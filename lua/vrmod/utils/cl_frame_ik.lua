-- =============================================================================
-- vrmod.frameik — compat shim → vrmod.charik (Cube single SoT)
--
-- All real IK lives in cl_character_ik.lua. This file keeps old call sites
-- (Init / TransformFrame / Apply) working without dual math.
-- =============================================================================
if SERVER then return end

vrmod = vrmod or {}

-- charik loads as cl_character_ik.lua (alphabetically after cl_avatar_editor,
-- before this file). At runtime both exist; re-bind after file load.
local function bind()
	if vrmod.charik then
		vrmod.frameik = vrmod.charik
		return true
	end
	return false
end

if not bind() then
	-- Deferred: avatar may call frameik after all utils load
	vrmod.frameik = vrmod.frameik or {}
	setmetatable(vrmod.frameik, {
		__index = function(_, k)
			if bind() and vrmod.charik then
				return vrmod.charik[k]
			end
		end,
	})
end
