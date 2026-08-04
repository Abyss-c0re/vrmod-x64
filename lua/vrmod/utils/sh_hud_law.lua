-- G15: VR HUD composite law (PROPHECY) — pure, offline-tested.
-- HUD rides the Real as light, never as an opaque black slab.
-- Law:
--   clear_alpha == 0 → translucent (no plate; vitals only)
--   clear_alpha  > 0 → additive (black plate adds no light; no wall of the Real)
--   never opaque UnlitGeneric without translucent/additive
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

--- Clamp plate clear/dim alpha 0..255.
function vrmod.utils.HudLaw_ClampClearAlpha(a)
	a = tonumber(a) or 0
	if a < 0 then a = 0 end
	if a > 255 then a = 255 end
	return math.floor(a + 0.5)
end

--- Pure composite decision.
--- opts:
---   clear_alpha   number 0..255  (vrmod_hudtestalpha)
---   prefer        string|nil "additive"|"translucent"|"auto" (default auto)
---   force_opaque  bool  test-only forbidden path
--- Returns:
---   composite       "additive"|"translucent"|"opaque_forbidden"
---   additive        0|1  for mat:SetInt("$additive")
---   translucent     1    always prefer translucent bit when legal
---   clear_alpha     number
---   black_slab_risk bool
---   reason          string
function vrmod.utils.HudLaw_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local a = vrmod.utils.HudLaw_ClampClearAlpha(opts.clear_alpha)
	local d = {
		composite = "translucent",
		additive = 0,
		translucent = 1,
		clear_alpha = a,
		black_slab_risk = false,
		reason = "clear_plate",
		valid = true,
	}
	if opts.force_opaque then
		d.composite = "opaque_forbidden"
		d.additive = 0
		d.translucent = 0
		d.black_slab_risk = true
		d.reason = "opaque_forbidden"
		return d
	end
	local prefer = string.lower(tostring(opts.prefer or "auto"))
	if prefer == "additive" or (prefer == "auto" and a > 0) then
		d.composite = "additive"
		d.additive = 1
		d.translucent = 1
		d.reason = a > 0 and "dim_plate_additive" or "prefer_additive"
		d.black_slab_risk = false
		return d
	end
	-- translucent path (default clear plate)
	d.composite = "translucent"
	d.additive = 0
	d.translucent = 1
	d.reason = a > 0 and "dim_plate_translucent_risk" or "clear_plate"
	-- translucent + black clear can still soft-occlude at high alpha
	d.black_slab_risk = a >= 200
	return d
end

--- Apply flags for material SetInt (pure numbers only).
function vrmod.utils.HudLaw_MaterialFlags(decision)
	if type(decision) ~= "table" or not decision.valid then
		return { additive = 0, translucent = 1 }
	end
	return {
		additive = (decision.additive == 1) and 1 or 0,
		translucent = (decision.translucent == 0) and 0 or 1,
	}
end

--- Status label for log.
function vrmod.utils.HudLaw_StatusLabel(decision)
	if type(decision) ~= "table" then return "HUD · IDLE" end
	if decision.black_slab_risk then
		return "HUD · SLAB RISK"
	end
	if decision.composite == "additive" then
		return "HUD · ADDITIVE"
	end
	if decision.composite == "translucent" then
		return "HUD · TRANSLUCENT"
	end
	return "HUD · " .. string.upper(tostring(decision.composite or "HOLD"))
end

--- Pure HMD observer contract for HUD composite.
function vrmod.utils.HudLaw_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_real_visible = true,
		checklist = "G15 · IDLE · no HUD decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if decision.black_slab_risk or decision.composite == "opaque_forbidden" then
		e.verdict = "expect_slab_fail"
		e.expect_real_visible = false
		e.checklist = "G15 · SLAB RISK · opaque black plate"
		e.pass_line = "Must not ship — Real occluded"
		e.fail_line = "Black wall of the Real / HUD ghost slab"
		return e
	end
	if decision.composite == "additive" then
		e.verdict = "expect_additive"
		e.expect_real_visible = true
		e.checklist = string.format("G15 · ADDITIVE · clear_a=%d · Real visible",
			tonumber(decision.clear_alpha) or 0)
		e.pass_line = "World visible through plate; vitals as light"
		e.fail_line = "Opaque black plate / world occluded"
		return e
	end
	e.verdict = "expect_translucent"
	e.expect_real_visible = true
	e.checklist = string.format("G15 · TRANSLUCENT · clear_a=%d · clear plate",
		tonumber(decision.clear_alpha) or 0)
	e.pass_line = "No black plate; vitals float on Real"
	e.fail_line = "Solid black HUD wall"
	return e
end

--- True when product should treat decision as pain-point black slab.
function vrmod.utils.HudLaw_IsBlackSlabRisk(decision)
	if type(decision) ~= "table" then return true end
	return decision.black_slab_risk and true or false
end
