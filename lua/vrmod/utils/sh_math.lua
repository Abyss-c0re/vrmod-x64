g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

function vrmod.utils.VecAlmostEqual(v1, v2, threshold)
    if not v1 or not v2 then return false end
    return v1:DistToSqr(v2) < (threshold or 0.05) ^ 2
end

function vrmod.utils.AngAlmostEqual(a1, a2, threshold)
    if not a1 or not a2 then return false end
    threshold = threshold or 0.5 -- degrees
    return math.abs(math.AngleDifference(a1.p, a2.p)) < threshold and math.abs(math.AngleDifference(a1.y, a2.y)) < threshold and math.abs(math.AngleDifference(a1.r, a2.r)) < threshold
end

function vrmod.utils.LengthSqr(v)
    if not v then return 0 end
    return v.x * v.x + v.y * v.y + v.z * v.z
end

function vrmod.utils.SubVec(a, b)
    return Vector(a.x - b.x, a.y - b.y, a.z - b.z)
end

function vrmod.utils.AddVec(a, b)
    return Vector(a.x + b.x, a.y + b.y, a.z + b.z)
end

function vrmod.utils.MulVec(v, s)
    s = s or 1
    return Vector(v.x * s, v.y * s, v.z * s)
end

function vrmod.utils.SmoothVector(current, target, smoothingFactor)
    return current + (target - current) * smoothingFactor
end

function vrmod.utils.LerpAngleWrap(factor, current, target)
    local diff = math.AngleDifference(target, current) -- handles ±180 wrap
    return current + diff * factor
end

function vrmod.utils.SmoothAngle(current, target, smoothingFactor)
    local diff = target - current
    diff.p = math.NormalizeAngle(diff.p)
    diff.y = math.NormalizeAngle(diff.y)
    diff.r = math.NormalizeAngle(diff.r)
    return current + diff * smoothingFactor
end

--- Type-dispatch smooth (number / Vector / Angle). Prefer this over ad-hoc FrameTime Lerp.
function vrmod.utils.SmoothValue(current, target, factor)
    factor = tonumber(factor) or 0
    if factor <= 0 or current == nil then return target end
    if isnumber(current) and isnumber(target) then
        return current + (target - current) * factor
    end
    if isvector and isvector(current) and isvector(target) then
        return vrmod.utils.SmoothVector(current, target, factor)
    end
    if isangle and isangle(current) and isangle(target) then
        return vrmod.utils.SmoothAngle(current, target, factor)
    end
    -- Table-like x/y/z or p/y/r
    if type(current) == "table" and type(target) == "table" then
        if current.x and target.x then
            return vrmod.utils.SmoothVector(
                Vector(current.x, current.y or 0, current.z or 0),
                Vector(target.x, target.y or 0, target.z or 0),
                factor
            )
        end
        if current.p and target.p then
            return vrmod.utils.SmoothAngle(
                Angle(current.p, current.y or 0, current.r or 0),
                Angle(target.p, target.y or 0, target.r or 0),
                factor
            )
        end
    end
    return target
end

--- Floor/ceiling vs wall (shared by hand wall coll + tests).
function vrmod.utils.IsFloorOrCeilingNormal(n, threshold)
    if not n then return false end
    local z = n.z
    if z == nil then return false end
    threshold = tonumber(threshold) or 0.55
    return math.abs(z) > threshold
end

--- RGBA convar string → Color. Shared SoT (settings + laser/beam).
function vrmod.utils.ParseColor(str, fallback)
    fallback = fallback or Color(255, 0, 0, 255)
    if not str or str == "" then
        return Color(fallback.r, fallback.g, fallback.b, fallback.a or 255)
    end
    local r, g, b, a = string.match(tostring(str), "(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
    if not r then
        r, g, b = string.match(tostring(str), "(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
        a = 255
    end
    if not r then
        return Color(fallback.r, fallback.g, fallback.b, fallback.a or 255)
    end
    return Color(tonumber(r) or 255, tonumber(g) or 0, tonumber(b) or 0, tonumber(a) or 255)
end

function vrmod.utils.FormatColor(col)
    if not col then return "255,0,0,255" end
    return string.format("%d,%d,%d,%d",
        math.Clamp(math.floor(col.r or 255), 0, 255),
        math.Clamp(math.floor(col.g or 0), 0, 255),
        math.Clamp(math.floor(col.b or 0), 0, 255),
        math.Clamp(math.floor(col.a or 255), 0, 255))
end

--- Finger digit index from angle slot (1-based): slots 1-3→1, 4-6→2, ...
function vrmod.utils.FingerDigitIndex(slot)
    slot = tonumber(slot) or 1
    return math.floor((slot - 1) / 3) + 1
end

--- Lerp one finger bone angle by curl 0..1
function vrmod.utils.LerpFingerAngle(curl, openAng, closedAng)
    curl = math.Clamp(tonumber(curl) or 0, 0, 1)
    if not openAng or not closedAng then return openAng or closedAng or Angle() end
    return LerpAngle(curl, openAng, closedAng)
end

--- Apply curl table to open/closed hand angle arrays → out angles (15 or table length).
function vrmod.utils.ApplyFingerCurl(openAngles, closedAngles, curls, out)
    out = out or {}
    local n = math.min(#(openAngles or {}), #(closedAngles or {}))
    for k = 1, n do
        local digit = vrmod.utils.FingerDigitIndex(k)
        local curl = 0
        if type(curls) == "table" then
            curl = curls[digit] or curls[k] or 0
        elseif isnumber(curls) then
            curl = curls
        end
        out[k] = vrmod.utils.LerpFingerAngle(curl, openAngles[k], closedAngles[k])
    end
    return out
end

--- Eye-height calibration: scale so measured eye height maps to reference (Source ~66.8).
function vrmod.utils.AutoScaleHeight(measuredEyeHeight, referenceEyeHeight)
    referenceEyeHeight = tonumber(referenceEyeHeight) or 66.8
    measuredEyeHeight = tonumber(measuredEyeHeight) or referenceEyeHeight
    if measuredEyeHeight < 1 then return 1 end
    return referenceEyeHeight / measuredEyeHeight
end

--- Seated offset: how much to lift origin so HMD sits at reference standing eye height.
function vrmod.utils.AutoSeatedOffset(measuredEyeHeight, referenceEyeHeight)
    referenceEyeHeight = tonumber(referenceEyeHeight) or 66.8
    measuredEyeHeight = tonumber(measuredEyeHeight) or referenceEyeHeight
    return referenceEyeHeight - measuredEyeHeight
end

--- Settings catalog kind tokens (desktop + Cube must both handle these).
vrmod.utils.SETTINGS_ROW_KINDS = {
    header = true,
    help = true,
    bool = true,
    slider = true,
    combo = true,
    color = true,
    action = true,
}

function vrmod.utils.IsSettingsRowKind(kind)
    return vrmod.utils.SETTINGS_ROW_KINDS[tostring(kind or "")] == true
end