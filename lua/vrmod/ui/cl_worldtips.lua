if SERVER then return end
-- =============================================================================
-- World tips (entity hover labels) for VR — stereo-safe, crimson plate chrome.
-- Stock path used EyePos() == g_VR.view.origin which never holds under dual-eye /
-- single-pass → tips invisible. Fixed: draw once using HMD anchor.
-- Accent: soft use of materials/vrmod/tpbeam when present (vrmod-x64 asset).
-- =============================================================================

local tips = {}
local AddWorldTip_orig
local accentMat = Material("vrmod/tpbeam", "smooth noclamp")

timer.Simple(0, function()
	if isfunction(AddWorldTip) then
		AddWorldTip_orig = AddWorldTip
	end
end)

local function Theme()
	if vrmod.cube and vrmod.cube.ThemeLive then
		return vrmod.cube.ThemeLive()
	end
	if vrmod.cube and vrmod.cube.Theme then
		return vrmod.cube.Theme
	end
	return {
		bg = Color(12, 6, 10, 235),
		bgGlass = Color(28, 12, 18, 230),
		header = Color(196, 30, 58, 255),
		hot = Color(255, 70, 100, 255),
		text = Color(255, 240, 244, 255),
		muted = Color(200, 150, 165, 230),
	}
end

local function TipFont()
	if vrmod.cube and vrmod.cube.Font then
		return vrmod.cube.Font("CubeLabel") or "DermaDefaultBold"
	end
	return "DermaDefaultBold"
end

local function HmdPos()
	if g_VR and g_VR.tracking and g_VR.tracking.hmd and g_VR.tracking.hmd.pos then
		return g_VR.tracking.hmd.pos
	end
	if g_VR and g_VR.view and g_VR.view.origin then
		return g_VR.view.origin
	end
	return EyePos()
end

--- One draw pass per frame (not per eye double).
local drawnFrame = -1

local function DrawTips()
	if not g_VR or not g_VR.active then return end
	if g_VR._radarCapturing or g_VR._renderingHudRT then return end
	local fr = FrameNumber()
	if drawnFrame == fr then return end
	drawnFrame = fr

	local curtime = SysTime()
	local hmd = HmdPos()
	local th = Theme()
	local tms = render.GetToneMappingScaleLinear()
	render.SetToneMappingScaleLinear(Vector(0.8, 0.8, 0.8))
	cam.IgnoreZ(true)
	surface.SetDrawColor(255, 255, 255, 255)

	local i = 1
	while tips[i] do
		local v = tips[i]
		if curtime > v.dietime or (v.ent and not IsValid(v.ent)) then
			table.remove(tips, i)
		else
			local wpos = (IsValid(v.ent) and v.ent:LocalToWorld(v.ent:OBBCenter())) or v.pos
			if wpos then
				local dist = (hmd - wpos):Length()
				local scale = math.Clamp(dist * math.tan(0.00115), 0.04, 0.55)
				local face = (hmd - wpos):Angle()
				face:RotateAroundAxis(face:Right(), 90)
				face:RotateAroundAxis(face:Up(), -90)
				-- Lift slightly toward HMD so tip sits above entity
				local lift = (hmd - wpos):GetNormalized() * (8 + dist * 0.02)
				local drawPos = wpos + lift + Vector(0, 0, 6)
				cam.Start3D2D(drawPos, face, scale)
				surface.SetMaterial(v.mat)
				surface.DrawTexturedRect(-256, -256, 512, 512)
				cam.End3D2D()
			end
			i = i + 1
		end
	end

	cam.IgnoreZ(false)
	render.SetToneMappingScaleLinear(tms)
	if #tips == 0 then
		hook.Remove("PostDrawTranslucentRenderables", "vrmod_worldtips")
		hook.Remove("VRMod_PostRender", "vrmod_worldtips_once")
	end
end

local function EnsureDrawHooks()
	hook.Add("PostDrawTranslucentRenderables", "vrmod_worldtips", function(depth, sky)
		if depth or sky then return end
		DrawTips()
	end)
	-- Fallback if translucent pass is skipped under some eye paths
	hook.Add("VRMod_PostRender", "vrmod_worldtips_once", function()
		-- only if tips remain and translucent didn't run
		if #tips > 0 and drawnFrame ~= FrameNumber() then
			DrawTips()
		end
	end)
