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
    return v.x * v.x + v.y * v.y + v.z * v.z
end

function vrmod.utils.SubVec(a, b)
    return Vector(a.x - b.x, a.y - b.y, a.z - b.z)
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