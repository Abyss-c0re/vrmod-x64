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

--- Stereo RT UV crop for desktop blit.
--- desktopView: 1=none 2=left 3=right 4=follow-cam (no stereo crop — use DesktopCam RT)
--- Soft NaN/zero guards (offline + bad ScrW/H) without changing valid b1a5e9e math.
function vrmod.utils.ComputeDesktopCrop(desktopView, w, h)
    desktopView = tonumber(desktopView) or 1
    -- G23: only left/right eye crop; follow-cam and none skip stereo half-blit
    if desktopView == 4 or desktopView == 1 then
        return 0, 0
    end
    w = tonumber(w) or 0
    h = tonumber(h) or 0
    local sw = (ScrW and ScrW()) or 0
    local sh = (ScrH and ScrH()) or 0
    if w < 32 or h < 32 or not sw or sw < 1 or not sh or sh < 1 then
        return 0.05, desktopView == 3 and 0.5 or 0
    end
    local vmargin = (1 - sh / sw * w / 2 / h) / 2
    if vmargin ~= vmargin then vmargin = 0 end -- NaN
    if vmargin < 0 then vmargin = 0 end
    if vmargin > 0.45 then vmargin = 0.45 end
    local hoffset = desktopView == 3 and 0.5 or 0
    return vmargin, hoffset
end

--- UV submit bounds for the shared stereo RT (Cube: crop from *live* projection).
--- Never use Q2-era fixed 0.25/0.5 — those mis-crop asymmetric FOV HMDs.
---
--- scaleFactor: zoom crop around each eye half center (>1 = tighter = fill black bars)
--- hOffset/vOffset: manual pan in UV (fixed gain — always visible in calibration)
--- renderOffset: fold OpenXR per-eye Horizontal/VerticalOffset into pan
--- lensBend: pull rect toward eye-half center (lens map)
---
--- Platform: Windows V increases down (0→1); Linux/OpenGL V often inverted (1→0).
--- C++ collector + submit MUST honor these U and V (not U-only).
function vrmod.utils.ComputeSubmitBounds(leftCalc, rightCalc, hOffset, vOffset, scaleFactor, renderOffset, lensBend)
    local isWindows = system.IsWindows()
    leftCalc = leftCalc or {}
    rightCalc = rightCalc or {}
    scaleFactor = tonumber(scaleFactor) or 1
    if scaleFactor < 0.05 then scaleFactor = 0.05 end
    if scaleFactor > 4.0 then scaleFactor = 4.0 end
    lensBend = tonumber(lensBend) or 0
    if lensBend < -0.5 then lensBend = -0.5 end
    if lensBend > 0.5 then lensBend = 0.5 end
    hOffset = tonumber(hOffset) or 0
    vOffset = tonumber(vOffset) or 0

    local wL = tonumber(leftCalc.Width) or 1
    local wR = tonumber(rightCalc.Width) or 1
    local hL = tonumber(leftCalc.Height) or 1
    local hR = tonumber(rightCalc.Height) or 1
    local wAvg = math.max(0.05, (wL + wR) * 0.5)
    local hAvg = math.max(0.05, (hL + hR) * 0.5)
    -- Auto FOV asymmetry → small UV nudge (projection space)
    local hFactor = 0.5 / wAvg
    local vFactor = 1.0 / hAvg

    local useAuto = renderOffset and true or false
    local lo = useAuto and (tonumber(leftCalc.HorizontalOffset) or 0) or 0
    local ro = useAuto and (tonumber(rightCalc.HorizontalOffset) or 0) or 0
    local lv = useAuto and (tonumber(leftCalc.VerticalOffset) or 0) or 0
    local rv = useAuto and (tonumber(rightCalc.VerticalOffset) or 0) or 0

    -- Fixed manual pan gains (±1 slider always moves image)
    local MANUAL_U_GAIN = 0.22
    local MANUAL_V_GAIN = 0.45
    local panU = hOffset * MANUAL_U_GAIN
    local panV = vOffset * MANUAL_V_GAIN

    local TEXTURE_INSET = 0.003
    -- Zoom: half-span of each eye half at scale=1 is full half; larger scale → smaller span
    local halfU = math.max(0.02, 0.25 / scaleFactor)
    local halfV = math.max(0.02, 0.5 / scaleFactor)

    -- Work in top-left UV (y=0 top), then convert to platform V.
    -- Independent edge clamp (no re-expand): when pan pushes past 0/1 the
    -- window shrinks on that side — that is the visible offset at scale=1.
    local function eyeRect(cx, autoH, autoV)
        local adjU = autoH * hFactor + panU
        local adjV = autoV * vFactor + panV
        local u0 = cx - halfU + adjU
        local u1 = cx + halfU + adjU
        local y0 = 0.5 - halfV - adjV -- top
        local y1 = 0.5 + halfV - adjV -- bottom
        if u0 < 0 then u0 = 0 end
        if u1 > 1 then u1 = 1 end
        if y0 < 0 then y0 = 0 end
        if y1 > 1 then y1 = 1 end
        if u1 < u0 + 0.04 then
            local m = (u0 + u1) * 0.5
            if m < 0.02 then m = 0.02 end
            if m > 0.98 then m = 0.98 end
            u0, u1 = m - 0.02, m + 0.02
        end
        if y1 < y0 + 0.04 then
            local m = (y0 + y1) * 0.5
            if m < 0.02 then m = 0.02 end
            if m > 0.98 then m = 0.98 end
            y0, y1 = m - 0.02, m + 0.02
        end
        -- Lens bend: pull toward half center
        if math.abs(lensBend) > 1e-6 then
            local cu, cv = (u0 + u1) * 0.5, (y0 + y1) * 0.5
            u0 = u0 + (cu - u0) * lensBend
            u1 = u1 + (cu - u1) * lensBend
            y0 = y0 + (cv - y0) * lensBend
            y1 = y1 + (cv - y1) * lensBend
        end
        -- Inset
        u0 = u0 + TEXTURE_INSET
        u1 = u1 - TEXTURE_INSET
        y0 = y0 + TEXTURE_INSET
        y1 = y1 - TEXTURE_INSET
        -- Platform V
        if isWindows then
            return u0, y0, u1, y1
        end
        -- Linux/OpenGL: invert V (engine top → GL bottom-left convention)
        return u0, 1.0 - y0, u1, 1.0 - y1
    end

    local uMinLeft, vMinLeft, uMaxLeft, vMaxLeft = eyeRect(0.25, lo, lv)
    local uMinRight, vMinRight, uMaxRight, vMaxRight = eyeRect(0.75, ro, rv)

    -- Keep halves from crossing the SBS seam too far (soft)
    if uMaxLeft > 0.55 then uMaxLeft = 0.55 end
    if uMinRight < 0.45 then uMinRight = 0.45 end

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
function vrmod.utils.SubmitBounds_MirrorLeftToBoth(bounds)
	local b = bounds
	if type(b) ~= "table" then return bounds end
	local u0 = tonumber(b[1]) or 0
	local v0 = tonumber(b[2]) or 0
	local u1 = tonumber(b[3]) or 0.5
	local v1 = tonumber(b[4]) or 1
	return u0, v0, u1, v1, u0, v0, u1, v1
end
