g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}
vrmod.suppressViewModelUpdates = false

--- Clip + reserve for HUD / weapon select.
-- ArcVR does not keep Clip1() in sync — use LoadedRounds + Chambered.
function vrmod.utils.GetWeaponAmmoDisplay(wep, ply)
	ply = ply or LocalPlayer()
	if not IsValid(wep) then return -1, -1 end
	local clip = -1
	local reserve = -1

	if wep.ArcticVR or wep.ArcticVRNade then
		-- Mag in gun + chamber (client fields updated by avr_magin_forclient / shoot)
		local loaded = tonumber(wep.LoadedRounds) or 0
		local chamber = tonumber(wep.Chambered) or 0
		clip = loaded + chamber
		-- Mag entity still held separately may report Rounds
		if IsValid(wep.Magazine) and wep.Magazine.Rounds then
			-- LoadedRounds already mirrors inserted mag; only use mag if Loaded empty but mag present
			if loaded <= 0 and not wep.InternalMagazine then
				clip = (tonumber(wep.Magazine.Rounds) or 0) + chamber
			end
		end
	elseif wep.Clip1 then
		clip = wep:Clip1() or -1
	end

	if IsValid(ply) then
		local at = wep.GetPrimaryAmmoType and wep:GetPrimaryAmmoType() or -1
		if isnumber(at) and at >= 0 then
			reserve = ply:GetAmmoCount(at) or 0
		elseif wep.Primary and wep.Primary.Ammo then
			reserve = ply:GetAmmoCount(wep.Primary.Ammo) or 0
		end
	end
	return clip, reserve
end

-- WEP UTILS
function vrmod.utils.CreateWorldModelVM(class, vmi)
    if not IsValid(g_VR.worldModelVM) then
        local model = vmi and vmi.modelOverride
        if not model then
            local wep = LocalPlayer():GetActiveWeapon()
            if IsValid(wep) then
                model = wep:GetModel()
            end
        end
        if not model or model == "" then return end

        g_VR.worldModelVM = ClientsideModel(model)
        if not IsValid(g_VR.worldModelVM) then return end
        g_VR.worldModelVM:SetNoDraw(false)
        local vm = LocalPlayer():GetViewModel()
        if IsValid(vm) then
            g_VR.worldModelVM:SetParent(vm) -- temporary parent
        end
        g_VR.worldModelVM:DrawShadow(false)
    end

    g_VR.viewModel = g_VR.worldModelVM
end

function vrmod.utils.IsValidWep(wep, get)
    if not IsValid(wep) then return false end
    local class = wep:GetClass()
    local vm
    vm = wep:GetWeaponViewModel()
    if class == "weapon_vrmod_empty" or vm == "" or vm == "models/weapons/c_arms.mdl" then return false end
    if get then
        return class, vm
    else
        return true
    end
end

function vrmod.utils.IsWeaponEntity(ent)
    if not IsValid(ent) then return false end
    local c = ent:GetClass()
    if not c then return false end
    if ent:IsWeapon() or c:find("weapon_") then return true end
    -- Safe check for weapon models on prop_physics
    if c == "prop_physics" then
        local mdl = ent:GetModel()
        if mdl and mdl:find("w_") then return true end
    end
    return false
end

function vrmod.utils.WepInfo(wep)
    local class, vm = vrmod.utils.IsValidWep(wep, true)
    if class and vm then return class, vm end
end

--- Viewmodel / gun is a pure slave of g_VR.tracking.pose_righthand (SoT).
--- Never read rawTracking here — wall collision overrides tracking in place;
--- raw device energy stays elsewhere for consumers that need unfiltered sample.
--- Ensure every stock weapon has a VMI so pose/laser never skip the hand slave path.
local function EnsureCurrentVMI(ply)
    local vmi = g_VR.currentvmi
    if vmi and vmi.offsetPos and vmi.offsetAng then return vmi end
    local wep = IsValid(ply) and ply:GetActiveWeapon() or nil
    local class = IsValid(wep) and wep:GetClass() or nil
    if class and g_VR.viewModelInfo and g_VR.viewModelInfo[class] then
        local entry = g_VR.viewModelInfo[class]
        if not entry.offsetPos then entry.offsetPos = Vector(0, 0, 0) end
        if not entry.offsetAng then entry.offsetAng = Angle(0, 0, 0) end
        g_VR.currentvmi = entry
        return entry
    end
    -- Ephemeral default for unconfigured stock weapons
    if not g_VR.currentvmi then
        g_VR.currentvmi = { offsetPos = Vector(0, 0, 0), offsetAng = Angle(0, 0, 0) }
    else
        if not g_VR.currentvmi.offsetPos then g_VR.currentvmi.offsetPos = Vector(0, 0, 0) end
        if not g_VR.currentvmi.offsetAng then g_VR.currentvmi.offsetAng = Angle(0, 0, 0) end
    end
    return g_VR.currentvmi
