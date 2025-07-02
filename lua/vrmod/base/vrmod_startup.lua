if SERVER then return end
local convars = vrmod.GetConvars()
local matLaser = Material("cable/redlaser")
local function drawLaser()
    if g_VR.viewModelMuzzle and not g_VR.menuFocus then
        render.SetMaterial(matLaser)
        render.DrawBeam(g_VR.viewModelMuzzle.Pos, g_VR.viewModelMuzzle.Pos + g_VR.viewModelMuzzle.Ang:Forward() * 10000, 1, 0, 1, Color(255, 255, 255, 255))
    end
end

-- Enable or disable laser
local function setLaserEnabled(enabled)
    if enabled then
        hook.Add("PostDrawTranslucentRenderables", "vr_laserpointer", drawLaser)
        if IsValid(LocalPlayer()) then
            LocalPlayer():ConCommand("vrmod_laserpointer 1")
        else
            timer.Simple(0, function() if IsValid(LocalPlayer()) then LocalPlayer():ConCommand("vrmod_laserpointer 1") end end)
        end
    else
        hook.Remove("PostDrawTranslucentRenderables", "vr_laserpointer")
        if IsValid(LocalPlayer()) then LocalPlayer():ConCommand("vrmod_laserpointer 0") end
    end
end

concommand.Add("vrmod", function(ply, cmd, args)
    if vgui.CursorVisible() then print("vrmod: menu will open when game is unpaused") end
    timer.Create("vrmod_open_menu", 0.1, 0, function()
        if not vgui.CursorVisible() then
            VRUtilOpenMenu()
            timer.Remove("vrmod_open_menu")
        end
    end)
end)

-- Toggle command
concommand.Add("vrmod_togglelaserpointer", function()
    local enabled = GetConVar("vrmod_laserpointer"):GetBool()
    setLaserEnabled(not enabled)
end)

-- Startup hook
hook.Add("VRMod_Start", "laserOn", function() timer.Simple(0.1, function() setLaserEnabled(true) end) end)
local convars = vrmod.AddCallbackedConvar("vrmod_showonstartup", nil, "0")
if convars.vrmod_showonstartup:GetBool() then
    hook.Add("CreateMove", "vrmod_showonstartup", function()
        hook.Remove("CreateMove", "vrmod_showonstartup")
        timer.Simple(1, function() RunConsoleCommand("vrmod") end)
    end)
end