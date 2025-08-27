local cl_debug_collisions = CreateClientConVar("vrmod_debug_collisions", "0", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local function DebugEnabled()
    local cv = GetConVar("vrmod_debug_collision_info")
    return cv and cv:GetBool() or false
end

if SERVER then
    CreateConVar("vrmod_collisions", "1", FCVAR_ARCHIVE + FCVAR_NOTIFY + FCVAR_REPLICATED, "Enable VR hand collision correction")
    util.AddNetworkString("vrmod_sync_model_params")
    net.Receive("vrmod_sync_model_params", function(len, ply)
        local modelPath = net.ReadString()
        local params = {
            radius = net.ReadFloat(),
            reach = net.ReadFloat(),
            mins_horizontal = net.ReadVector(),
            maxs_horizontal = net.ReadVector(),
            mins_vertical = net.ReadVector(),
            maxs_vertical = net.ReadVector(),
            angles = net.ReadAngle(),
            computed = true,
            sent = true
        }

        -- Only update + rebroadcast if different or unseen
        local old = vrmod.modelCache[modelPath]
        if not old or old.radius ~= params.radius or old.reach ~= params.reach or old.mins_horizontal ~= params.mins_horizontal or old.maxs_horizontal ~= params.maxs_horizontal or old.mins_vertical ~= params.mins_vertical or old.maxs_vertical ~= params.maxs_vertical or old.angles ~= params.angles then
            if DebugEnabled() then vrmod.logger.Info("Server received NEW collision params for %s from %s", modelPath, ply:Nick()) end
            vrmod.modelCache[modelPath] = params
            net.Start("vrmod_sync_model_params")
            net.WriteString(modelPath)
            net.WriteFloat(params.radius)
            net.WriteFloat(params.reach)
            net.WriteVector(params.mins_horizontal)
            net.WriteVector(params.maxs_horizontal)
            net.WriteVector(params.mins_vertical)
            net.WriteVector(params.maxs_vertical)
            net.WriteAngle(params.angles)
            net.Broadcast()
            if DebugEnabled() then vrmod.logger.Info("Broadcasted collision params for %s to all clients", modelPath) end
        else
            if DebugEnabled() then vrmod.logger.Info("Ignored duplicate collision params for %s from %s", modelPath, ply:Nick()) end
        end
    end)

    hook.Add("PlayerInitialSpawn", "VRMod_Sendvrmod.modelCache", function(ply)
        for modelPath, params in pairs(vrmod.modelCache) do
            if params.computed then
                net.Start("vrmod_sync_model_params")
                net.WriteString(modelPath)
                net.WriteFloat(params.radius)
                net.WriteFloat(params.reach)
                net.WriteVector(params.mins_horizontal)
                net.WriteVector(params.maxs_horizontal)
                net.WriteVector(params.mins_vertical)
                net.WriteVector(params.maxs_vertical)
                net.WriteAngle(params.angles)
                net.Send(ply)
                if DebugEnabled() then vrmod.logger.Info("Synced cached collision params for %s to %s", modelPath, ply:Nick()) end
            end
        end
    end)

    cvars.AddChangeCallback("vrmod_collisions", function(cvar, old, new)
        for _, ply in ipairs(player.GetAll()) do
            ply:SetNWBool("vrmod_server_enforce_collision", tobool(new))
        end
    end)

    hook.Add("VRMod_Start", "SendCollisionState", function(ply) ply:SetNWBool("vrmod_server_enforce_collision", GetConVar("vrmod_collisions"):GetBool()) end)
end

if CLIENT then
    net.Receive("vrmod_sync_model_params", function()
        local modelPath = net.ReadString()
        local params = {
            radius = net.ReadFloat(),
            reach = net.ReadFloat(),
            mins_horizontal = net.ReadVector(),
            maxs_horizontal = net.ReadVector(),
            mins_vertical = net.ReadVector(),
            maxs_vertical = net.ReadVector(),
            angles = net.ReadAngle(),
            computed = true
        }

        if DebugEnabled() then vrmod.logger.Debug("Received synced collision params for %s from server", modelPath) end
        vrmod.modelCache[modelPath] = params
    end)

    hook.Add("PostDrawOpaqueRenderables", "VRMod_HandDebugShapes", function()
        if not cl_debug_collisions:GetBool() or not g_VR.active then return end
        local ply = LocalPlayer()
        if not IsValid(ply) or not ply:Alive() or not vrmod.IsPlayerInVR(ply) then return end
        render.SetColorMaterial()
        for i = 1, #vrmod.collisionSpheres do
            local s = vrmod.collisionSpheres[i]
            render.DrawWireframeSphere(s.pos, s.radius, 16, 16, s.hit and Color(255, 255, 0, 100) or Color(255, 0, 0, 150))
        end

        for i = 1, #vrmod.collisionBoxes do
            local b = vrmod.collisionBoxes[i]
            render.DrawWireframeBox(b.pos, b.angles, b.mins, b.maxs, b.hit and Color(255, 255, 0, 100) or Color(0, 255, 0, 150))
        end
    end)
end