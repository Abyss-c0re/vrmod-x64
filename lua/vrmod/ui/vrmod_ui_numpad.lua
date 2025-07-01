if CLIENT then
    local open = false
    local wasClicking = false
    local justClicked = false
    local holdKey = nil
    local holdStart = 0
    local holdDelay = 0.5
    local holdRate = 0.1
    local keyMap = {
        ["1"] = KEY_PAD_1,
        ["2"] = KEY_PAD_2,
        ["3"] = KEY_PAD_3,
        ["4"] = KEY_PAD_4,
        ["5"] = KEY_PAD_5,
        ["6"] = KEY_PAD_6,
        ["7"] = KEY_PAD_7,
        ["8"] = KEY_PAD_8,
        ["9"] = KEY_PAD_9,
        ["0"] = KEY_PAD_0,
        ["CLR"] = KEY_BACKSPACE,
        ["ENT"] = KEY_PAD_ENTER,
        ["+"] = KEY_PAD_PLUS,
        ["-"] = KEY_PAD_MINUS,
        ["*"] = KEY_PAD_MULTIPLY,
    }

    local keys = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "CLR", "0", "ENT", "+", "-", "*"}
    local function emitKey(name, down)
        local code = keyMap[name]
        if not code then return end
        net.Start("vrmod_numpad_emit")
        net.WriteUInt(code, 8)
        net.WriteBool(down)
        net.SendToServer()
    end

    function VRUtilNumpadMenuOpen()
        if open then return end
        open = true
        VRUtilMenuOpen("numpadmenu", 512, 512, nil, true, Vector(6, -10, 5.5), Angle(0, -90, 55), 0.03, true, function()
            hook.Remove("PreRender", "vrutil_hook_rendernumpad")
            hook.Remove("VRMod_Input", "vrmod_numpad_clickdetect")
            hook.Remove("Think", "vrmod_numpad_holdrepeat")
            -- Release any held key on close
            if holdKey then
                emitKey(holdKey, false)
                holdKey = nil
            end

            wasClicking = false
            justClicked = false
            open = false
        end)

        hook.Add("VRMod_Input", "vrmod_numpad_clickdetect", function(action, pressed)
            local clickInCar = LocalPlayer():InVehicle() and action == "boolean_right_pickup"
            if action == "boolean_primaryfire" or clickInCar then
                justClicked = pressed and not wasClicking
                wasClicking = pressed
                if not pressed and holdKey then
                    emitKey(holdKey, false)
                    holdKey = nil
                end
            end
        end)

        hook.Add("PreRender", "vrutil_hook_rendernumpad", function()
            if not VRUtilIsMenuOpen("numpadmenu") then return end
            if not g_VR.menuCursorX then return end
            local cx, cy = g_VR.menuCursorX, g_VR.menuCursorY
            local bw, bh, pad = 100, 100, 10
            local gridW = 3 * bw + 2 * pad
            local gridH = 5 * bh + 4 * pad
            local scaleX = 512 / gridW
            local scaleY = 512 / gridH
            local scale = math.min(scaleX, scaleY)
            bw = bw * scale
            bh = bh * scale
            pad = pad * scale
            VRUtilMenuRenderStart("numpadmenu")
            for i = 0, #keys - 1 do
                local col = i % 3
                local row = math.floor(i / 3)
                local x = col * (bw + pad)
                local y = row * (bh + pad)
                local key = keys[i + 1]
                local hovered = cx > x and cx < x + bw and cy > y and cy < y + bh
                draw.RoundedBox(8, x, y, bw, bh, Color(0, 0, 0, hovered and 200 or 100))
                draw.SimpleText(key, "DermaLarge", x + bw / 2, y + bh / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                if hovered and justClicked then
                    emitKey(key, true)
                    holdKey = key
                    holdStart = SysTime()
                end
            end

            VRUtilMenuRenderEnd()
            justClicked = false
        end)

        hook.Add("Think", "vrmod_numpad_holdrepeat", function()
            if not holdKey then return end
            if not wasClicking then
                emitKey(holdKey, false)
                holdKey = nil
                return
            end

            local dt = SysTime() - holdStart
            if dt >= holdDelay then
                emitKey(holdKey, true)
                holdStart = holdStart + holdRate
            end
        end)
    end

    function VRUtilNumpadMenuClose()
        VRUtilMenuClose("numpadmenu")
    end

    concommand.Add("vrmod_numpad", function()
        if VRUtilIsMenuOpen("numpadmenu") then
            VRUtilNumpadMenuClose()
        else
            VRUtilNumpadMenuOpen()
        end
    end)
end

if SERVER then
    util.AddNetworkString("vrmod_numpad_emit")
    net.Receive("vrmod_numpad_emit", function(len, ply)
        local key = net.ReadUInt(8)
        local down = net.ReadBool()
        if down then
            numpad.Activate(ply, key, true)
        else
            numpad.Deactivate(ply, key, true)
        end
    end)
end