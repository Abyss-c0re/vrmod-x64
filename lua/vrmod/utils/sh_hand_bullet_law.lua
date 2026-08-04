-- G37: hand vs bullet filter law (pure, offline-tested).
-- Watchlist W9: hand collision blocks bullets; hands feel non-physical.
-- Cube way: hands Real for grabs; bullets use filtered damage path.
-- Law:
--   hand proxies never solid to world (no wall sparks thrash)
--   non-bullet damage on proxy absorbed (no self-punch)
--   bullet hits hands → scaled damage + drop (not solid stop of world)
--   grab contact allowed; do not rewrite climb wall path here
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

-- Source-style bits when GMod globals missing (offline tests)
local DMG_BULLET_BIT = (DMG_BULLET ~= nil) and DMG_BULLET or 2
local DMG_BUCKSHOT_BIT = (DMG_BUCKSHOT ~= nil) and DMG_BUCKSHOT or 536870912

function vrmod.utils.HandBulletLaw_HandDamageScale()
	return 0.45
end

function vrmod.utils.HandBulletLaw_HeadDamageScale()
	return 10.0
end

--- Proxies must not fight world solids (separate wall path exists).
function vrmod.utils.HandBulletLaw_ProxySolidToWorld()
	return false
end

--- Grab / prop contact stays Real.
function vrmod.utils.HandBulletLaw_AllowGrabContact()
	return true
end

--- Non-bullet damage on hand proxy from self is blocked.
function vrmod.utils.HandBulletLaw_PreventSelfMeleeOnHand()
	return true
end

--- Non-bullet hits on proxies are absorbed (redirect only bullets).
function vrmod.utils.HandBulletLaw_AbsorbNonBulletOnProxy()
	return true
end

function vrmod.utils.HandBulletLaw_IsBulletDamageType(dmgType)
	dmgType = tonumber(dmgType) or 0
	if dmgType == 0 then return false end
	-- bit.band if available
	local band = bit and bit.band or function(a, b)
		local r, p = 0, 1
		while a > 0 and b > 0 do
			local aa, bb = a % 2, b % 2
			if aa == 1 and bb == 1 then r = r + p end
			a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
		end
		return r
	end
	if band(dmgType, DMG_BULLET_BIT) ~= 0 then return true end
	if band(dmgType, DMG_BUCKSHOT_BIT) ~= 0 then return true end
	return false
end

function vrmod.utils.HandBulletLaw_NormalizePart(part)
	part = string.lower(tostring(part or ""))
	if part == "left" or part == "right" or part == "head" then return part end
	return "unknown"
end

function vrmod.utils.HandBulletLaw_IsHandPart(part)
	part = vrmod.utils.HandBulletLaw_NormalizePart(part)
	return part == "left" or part == "right"
end

--- Pure: should absorb this damage on proxy (return true → zero proxy dmg).
--- opts: is_bullet, is_self, part
function vrmod.utils.HandBulletLaw_ShouldAbsorbOnProxy(opts)
	opts = type(opts) == "table" and opts or {}
	local isBullet = opts.is_bullet and true or false
	local isSelf = opts.is_self and true or false
	local part = vrmod.utils.HandBulletLaw_NormalizePart(opts.part)
	if not isBullet then
		if isSelf and vrmod.utils.HandBulletLaw_IsHandPart(part)
			and vrmod.utils.HandBulletLaw_PreventSelfMeleeOnHand() then
			return true
		end
		return vrmod.utils.HandBulletLaw_AbsorbNonBulletOnProxy()
	end
	return false -- bullets processed (redirect), not silent absorb without logic
end

--- Scale applied to player after bullet hits proxy part.
function vrmod.utils.HandBulletLaw_RedirectScale(part)
	part = vrmod.utils.HandBulletLaw_NormalizePart(part)
	if part == "head" then return vrmod.utils.HandBulletLaw_HeadDamageScale() end
	if vrmod.utils.HandBulletLaw_IsHandPart(part) then
		return vrmod.utils.HandBulletLaw_HandDamageScale()
	end
	return 0
end

function vrmod.utils.HandBulletLaw_ShouldDropOnHandBullet(part, isBullet)
	return isBullet and vrmod.utils.HandBulletLaw_IsHandPart(part)
end

