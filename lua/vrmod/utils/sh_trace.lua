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

function vrmod.utils.TraceHand(ply, hand, fromPalm)
    local startPos, ang, dir
    if hand == "left" then
        startPos = vrmod.GetLeftHandPos(ply)
        ang = vrmod.GetLeftHandAng(ply)
        if not ang then return nil end
        if fromPalm then
            dir = ang:Right()
        else
            dir = Angle(ang.p, ang.y, ang.r + 180):Forward()
        end
    else
        startPos = vrmod.GetRightHandPos(ply)
        ang = vrmod.GetRightHandAng(ply)
        if not ang then return nil end
        if fromPalm then
            dir = -ang:Right()
        else
            dir = ang:Forward()
        end
    end

    if not startPos or not dir then return nil end
    dir:Normalize()
    -- Sphere size for the palm
    local radius = 4 -- tweak this (palm "thickness")
    local ignore = {}
    local maxDepth = 10
    local traceStart = startPos
    for i = 1, maxDepth do
        local tr = util.TraceHull({
            start = traceStart,
            endpos = traceStart + dir * 32768,
            mins = Vector(-radius, -radius, -radius),
            maxs = Vector(radius, radius, radius),
            filter = ignore,
            mask = MASK_SHOT_HULL
        })

        if not tr.Entity or not IsValid(tr.Entity) then return tr end
        if vrmod.utils.HitFilter(tr.Entity, ply, hand) then
            return tr
        else
            table.insert(ignore, tr.Entity)
            traceStart = tr.HitPos + dir * 1
        end
    end
    return nil
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