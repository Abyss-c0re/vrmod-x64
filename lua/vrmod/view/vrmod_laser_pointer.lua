if CLIENT then
    local convars = vrmod.GetConvars()
    local blacklist = {
        ["arcticvr_hl2_cmbsniper"] = true,
        ["arcticvr_hl2_crowbar"] = true,
        ["arcticvr_hl2_stunstick"] = true,
        ["arcticvr_hl2_rpg"] = true,
        ["arcticvr_knife"] = true,
        ["laserpointer"] = true,
        ["seal6_c4"] = true,
        ["seal6_bottle"] = true,
        ["seal6_doritos"] = true,
        ["weapon_physgun"] = true,
        ["weapon_newtphysgun"] = true,
        ["weapon_physcannon"] = true,
        ["weapon_crowbar"] = true,
        ["weapon_stunstick"] = true,
        ["weapon_medkit"] = true,
        ["weapon_rpg"] = true,
        ["weapon_extinguisher"] = true,
        ["weapon_extinguisher_infinte"] = true,
        ["weapon_bomb"] = true,
        ["weapon_c4"] = true,
        ["weapon_vfire_gascan"] = true
    }

    -- Default laser color
    local laserColor = Color(255, 0, 0, 255)
    -- Custom laser beam material with vertex color support
    local LaserMaterial = Material("cable/red") -- fallback
    do
        local matData = {
            ["$basetexture"] = "color/white",
            ["$additive"] = "1", -- Glowing effect
            ["$vertexcolor"] = "1", -- Use per-vertex color
            ["$vertexalpha"] = "1", -- Use per-vertex alpha
            ["$nocull"] = "1", -- Make it visible from both sides
            ["$ignorez"] = "0", -- Depth-aware (optional)
        }

        local success, customMat = pcall(CreateMaterial, "CustomLaserMaterial", "UnlitGeneric", matData)
        if success and customMat then LaserMaterial = customMat end
    end

    -- Glow sprite material
    local GlowSprite = Material("sprites/glow04_noz")
    -- Update laserColor from convar string
    local function UpdateLaserColor(colorString)
        local r, g, b, a = string.match(colorString, "(%d+),(%d+),(%d+),(%d+)")
        if not (r and g and b and a) then return end
        laserColor = Color(tonumber(r), tonumber(g), tonumber(b), tonumber(a))
    end

    -- ConVar listener for dynamic updates
    vrmod.AddCallbackedConvar("vrmod_laser_color", nil, "255,0,0,255", nil, "", nil, nil, nil, function(newValue) UpdateLaserColor(newValue) end)
    -- Flicker width for beam animation
    local function getFlickerWidth()
        return 0.05 + math.abs(math.sin(CurTime() * 40)) * 0.05
    end

    -- Beam + glow rendering
    local function drawLaser()
        if not g_VR.viewModelMuzzle or g_VR.menuFocus then return end
        local wep = LocalPlayer():GetActiveWeapon()
        if not IsValid(wep) or blacklist[wep:GetClass()] then return end
        local startPos = g_VR.viewModelMuzzle.Pos
        local dir = g_VR.viewModelMuzzle.Ang:Forward()
        local endPos = startPos + dir * 10000
        local tr = util.TraceLine({
            start = startPos,
            endpos = endPos,
            filter = LocalPlayer(),
        })

        local function ScaleAlpha(col, scale)
            return Color(col.r, col.g, col.b, math.Clamp(col.a * scale, 0, 255))
        end

        -- Draw laser beam
        render.SetMaterial(LaserMaterial)
        render.DrawBeam(startPos, tr.HitPos, getFlickerWidth(), 0, 1, laserColor)
        -- Draw muzzle glow (slightly smaller)
        render.SetMaterial(GlowSprite)
        render.DrawSprite(startPos, 1, 1, laserColor)
        -- Draw hit glow if beam hits something
        if tr.Hit then render.DrawSprite(tr.HitPos + tr.HitNormal * 1, 8, 8, ScaleAlpha(laserColor, 1.2)) end
    end

    local function setLaserEnabled(enabled)
        if enabled then
            hook.Add("PostDrawTranslucentRenderables", "vr_laserpointer", drawLaser)
        else
            hook.Remove("PostDrawTranslucentRenderables", "vr_laserpointer")
        end

        -- Persist state in convar
        RunConsoleCommand("vrmod_laserpointer", enabled and "1" or "0")
    end

    -- Console command to toggle laser
    concommand.Add("vrmod_togglelaserpointer", function()
        local enabled = GetConVar("vrmod_laserpointer"):GetBool()
        setLaserEnabled(not enabled)
    end)

    -- Activate laser if convar is set on VR start
    hook.Add("VRMod_Start", "laserOn", function()
        timer.Simple(0.1, function()
            if GetConVar("vrmod_laserpointer"):GetBool() then setLaserEnabled(true) end
            -- Force update laser color from current convar value
            local laserColorConvar = GetConVar("vrmod_laser_color")
            if laserColorConvar then UpdateLaserColor(laserColorConvar:GetString()) end
        end)
    end)
end