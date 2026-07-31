-- =============================================================================
-- vrmod.algocube.vision — Vision / HUD / Twin diagnosis cube (nonverbal)
--
-- ESSENCE (from live failure + screenshot SoT):
--
--   TWO overlay energies exist in VR:
--
--   A) MENU PATH (works — Avatar panel in screenshot):
--        VGUI panel → SetPaintedManually → PushRT → cam.Start2D
--        → PaintManual() → world 3D2D quad via VRUtilRenderMenuSystem
--
--   B) HUD PATH (fails — empty grey plate):
--        curved Mesh + UnlitGeneric($basetexture=RT)
--        → render.RenderHUD into RT while nested under stereo eye RT
--        → often paints NOTHING → mesh still draws → blank square
--
--   False dual-truth: treating (A) and (B) as interchangeable "UI".
--   Cube law: one paint energy. HUD must use the same paint atoms as menus
--   (PaintManual / Start2D / dedicated RT), not a weaker nested RenderHUD hope.
--
--   Twin (foreground black figure): pose snap without laterality / re-IK
--   is a second dual-truth (player IK vs twin invent). Snap-only + mode digit.
--
-- IO bits (0/1) → Digit 0..9 → policy payload (no prose on hot path).
-- =============================================================================

vrmod = vrmod or {}
vrmod.algocube = vrmod.algocube or {}
local A = vrmod.algocube
local V = {}
vrmod.algocube.vision = V

-- Blueprint: vision-weighted law (HUD paint SoT first)
-- pick emphasis: 2=cube SoT (menu-style paint), 6=cmd override full repair
V.BLUEPRINT = { 2, 2, 6, 1, 8, 3, 6, 0, 9, 4 }
V.PICK = 2
V.HOST = "vrmod_vision"
V.SCHEMA = 1

------------------------------------------------------------------------
-- Digit → policy (pure table)
------------------------------------------------------------------------
--- @return table policy
function V.PolicyFor(digit)
	digit = (tonumber(digit) or V.PICK) % 10
	if digit < 0 then digit = V.PICK end

	-- Defaults: menu-style HUD paint + clone twin (safe laterality)
	local p = {
		digit = digit,
		law = (A.LawLabel and A.LawLabel(digit)) or tostring(digit),
		-- HUD
		hudPaint = "vgui", -- "vgui" | "renderhud" | "essentials" | "off"
		hudComposite = "translucent", -- "translucent" | "additive"
		hudClearAlpha = 0, -- 0 = no plate; >0 dim plate
		hudEssentials = true, -- always project HP/ammo/crosshair
		hudMenuWrap = true,
		hudStereoBackup = true,
		-- Twin
		twinMode = "clone", -- clone | facing | world | idle
		twinSoftClamp = false,
		twinLR = false,
		twinSnapOnly = true,
		label = "VISION",
	}

	if digit == 0 then
		-- free device — HUD off plate, twin idle
		p.hudPaint = "off"
		p.twinMode = "idle"
		p.label = "FREE"
	elseif digit == 1 then
		-- open way — essentials only, clone twin
		p.hudPaint = "essentials"
		p.twinMode = "clone"
		p.twinLR = false
		p.label = "ESSENTIALS+CLONE"
	elseif digit == 2 then
		-- cube SoT — MENU paint path (essence fix)
		p.hudPaint = "vgui"
		p.hudComposite = "translucent"
		p.hudClearAlpha = 0
		p.hudEssentials = true
		p.twinMode = "clone"
		p.label = "MENU_PAINT+CLONE"
	elseif digit == 3 then
		-- nanobot raw — RenderHUD attempt + essentials
		p.hudPaint = "renderhud"
		p.hudEssentials = true
		p.twinMode = "world"
		p.label = "RAWHUD+WORLD"
	elseif digit == 4 then
		-- hail — additive composite (PROPHECY black-slab law)
		p.hudPaint = "vgui"
		p.hudComposite = "additive"
		p.hudClearAlpha = 255 -- black plate, additive hides
		p.twinMode = "facing"
		p.twinLR = true
		p.label = "ADDITIVE+MIRROR"
	elseif digit == 5 then
		-- commander — opaque-ish plate for readability
		p.hudPaint = "vgui"
		p.hudClearAlpha = 120
		p.twinMode = "facing"
		p.twinLR = true
		p.label = "DIM_PLATE+MIRROR"
	elseif digit == 6 then
		-- cmd override — full repair (matrix pick analogue)
		p.hudPaint = "vgui"
		p.hudComposite = "translucent"
		p.hudClearAlpha = 0
		p.hudEssentials = true
		p.hudMenuWrap = true
		p.hudStereoBackup = true
		p.twinMode = "facing"
		p.twinLR = true
		p.twinSnapOnly = true
		p.twinSoftClamp = false
		p.label = "FULL_REPAIR"
	elseif digit == 7 then
		-- OS way — essentials + clone only
		p.hudPaint = "essentials"
		p.twinMode = "clone"
		p.label = "MINIMAL"
	elseif digit == 8 then
		-- nonverbal — no HUD mesh, twin facing silent
		p.hudPaint = "off"
		p.twinMode = "facing"
		p.twinLR = true
		p.label = "SILENT_MIRROR"
	elseif digit == 9 then
		-- hivemind — everything on, debug-friendly
		p.hudPaint = "vgui"
		p.hudClearAlpha = 40
		p.hudEssentials = true
		p.twinMode = "facing"
		p.twinLR = true
		p.label = "HIVE_VERBOSE"
	end

	return p
