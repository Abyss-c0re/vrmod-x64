print("running vr button presser")
if SERVER then
    util.AddNetworkString("VRButtonPresserMessage") -- once again preparing a network string, this is needed to determine when the VR player makes a controller input
end

----------------------------------------------------------------------------
if CLIENT then -- there has to be a client element because only the client can 'see' a player's VR controller inputs
    hook.Add("VRMod_Input", "VRModButtonPresser", function(action, state)
        -- hook that fires whenever any VR input is made
        if action == "boolean_left_pickup" then -- checks if the input is actually the one we want (in this case, it's the input for closing your hand)
            net.Start("VRButtonPresserMessage")
            net.WriteBool(true) -- sends a 'true' boolean if it is the left hand
            net.WriteBool(state) -- another boolean, but used only to determine if the input is being held down or not
            net.SendToServer()
        else -- same thing as above but for the right hand
            if action == "boolean_right_pickup" then
                net.Start("VRButtonPresserMessage")
                net.WriteBool(false) -- the 'false' boolean, used to identify the right hand
                net.WriteBool(state)
                net.SendToServer()
            end
        end
    end)
end

----------------------------------------------------------------------------
if SERVER then
    net.Receive("VRButtonPresserMessage", function(len, ply)
        -- receives the net message configured above, and it includes information about the controller input
        local bInputLeft = net.ReadBool() -- if this bool is true, that means the input came from the left hand - if it's false, then it was the right hand
        local PushingButton = net.ReadBool() -- the earlier mentioned boolean that only checks if the input is currently being held down
        if bInputLeft then -- distinguishes the right hand from the left hand
            ply.PushButtonLeft = PushingButton
        else
            ply.PushButtonRight = PushingButton
        end
    end)

    hook.Add("PlayerTick", "VRButtonTicker", function(ply)
        -- this hook is needed to continuously fire the 'use' input later on - 
        -- this will be used to immediately activate the button when you move your hand to it, thus simulating a physical button press
        if not ply:Alive() then -- checks if the player is alive, so we can just ignore all the code below if the player is dead - so you can't activate buttons while dead
            ply.PushButtonLeft = false
            ply.PushButtonRight = false
            return
        end

        if ply.PushButtonRight then
            local HandLocationRight = vrmod.GetRightHandPos(ply) -- this is used to obtain your current hand's position
            local FoundButtonsRight = ents.FindInSphere(HandLocationRight, 5) -- this places a spherical hitbox at your hand's position, with a size of 5 units - any button found inside this hitbox will be marked to activate
            for k, v in ipairs(FoundButtonsRight) do -- a 'k, v in ipairs' loop gets a list of objects (in this case, the button we found through the hitbox) and processes each object in the list once
                -- this is needed because it's possible you might touch two buttons at once, which needs to be accounted for
                if v:GetClass() == "func_button" or v:GetClass() == "func_rot_button" or v:GetClass() == "item_healthcharger" or v:GetClass() == "item_suitcharger" or v:GetClass() == "item_ammo_crate" or v:GetClass() == "func_door_rotating" then -- checks the entity your hand touched to see if it's actually a button or other pressable entity - if not, it will do nothing
                    v:Use(ply) -- if it actually is a button though, it will activate it
                    break -- breaks the loop when the button is pressed so this function doesn't run infinite times per second
                end
            end
        end

        -- this next block of code is the same thing as above, but for the left hand - thus no explanation is needed
        if ply.PushButtonLeft then
            local HandLocationLeft = vrmod.GetLeftHandPos(ply)
            local FoundButtonsLeft = ents.FindInSphere(HandLocationLeft, 5)
            for k, v in ipairs(FoundButtonsLeft) do
                if v:GetClass() == "func_button" or v:GetClass() == "func_rot_button" or v:GetClass() == "item_healthcharger" or v:GetClass() == "item_suitcharger" or v:GetClass() == "item_ammo_crate" or v:GetClass() == "func_door_rotating" then
                    v:Use(ply)
                    break
                end
            end
        end
    end)
end

hook.Add("PlayerUse", "NoTelepathicButtonPressing", function(ply, ent)
    -- this is here to stop VR players with this addon from activating buttons through the 'regular' use function - meaning they could activate buttons from a distance, without touching them
    if ent:GetClass() == "func_button" and vrmod.IsPlayerInVR(ply) or ent:GetClass() == "func_rot_button" and vrmod.IsPlayerInVR(ply) or ent:GetClass() == "item_healthcharger" and vrmod.IsPlayerInVR(ply) or ent:GetClass() == "item_suitcharger" and vrmod.IsPlayerInVR(ply) or ent:GetClass() == "item_ammo_crate" and vrmod.IsPlayerInVR(ply) then return false end
end)
-- if v:GetClass() == "func_button" or "func_rot_button" or "item_healthcharger" or "item_suitcharger" or "item_ammo_crate" or "func_door_rotating" then
-- attempted to do this list in a (i think) more efficient way at some point, but then it stopped working for some reason