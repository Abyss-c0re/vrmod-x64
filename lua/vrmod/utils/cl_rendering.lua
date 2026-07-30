g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}
function vrmod.utils.CalculateProjectionParams(projMatrix, worldScale)
    local xscale = projMatrix[1][1]
    local xoffset = projMatrix[1][3]
    local yscale = projMatrix[2][2]
    local yoffset = projMatrix[2][3]
    -- ** Normalize vertical sign: **
    if not system.IsWindows() then
        -- On Linux/OpenGL: invert the sign so + means “down” just like on Windows
        yoffset = -yoffset
    end

    -- now the rest is identical on both platforms:
    local tan_px = math.abs((1 - xoffset) / xscale)
    local tan_nx = math.abs((-1 - xoffset) / xscale)
    local tan_py = math.abs((1 - yoffset) / yscale)
    local tan_ny = math.abs((-1 - yoffset) / yscale)
    local w = (tan_px + tan_nx) / worldScale
    local h = (tan_py + tan_ny) / worldScale
    return {
        HorizontalFOV = math.deg(2 * math.atan(w / 2)),
        AspectRatio = w / h,
        HorizontalOffset = xoffset,
        VerticalOffset = yoffset,
        Width = w,
        Height = h,
    }
end

function vrmod.utils.ComputeDesktopCrop(desktopView, w, h)
    local vmargin = (1 - ScrH() / ScrW() * w / 2 / h) / 2
    local hoffset = desktopView == 3 and 0.5 or 0
    return vmargin, hoffset
end

--- UV submit bounds for the shared stereo RT (Cube: crop from *live* projection).
--- Never use Q2-era fixed 0.25/0.5 — those mis-crop asymmetric FOV HMDs.
--- renderOffset=true  → apply OpenVR per-eye Horizontal/VerticalOffset
--- renderOffset=false → manual H/V sliders only; factors still from projection Width/Height
function vrmod.utils.ComputeSubmitBounds(leftCalc, rightCalc, hOffset, vOffset, scaleFactor, renderOffset)
    local isWindows = system.IsWindows()
    leftCalc = leftCalc or {}
    rightCalc = rightCalc or {}
    scaleFactor = scaleFactor or 1

    local wL = tonumber(leftCalc.Width) or 1
    local wR = tonumber(rightCalc.Width) or 1
    local hL = tonumber(leftCalc.Height) or 1
    local hR = tonumber(rightCalc.Height) or 1
    local wAvg = math.max(0.05, (wL + wR) * 0.5)
    local hAvg = math.max(0.05, (hL + hR) * 0.5)

    -- Always derive UV scale from live projection extent (not fixed Q2 constants)
    local hFactor = (0.5 / wAvg) * scaleFactor
    local vFactor = (1.0 / hAvg) * scaleFactor

    -- Auto-offset: fold asymmetric FOV into crop. Manual: only creator H/V sliders.
    local useAuto = renderOffset and true or false
    local lo = useAuto and (tonumber(leftCalc.HorizontalOffset) or 0) or 0
    local ro = useAuto and (tonumber(rightCalc.HorizontalOffset) or 0) or 0
    local lv = useAuto and (tonumber(leftCalc.VerticalOffset) or 0) or 0
    local rv = useAuto and (tonumber(rightCalc.VerticalOffset) or 0) or 0
    hOffset = tonumber(hOffset) or 0
    vOffset = tonumber(vOffset) or 0

    local TEXTURE_INSET = 0.003
    local vMin, vMax = isWindows and 0 or 1, isWindows and 1 or 0
    local function calcVMinMax(eyeVOffset)
        local adj = (eyeVOffset + vOffset) * vFactor
        if isWindows then
            return (vMin + TEXTURE_INSET) - adj, (vMax - TEXTURE_INSET) - adj
        else
            return (vMin - TEXTURE_INSET) - adj, (vMax + TEXTURE_INSET) - adj
        end
    end

    -- U: outer only (inner seam at 0.5 untouched)
    local uMinLeft = 0.0 + TEXTURE_INSET + (lo + hOffset) * hFactor
    local uMaxLeft = 0.5 + (lo + hOffset) * hFactor
    local uMinRight = 0.5 + (ro + hOffset) * hFactor
    local uMaxRight = 1.0 - TEXTURE_INSET + (ro + hOffset) * hFactor
    local vMinLeft, vMaxLeft = calcVMinMax(lv)
    local vMinRight, vMaxRight = calcVMinMax(rv)
    return uMinLeft, vMinLeft, uMaxLeft, vMaxLeft, uMinRight, vMinRight, uMaxRight, vMaxRight
end

function vrmod.utils.AdjustFOV(proj, fovScaleX, fovScaleY)
    local clone = {}
    for i = 1, 4 do
        clone[i] = {proj[i][1], proj[i][2], proj[i][3], proj[i][4]}
    end

    -- scale the FOV (diagonal terms)
    clone[1][1] = clone[1][1] * fovScaleX
    clone[2][2] = clone[2][2] * fovScaleY
    -- scale the center offset (asymmetry) terms
    clone[1][3] = clone[1][3] * fovScaleX
    clone[2][3] = clone[2][3] * fovScaleY
    return clone
end

function vrmod.utils.DrawDeathAnimation(rtWidth, rtHeight)
    if not g_VR.deathTime then g_VR.deathTime = CurTime() end
    local fadeAlpha = 0
    local fadeDuration = 3.5
    local maxAlpha = 200
    local progress = math.min((CurTime() - g_VR.deathTime) / fadeDuration, 1)
    fadeAlpha = math.min(progress * maxAlpha, maxAlpha)
    cam.Start2D()
    surface.SetDrawColor(120, 0, 0, fadeAlpha)
    surface.DrawRect(0, 0, rtWidth, rtHeight)
    cam.End2D()
end