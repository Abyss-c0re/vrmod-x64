if SERVER then util.AddNetworkString("VRButtonPresserMessage") end
-- CLIENT: Detect VR input and notify server
if CLIENT then
    local cl_interactive_buttons = CreateClientConVar("vrmod_interactive_buttons", "1", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
    hook.Add("VRMod_Input", "VRModButtonPresser", function(action, state)
        if not cl_interactive_buttons:GetBool() or not g_VR.active then return end
        -- Only act when the input is first pressed down
        if state then
            if action == "boolean_left_pickup" then
                net.Start("VRButtonPresserMessage")
                net.WriteBool(true) -- Left hand
                net.SendToServer()
            elseif action == "boolean_right_pickup" then
                net.Start("VRButtonPresserMessage")
                net.WriteBool(false) -- Right hand
                net.SendToServer()
            end
        end
    end)
end

-- SERVER: When client reports a press, check for nearby buttons and press them
if SERVER then
    local validClasses = {
        ["func_button"] = true,
        ["func_rot_button"] = true,
        ["item_healthcharger"] = true,
        ["item_suitcharger"] = true,
        ["item_ammo_crate"] = true,
        ["func_door_rotating"] = true,
        ["gmod_button"] = true,
        ["gmod_wire_button"] = true,
        ["sent_button"] = true
    }

    net.Receive("VRButtonPresserMessage", function(_, ply)
        if not ply:Alive() then return end
        local isLeftHand = net.ReadBool()
        local handPos = isLeftHand and vrmod.GetLeftHandPos(ply) or vrmod.GetRightHandPos(ply)
        if not handPos then return end
        local nearby = ents.FindInSphere(handPos, 5)
        for _, ent in ipairs(nearby) do
            if validClasses[ent:GetClass()] then
                ent:Use(ply)
                break
            end
        end
    end)
end