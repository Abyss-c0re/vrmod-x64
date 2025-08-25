g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

local magCache = {}

local function IsMagazine(ent)
    local class = ent:GetClass()
    if magCache[class] ~= nil then return magCache[class] end
    local isMag = string.StartWith(class, "avrmag_")
    magCache[class] = isMag
    return isMag
end

--FILTERS AND TRACE UTILS
function vrmod.utils.HitFilter(ent, ply, hand)
    if not IsValid(ent) then return false end
    if ent == ply then return end
    if ent:GetNWBool("isVRHand", false) then return false end
    if IsValid(ply) and (hand == "left" or hand == "right") then
        local held = vrmod.GetHeldEntity(ply, hand)
        if IsValid(held) and held == ent then return false end
    end
    return true
end

function vrmod.utils.MeleeFilter(ent, ply, hand)
    return vrmod.utils.HitFilter(ent, ply, hand) and not IsMagazine(ent)
end

function vrmod.utils.TraceHand(ply, hand)
    local startPos, ang, dir
    if hand == "left" then
        startPos = vrmod.GetLeftHandPos(ply)
        ang = vrmod.GetLeftHandAng(ply)
        if not ang then return nil end
        local ang2 = Angle(ang.p, ang.y, ang.r + 180)
        dir = ang2:Forward()
    else
        startPos = vrmod.GetRightHandPos(ply)
        ang = vrmod.GetRightHandAng(ply)
        if not ang then return nil end
        dir = ang:Forward()
    end

    if not startPos or not dir then return nil end
    local ignore = {}
    local maxDepth = 10
    for i = 1, maxDepth do
        local tr = util.TraceLine({
            start = startPos,
            endpos = startPos + dir * 32768,
            filter = ignore
        })

        if not tr.Entity or not IsValid(tr.Entity) then return tr end
        if vrmod.utils.HitFilter(tr.Entity, ply, hand) then
            return tr
        else
            table.insert(ignore, tr.Entity)
            startPos = tr.HitPos + dir * 1 -- Avoid infinite loops on same surface
        end
    end
    return nil -- Nothing valid hit after maxDepth
end

function vrmod.utils.TraceBoxOrSphere(data)
    local best = {
        Hit = false,
        Fraction = 1
    }

    if data.mins and data.maxs then
        -- Box trace
        local tr = util.TraceHull({
            start = data.start,
            endpos = data.endpos,
            mins = data.mins,
            maxs = data.maxs,
            filter = data.filter,
            mask = data.mask
        })

        if tr.Hit then
            best = tr
            best.Hit = true
        end
    else
        -- Sphere approximation with single hull trace
        local radius = data.radius or vrmod.DEFAULT_RADIUS
        local tr = util.TraceHull({
            start = data.start,
            endpos = data.endpos,
            mins = Vector(-radius, -radius, -radius),
            maxs = Vector(radius, radius, radius),
            filter = data.filter,
            mask = data.mask
        })

        if tr.Hit then
            best = tr
            best.Hit = true
        end
    end
    return best
end
