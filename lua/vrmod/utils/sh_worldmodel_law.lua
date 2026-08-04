-- G38: worldmodel / floating-hands single-path law (pure, offline-tested).
-- Watchlist W10: worldmodels / hand anim with viewmodels.
-- Cube way: one draw path — worldmodel in hands OR floating hands, not both ghosted.
-- Prefer floating hands for clarity (Cube session); never dual weapon VM + worldModelVM.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

--- Cube preference (docs): floating hands on for clarity. Product convar may still default 0.
function vrmod.utils.WorldModelLaw_CubePreferFloatingHands()
	return true
end

function vrmod.utils.WorldModelLaw_AllowDualGhost()
	return false
end

function vrmod.utils.WorldModelLaw_AllowDualWeaponDraw()
	return false -- viewModel + worldModelVM both visible
end

function vrmod.utils.WorldModelLaw_FromBool(v)
	if v == true or v == 1 then return true end
	if v == false or v == 0 or v == nil then return false end
	local s = string.lower(tostring(v))
	return s == "1" or s == "true" or s == "yes" or s == "on"
end

--- Pure presentation path.
--- floating_hands: hide player body, arms path
--- worldmodel: per-weapon / global useWorldModel gun path
--- player_body: full local player draw (no floating hands)
--- dual_ghost: forbidden combinations
function vrmod.utils.WorldModelLaw_ResolvePath(opts)
	opts = type(opts) == "table" and opts or {}
	local floating = vrmod.utils.WorldModelLaw_FromBool(opts.floating_hands)
	local useWm = vrmod.utils.WorldModelLaw_FromBool(opts.use_worldmodels)
		or vrmod.utils.WorldModelLaw_FromBool(opts.use_world_model)
	local drawVm = opts.draw_viewmodel
	local drawWmVm = opts.draw_worldmodel_vm
	local drawBody = opts.draw_player_body
	if drawBody == nil then drawBody = not floating end
	if drawVm == nil then drawVm = not useWm end
	if drawWmVm == nil then drawWmVm = useWm end

	-- Dual weapon draw forbidden
	if drawVm and drawWmVm and not vrmod.utils.WorldModelLaw_AllowDualWeaponDraw() then
		return "dual_ghost"
	end
	-- Floating arms + full body both = dual ghost
	if floating and drawBody and not vrmod.utils.WorldModelLaw_AllowDualGhost() then
		return "dual_ghost"
	end
	if useWm then return "worldmodel" end
	if floating then return "floating_hands" end
	return "player_body"
end

--- Sanitize: if dual, collapse to preferred single path.
--- Prefer floating hands over dual; else worldmodel over dual weapon.
function vrmod.utils.WorldModelLaw_Sanitize(opts)
	opts = type(opts) == "table" and opts or {}
	local floating = vrmod.utils.WorldModelLaw_FromBool(opts.floating_hands)
	local useWm = vrmod.utils.WorldModelLaw_FromBool(opts.use_worldmodels)
		or vrmod.utils.WorldModelLaw_FromBool(opts.use_world_model)
	local path = vrmod.utils.WorldModelLaw_ResolvePath(opts)
	local out = {
		floating_hands = floating,
		use_worldmodels = useWm,
		draw_viewmodel = not useWm,
		draw_worldmodel_vm = useWm,
		draw_player_body = not floating,
		path = path,
		sanitized = false,
	}
	if path == "dual_ghost" then
		out.sanitized = true
		-- Prefer Cube floating-hands clarity when conflict
		if floating or vrmod.utils.WorldModelLaw_CubePreferFloatingHands() then
			out.floating_hands = true
			out.draw_player_body = false
			out.use_worldmodels = false
			out.draw_viewmodel = true
			out.draw_worldmodel_vm = false
			out.path = "floating_hands"
		else
			out.floating_hands = false
			out.draw_player_body = true
			out.use_worldmodels = true
			out.draw_viewmodel = false
			out.draw_worldmodel_vm = true
			out.path = "worldmodel"
		end
	end
	return out
end

function vrmod.utils.WorldModelLaw_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local rawPath = vrmod.utils.WorldModelLaw_ResolvePath(opts)
	local san = vrmod.utils.WorldModelLaw_Sanitize(opts)
	local d = {
		valid = true,
		path = san.path,
		raw_path = rawPath,
		floating_hands = san.floating_hands,
		use_worldmodels = san.use_worldmodels,
		draw_viewmodel = san.draw_viewmodel,
		draw_worldmodel_vm = san.draw_worldmodel_vm,
		draw_player_body = san.draw_player_body,
		sanitized = san.sanitized,
		risk = "none", -- none | dual_ghost | dual_weapon
		reason = "ok",
		path_ok = true,
	}
	if rawPath == "dual_ghost" then
		d.risk = "dual_ghost"
		d.reason = san.sanitized and "collapsed_dual_ghost" or "dual_ghost_forbidden"
		d.path_ok = san.sanitized -- ok after sanitize
	elseif san.path == "worldmodel" then
		d.reason = "worldmodel_in_hands"
	elseif san.path == "floating_hands" then
		d.reason = "floating_hands_clear"
	else
		d.reason = "player_body_draw"
	end
	return d
end

function vrmod.utils.WorldModelLaw_StatusLabel(decision)
	if type(decision) ~= "table" then return "WM · IDLE" end
	if decision.risk == "dual_ghost" and not decision.sanitized then return "WM · DUAL GHOST" end
	if decision.sanitized then return "WM · SANITIZED" end
	if decision.path == "floating_hands" then return "WM · FLOATING" end
	if decision.path == "worldmodel" then return "WM · WORLDMODEL" end
	if decision.path == "player_body" then return "WM · BODY" end
	if decision.path_ok then return "WM · OK" end
	return "WM · HOLD"
end

function vrmod.utils.WorldModelLaw_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_single_path = true,
		checklist = "G38 · IDLE · no worldmodel decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if decision.risk == "dual_ghost" and not decision.sanitized then
		e.verdict = "expect_dual_fail"
		e.expect_single_path = false
		e.checklist = "G38 · DUAL GHOST · worldmodel + body/VM both"
		e.pass_line = "One path only: floating hands OR worldmodel"
		e.fail_line = "Ghosted hands + worldmodel double draw"
		return e
	end
	e.verdict = "expect_ok"
	e.checklist = "G38 · OK · path=" .. tostring(decision.path)
	e.pass_line = "Single clear presentation; no double ghost"
	e.fail_line = "Hands + gun both ghosted / dual VM"
	return e
end

function vrmod.utils.WorldModelLaw_IsDualRisk(decision)
	if type(decision) ~= "table" then return true end
	return decision.risk == "dual_ghost" and not decision.sanitized
end