end

local function PaintTipRT(rt, text)
	local th = Theme()
	local font = TipFont()
	render.PushRenderTarget(rt)
	render.ClearDepth()
	render.Clear(0, 0, 0, 0)
	cam.Start2D()

	surface.SetFont(font)
	local tw, tht = surface.GetTextSize(text or "")
	tw = math.min(tw, 420)
	local pad = 16
	local bar = 8
	local boxW = tw + pad * 2 + bar + 8
	local boxH = tht + pad * 2
	local cx, cy = 256, 220
	local x = cx - boxW * 0.5
	local y = cy - boxH * 0.5

	-- Soft beam accent (vrmod-x64 material) behind plate
	if accentMat and not accentMat:IsError() then
		surface.SetMaterial(accentMat)
		surface.SetDrawColor(196, 30, 58, 90)
		surface.DrawTexturedRectRotated(cx, cy + boxH * 0.35, 380, 90, 0)
	end

	-- Glass plate
	surface.SetDrawColor(th.bgGlass or Color(28, 12, 18, 235))
	surface.DrawRect(x, y, boxW, boxH)
	-- Crimson energy bar
	surface.SetDrawColor(th.header or Color(196, 30, 58, 255))
	surface.DrawRect(x, y, bar, boxH)
	-- Hot outline
	surface.SetDrawColor(th.hot or Color(255, 70, 100, 255))
	surface.DrawOutlinedRect(x, y, boxW, boxH, 2)
	-- Inner line
	surface.SetDrawColor(196, 30, 58, 100)
	surface.DrawOutlinedRect(x + 3, y + 3, boxW - 6, boxH - 6, 1)

	-- Pointer triangle toward bottom-right (entity)
	draw.NoTexture()
	local tipCol = th.bgGlass or Color(28, 12, 18, 235)
	surface.SetDrawColor(tipCol)
	local px, py = cx + boxW * 0.22, y + boxH
	surface.DrawPoly({
		{ x = px - 14, y = py },
		{ x = px + 14, y = py },
		{ x = cx + 40, y = py + 36 },
	})
	surface.SetDrawColor(th.hot or Color(255, 70, 100, 255))
	surface.DrawPoly({
		{ x = px - 12, y = py },
		{ x = px + 12, y = py },
		{ x = cx + 40, y = py + 34 },
	})

	draw.SimpleText(text or "", font, cx + bar * 0.5, cy, th.text or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	cam.End2D()
	render.PopRenderTarget()
end

hook.Add("VRMod_Start", "worldtips", function(ply)
	if ply ~= LocalPlayer() then return end
	if not isfunction(AddWorldTip) and AddWorldTip_orig then
		-- already hooked
	end
	if not AddWorldTip_orig and isfunction(AddWorldTip) then
		AddWorldTip_orig = AddWorldTip
	end

	AddWorldTip = function(entindex, text, dietime, pos, ent)
		if #tips == 0 then
			EnsureDrawHooks()
		end

		local index = #tips + 1
		for i = 1, #tips do
			if tips[i].ent == ent or (pos and tips[i].pos == pos) then
				index = i
				break
			end
		end

		if not tips[index] or tips[index].text ~= text then
			local rt = GetRenderTarget("vrmod_worldtip_" .. index, 512, 512, false)
			local mat = CreateMaterial("vrmod_worldtip_mat_" .. index, "UnlitGeneric", {
				["$basetexture"] = rt:GetName(),
				["$translucent"] = 1,
				["$vertexalpha"] = 1,
				["$vertexcolor"] = 1,
			})
			PaintTipRT(rt, tostring(text or ""))
			tips[index] = {
				text = text,
				pos = pos,
				ent = ent,
				mat = mat,
				rt = rt,
			}
		end

		tips[index].dietime = SysTime() + math.max(0.12, tonumber(dietime) or 0.15)
	end
end)

hook.Add("VRMod_Exit", "worldtips", function(ply)
	if ply ~= LocalPlayer() then return end
	if AddWorldTip_orig then
		AddWorldTip = AddWorldTip_orig
	end
	hook.Remove("PostDrawTranslucentRenderables", "vrmod_worldtips")
	hook.Remove("VRMod_PostRender", "vrmod_worldtips_once")
	tips = {}
	drawnFrame = -1
end)