end

function vrmod.utils.UpdateViewModelPos(pos, ang, override)
    local ply = LocalPlayer()
    if vrmod.suppressViewModelUpdates and not override then
        vrmod.utils.UpdateViewModel()
        return
    end

    if not IsValid(ply) or not g_VR.active then return end
    if not ply:Alive() then return end
    local currentvmi = EnsureCurrentVMI(ply)

    -- override=true + pos/ang: use those hands (foregrip guided aim).
    -- Otherwise prefer tracking SoT (post wall override); args are optional hints.
    local handPos, handAng
    if override and pos and ang then
        handPos, handAng = pos, ang
    else
        local hand = g_VR.tracking and g_VR.tracking.pose_righthand
        if hand and hand.pos and hand.ang then
            handPos, handAng = hand.pos, hand.ang
        else
            handPos, handAng = pos, ang
        end
    end
    if not handPos or not handAng then return end

    local offsetPos, offsetAng = LocalToWorld(currentvmi.offsetPos or Vector(), currentvmi.offsetAng or Angle(), handPos, handAng)
    g_VR.viewModelPos = offsetPos
    g_VR.viewModelAng = offsetAng
    -- Pass the same hand so UpdateViewModel does not re-read tracking and stomp guided pose
    vrmod.utils.UpdateViewModel(handPos, handAng)
end

--- Optional handPos/handAng: pose from these instead of tracking (guided foregrip).
function vrmod.utils.UpdateViewModel(handPos, handAng)
    local vm = g_VR.viewModel
    if not IsValid(vm) then
        -- Fall back to engine viewmodel for stock weapons
        local ply = LocalPlayer()
        if IsValid(ply) then
            vm = ply:GetViewModel()
            if IsValid(vm) then g_VR.viewModel = vm end
        end
    end
    if not IsValid(vm) then return end

    local vmi = g_VR.currentvmi or EnsureCurrentVMI(LocalPlayer())
    local hand = g_VR.tracking and g_VR.tracking.pose_righthand
    if not (handPos and handAng) and hand and hand.pos and hand.ang then
        handPos, handAng = hand.pos, hand.ang
    end

    if vmi and vmi.useWorldModel and handPos and handAng then
        local off = vmi.offsetPos or Vector()
        local oang = vmi.offsetAng or Angle()
        local pos = handPos + handAng:Forward() * off.x + handAng:Right() * off.y + handAng:Up() * off.z
        local ang = Angle(handAng.p, handAng.y, handAng.r)
        ang:RotateAroundAxis(ang:Right(), oang.p or 0)
        ang:RotateAroundAxis(ang:Up(), oang.y or 0)
        ang:RotateAroundAxis(ang:Forward(), oang.r or 0)
        g_VR.viewModelPos = pos
        g_VR.viewModelAng = ang
        vm:SetPos(pos)
        vm:SetAngles(ang)
        vm:SetupBones()
    else
        if handPos and handAng and vmi then
            local offsetPos, offsetAng = LocalToWorld(vmi.offsetPos or Vector(), vmi.offsetAng or Angle(), handPos, handAng)
            g_VR.viewModelPos = offsetPos
            g_VR.viewModelAng = offsetAng
        end
        if g_VR.viewModelPos and g_VR.viewModelAng then
            vm:SetPos(g_VR.viewModelPos)
            vm:SetAngles(g_VR.viewModelAng)
            vm:SetupBones()
        end
    end

    -- Muzzle: attachment near hand, else synthesize tip from gun pose (stock weapons)
    local muz = vm:GetAttachment(1)
    if (not muz or not muz.Pos) and isfunction(vm.GetAttachments) then
        local atts = vm:GetAttachments()
        if istable(atts) then
            for _, a in ipairs(atts) do
                local n = string.lower(tostring(a.name or ""))
                local id = a.id or a.ID
                if id and (n:find("muzzle", 1, true) or n:find("laser", 1, true) or n:find("muzzle_flash", 1, true)) then
                    muz = vm:GetAttachment(id)
                    if muz and muz.Pos then break end
                end
            end
        end
    end
    if muz and muz.Pos and hand and hand.pos then
        if muz.Pos:DistToSqr(hand.pos) > (100 * 100) then
            muz = nil -- stale/world-origin att
        end
    end
    -- Synthesize muzzle table for laser if attachment missing
    if (not muz or not muz.Pos) and g_VR.viewModelPos and g_VR.viewModelAng then
        local tip = g_VR.viewModelPos + g_VR.viewModelAng:Forward() * 14
        muz = { Pos = tip, Ang = Angle(g_VR.viewModelAng.p, g_VR.viewModelAng.y, g_VR.viewModelAng.r) }
    end
    g_VR.viewModelMuzzle = muz
end