end

------------------------------------------------------------------------
-- Sample live IO → bits (CLIENT/SERVER safe fields only where exist)
------------------------------------------------------------------------
function V.SampleIO()
	local bits = {} -- 0/1 array
	local function push(v)
		bits[#bits + 1] = (v and true) and 1 or 0
	end

	local g = g_VR or {}
	push(g.active)
	push(g.stereoEye ~= nil)
	push(g.threePoints)
	push(g.tracking and g.tracking.hmd and g.tracking.hmd.pos ~= nil)
	push(g.rt ~= nil)
	push(tonumber(g.rtWidth) ~= nil and tonumber(g.rtWidth) >= 32)
	push(tonumber(g.rtHeight) ~= nil and tonumber(g.rtHeight) >= 32)

	-- HUD diag
	local hd = g.hudDiag or {}
	push(hd.bound == true)
	push((tonumber(hd.captures) or 0) > 0)
	push(hd.paintMode == "vgui")
	push(hd.paintMode == "renderhud")
	push(hd.lastPaintOk == true)
	push((tonumber(hd.luma) or 0) > 0.02) -- RT has visible energy
	push(hd.plateOnly == true) -- mesh but no luma

	-- Twin / avatar
	local ad = g.avatarDiag or {}
	push(ad.applyOk == true)
	push(ad.lrRemap == true)
	push((tonumber(ad.snapBones) or 0) >= 4)
	push((tonumber(ad.maxPosErr) or 0) > 5)
	push(vrmod and vrmod.avatar and vrmod.avatar.IsOpen and vrmod.avatar.IsOpen("avatar"))

	-- Menu path alive (essence: menus work)
	push(g.menus ~= nil and next(g.menus) ~= nil)
	push(isfunction(VRUtilRenderMenuSystem))
	push(isfunction(VRUtilMenuRenderPanel))

	-- Pad to 64 bits for stable algocube input
	while #bits < 64 do
		bits[#bits + 1] = 0
	end
	return bits
end

--- Decide digit from live IO (or forced).
function V.Decide(forceDigit)
	local bits = V.SampleIO()
	local algo = A.New(A.SeedFromBytes and A.SeedFromBytes(bits) or 0xA150)
	local digit
	if forceDigit ~= nil and tonumber(forceDigit) and tonumber(forceDigit) >= 0 then
		digit = tonumber(forceDigit) % 10
	else
		digit = A.Digit(algo, bits, V.BLUEPRINT)
	end
	local policy = V.PolicyFor(digit)
	local payload = A.NeuralPayload and A.NeuralPayload(digit, V.BLUEPRINT) or {}
	return digit, policy, payload, bits
end

--- Structural fail flags from screenshot-class failures (no RNG).
function V.Classify(bits)
	bits = bits or V.SampleIO()
	-- indices 1-based from SampleIO order
	local active = bits[1] == 1
	local stereo = bits[2] == 1
	local rtOk = bits[5] == 1 and bits[6] == 1
	local hudBound = bits[8] == 1
	local captures = bits[9] == 1
	local vguiPaint = bits[10] == 1
	local paintOk = bits[12] == 1
	local hasLuma = bits[13] == 1
	local plateOnly = bits[14] == 1
	local twinOk = bits[15] == 1
	local twinErr = bits[18] == 1
	local menus = bits[20] == 1

	local class = "ok"
	if active and hudBound and captures and not hasLuma then
		class = "empty_plate" -- THE essence failure
	elseif active and not rtOk then
		class = "rt_broken"
	elseif active and twinErr then
		class = "twin_cursed"
	elseif active and not stereo then
		class = "no_stereo"
	elseif plateOnly then
		class = "empty_plate"
	end

	-- Force policy for empty plate → digit 2 (menu paint)
	local force
	if class == "empty_plate" then
		force = 2
	elseif class == "twin_cursed" then
		force = 1 -- clone
	elseif class == "rt_broken" then
		force = 6
	end

	return class, force
end

return V