--- Pure decision snapshot.
--- opts: part, is_bullet, is_self, damage, solid_to_world, grab_ok
function vrmod.utils.HandBulletLaw_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local part = vrmod.utils.HandBulletLaw_NormalizePart(opts.part)
	local isBullet = opts.is_bullet
	if isBullet == nil and opts.dmg_type ~= nil then
		isBullet = vrmod.utils.HandBulletLaw_IsBulletDamageType(opts.dmg_type)
	end
	isBullet = isBullet and true or false
	local isSelf = opts.is_self and true or false
	local dmg = tonumber(opts.damage) or 0
	local absorb = vrmod.utils.HandBulletLaw_ShouldAbsorbOnProxy({
		is_bullet = isBullet,
		is_self = isSelf,
		part = part,
	})
	local scale = isBullet and vrmod.utils.HandBulletLaw_RedirectScale(part) or 0
	local d = {
		valid = true,
		part = part,
		is_bullet = isBullet,
		is_self = isSelf,
		absorb = absorb,
		redirect_scale = scale,
		player_damage = (not absorb and isBullet) and (dmg * scale) or 0,
		drop_weapon = vrmod.utils.HandBulletLaw_ShouldDropOnHandBullet(part, isBullet),
		proxy_solid_to_world = vrmod.utils.HandBulletLaw_ProxySolidToWorld(),
		grab_contact = vrmod.utils.HandBulletLaw_AllowGrabContact(),
		risk = "none", -- none | solid_world | blocks_bullets | self_melee | ok_bullet
		reason = "ok",
		path_ok = true,
	}
	if opts.solid_to_world then
		d.risk = "solid_world"
		d.reason = "proxy_must_not_solid_world"
		d.path_ok = false
	elseif opts.blocks_bullets_as_world then
		d.risk = "blocks_bullets"
		d.reason = "hands_block_bullet_traces"
		d.path_ok = false
	elseif isSelf and not isBullet and vrmod.utils.HandBulletLaw_IsHandPart(part) and not absorb then
		d.risk = "self_melee"
		d.reason = "self_punch_not_absorbed"
		d.path_ok = false
	elseif isBullet and d.player_damage > 0 then
		d.risk = "none"
		d.reason = "bullet_redirect_" .. part
		d.path_ok = true
	elseif absorb then
		d.reason = "absorbed_non_bullet"
		d.path_ok = true
	else
		d.reason = "idle"
	end
	return d
end

function vrmod.utils.HandBulletLaw_StatusLabel(decision)
	if type(decision) ~= "table" then return "HAND · IDLE" end
	if decision.risk == "solid_world" then return "HAND · SOLID WORLD" end
	if decision.risk == "blocks_bullets" then return "HAND · BLOCKS BULLETS" end
	if decision.risk == "self_melee" then return "HAND · SELF MELEE" end
	if decision.is_bullet and decision.player_damage > 0 then return "HAND · BULLET REDIRECT" end
	if decision.absorb then return "HAND · ABSORB" end
	if decision.path_ok then return "HAND · OK" end
	return "HAND · HOLD"
end

function vrmod.utils.HandBulletLaw_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_grabs = true,
		expect_bullets_filtered = true,
		checklist = "G37 · IDLE · no hand-bullet decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if not decision.path_ok then
		e.verdict = "expect_fail"
		e.expect_bullets_filtered = false
		e.checklist = "G37 · FAIL · " .. tostring(decision.reason)
		e.pass_line = "Hands grab Real; bullets filtered; no world solid"
		e.fail_line = "Hands block all bullets / solid walls thrash"
		return e
	end
	if decision.is_bullet then
		e.verdict = "expect_bullet_redirect"
		e.checklist = "G37 · BULLET · " .. tostring(decision.part) .. " scale=" .. tostring(decision.redirect_scale)
		e.pass_line = "Damage redirect; hand drop if hand hit; no silent stop"
		e.fail_line = "Bullets vanish in hands with no feedback"
		return e
	end
	e.verdict = "expect_ok"
	e.checklist = "G37 · OK · grabs Real · non-bullet absorbed · world not solid"
	e.pass_line = "Grab props; shoot past hands; no wall spark thrash"
	e.fail_line = "Hands block bullets or feel non-physical for grabs"
	return e
end

function vrmod.utils.HandBulletLaw_IsBlockRisk(decision)
	if type(decision) ~= "table" then return true end
	return decision.risk == "blocks_bullets" or decision.risk == "solid_world"
end
