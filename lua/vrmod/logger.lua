g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}
local cv_debug = CreateConVar("vrmod_debug", "0", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Enable detailed melee debug logging (0 = off, 1 = on)")
local function tostr(v)
    if istable(v) then
        local parts = {}
        for k, val in pairs(v) do
            table.insert(parts, tostring(k) .. "=" .. tostr(val))
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    elseif IsEntity and IsEntity(v) and v:IsValid() then
        return string.format("Entity[%s:%s]", v:GetClass(), v:EntIndex())
    elseif IsEntity and IsEntity(v) then
        return "Entity[INVALID]"
    elseif isvector and isvector(v) then
        return string.format("Vector(%.2f, %.2f, %.2f)", v.x, v.y, v.z)
    elseif isangle and isangle(v) then
        return string.format("Angle(%.2f, %.2f, %.2f)", v.p, v.y, v.r)
    else
        return tostring(v)
    end
end

--DEBUG
function vrmod.utils.DebugPrint(fmt, ...)
    if not cv_debug:GetBool() then return end
    local prefix = string.format("[VRMod:][%s]", CLIENT and "Client" or "Server")
    if select("#", ...) > 0 then
        if type(fmt) == "string" and fmt:find("%%") then
            -- format mode
            local args = {...}
            for i = 1, #args do
                args[i] = tostr(args[i])
            end

            print(prefix, string.format(fmt, unpack(args)))
        else
            -- print mode
            local args = {fmt, ...}
            for i = 1, #args do
                args[i] = tostr(args[i])
            end

            print(prefix, unpack(args))
        end
    else
        -- single argument only
        print(prefix, tostr(fmt))
    end
end