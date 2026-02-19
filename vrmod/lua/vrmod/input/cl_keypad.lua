if CLIENT then
    local maxDistance = 35
    local originalCalculateCursorPos = nil
    local keypadFocusedEnt = nil
    local unpatched = true
    local cursorVisible = false
    local cursorPos = {
        x = 0,
        y = 0
    }

    local mat_beam = Material("cable/redlaser")
    local function CalculateCursorPos_VR(self)
        local ply = LocalPlayer()
        if not IsValid(ply) then return 0, 0 end
        local handPos = vrmod.GetRightHandPos(ply)
        if not handPos then return 0, 0 end
        -- Distance check here too: prevent cursor if hand too far
        if handPos:Distance(self:GetPos()) > maxDistance then return 0, 0 end
        local tr = vrmod.utils.TraceHand(ply, "right")
        if not tr or not tr.Hit or tr.Entity ~= self then return 0, 0 end
        local scale = self.Scale or 1
        local pos, ang = self:CalculateRenderPos(), self:CalculateRenderAng()
        local normal = self:GetForward()
        local intersection = util.IntersectRayWithPlane(tr.HitPos, -tr.Normal, pos, normal)
        if not intersection then return 0, 0 end
        local diff = pos - intersection
        local x = diff:Dot(-ang:Forward()) / scale
        local y = diff:Dot(-ang:Right()) / scale
        return x, y
    end

    local function PatchKeypadEntity(ent)
        if not IsValid(ent) then return end
        if ent.__VRPatched then return end
        ent.__VRPatched = true
        if not originalCalculateCursorPos and ent.CalculateCursorPos then originalCalculateCursorPos = ent.CalculateCursorPos end
        ent.Mins = ent:OBBMins()
        ent.Maxs = ent:OBBMaxs()
        ent.CalculateCursorPos = CalculateCursorPos_VR
    end

    local function UnpatchKeypadEntity(ent)
        if IsValid(ent) and ent.__VRPatched then
            ent.__VRPatched = nil
            if originalCalculateCursorPos then ent.CalculateCursorPos = originalCalculateCursorPos end
        end
    end

    local function UnpatchAllKeypads()
        for _, ent in ipairs(ents.FindByClass("Keypad")) do
            UnpatchKeypadEntity(ent)
        end

        for _, ent in ipairs(ents.FindByClass("Keypad_Wire")) do
            UnpatchKeypadEntity(ent)
        end
    end

    local function UpdateKeypadInteraction()
        local ply = LocalPlayer()
        if not IsValid(ply) or not g_VR.active then
            keypadFocusedEnt = nil
            cursorVisible = false
            gui.EnableScreenClicker(false)
            UnpatchAllKeypads()
            return
        end

        local tr = vrmod.utils.TraceHand(ply, "right")
        if not tr or not tr.Hit or not IsValid(tr.Entity) then
            keypadFocusedEnt = nil
            cursorVisible = false
            gui.EnableScreenClicker(false)
            UnpatchAllKeypads()
            return
        end

        local ent = tr.Entity
        local class = ent:GetClass()
        if class ~= "Keypad" and class ~= "Keypad_Wire" then
            keypadFocusedEnt = nil
            cursorVisible = false
            gui.EnableScreenClicker(false)
            UnpatchAllKeypads()
            return
        end

        local handPos = vrmod.GetRightHandPos(ply)
        if not handPos or handPos:Distance(ent:GetPos()) > maxDistance then
            -- Unpatch when player too far away so normal interaction works
            UnpatchKeypadEntity(ent)
            keypadFocusedEnt = nil
            cursorVisible = false
            gui.EnableScreenClicker(false)
            return
        end

        PatchKeypadEntity(ent)
        keypadFocusedEnt = ent
        cursorVisible = true
        local x, y = ent:CalculateCursorPos()
        if x == 0 and y == 0 then
            cursorVisible = false
            gui.EnableScreenClicker(false)
            keypadFocusedEnt = nil
            return
        end

        cursorPos.x, cursorPos.y = x, y
        gui.EnableScreenClicker(true)
    end

    hook.Add("Think", "VRMod_Keypad_Interaction", function()
        if not g_VR or not g_VR.active then
            if not unpatched then
                UnpatchAllKeypads()
                keypadFocusedEnt = nil
                cursorVisible = false
                gui.EnableScreenClicker(false)
                unpatched = true
            end
            return
        end

        UpdateKeypadInteraction()
        unpatched = false
    end)

    hook.Add("PostDrawTranslucentRenderables", "VRMod_Keypad_Beam", function()
        if not cursorVisible or not IsValid(keypadFocusedEnt) then return end
        local ply = LocalPlayer()
        local handPos = vrmod.GetRightHandPos(ply)
        local tr = vrmod.utils.TraceHand(ply, "right")
        local hitPos = tr and tr.Hit and tr.HitPos or keypadFocusedEnt:GetPos()
        render.SetMaterial(mat_beam)
        render.DrawBeam(handPos, hitPos, 0.1, 0, 1, Color(255, 255, 255, 255))
    end)

    hook.Add("VRMod_Input", "VRMod_Keypad_MouseInput", function(action, pressed)
        if not cursorVisible or not IsValid(keypadFocusedEnt) then return end
        local mouseButton = nil
        if action == "boolean_primaryfire" then mouseButton = MOUSE_LEFT end
        if mouseButton then
            if pressed then
                local hovered = keypadFocusedEnt:GetHoveredElement(cursorPos.x, cursorPos.y)
                if hovered and hovered.click then hovered.click(keypadFocusedEnt) end
                gui.InternalMousePressed(mouseButton)
            else
                gui.InternalMouseReleased(mouseButton)
            end
        end
    end)
end