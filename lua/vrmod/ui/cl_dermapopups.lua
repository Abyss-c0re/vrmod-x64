if SERVER then return end
-- =============================================================================
-- Derma popup intercept — now owned by vrmod.web2vr (cl_web2vr.lua)
-- This file remains for load-order compatibility and a thin bridge.
-- Legacy MakePopup hook is intentionally NOT installed here (double-manifest).
-- =============================================================================

-- Re-export convenience for older call sites
function VRUtilManifestPanel(panel, opts)
	if vrmod and vrmod.web2vr and vrmod.web2vr.ManifestPanel then
		return vrmod.web2vr.ManifestPanel(panel, opts)
	end
end

-- If web2vr failed to load for any reason, install a minimal fallback once.
hook.Add("InitPostEntity", "vrmod_dermapopups_fallback", function()
	timer.Simple(1, function()
		if vrmod and vrmod.web2vr and vrmod.web2vr.InstallHooks then
			vrmod.web2vr.InstallHooks()
			return
		end
		-- Absolute fallback: previous MakePopup paint path (best-effort)
		if not g_VR then return end
		local meta = getmetatable(vgui.GetWorldPanel())
		if not meta or meta._vrmod_popup_fallback then return end
		meta._vrmod_popup_fallback = true
		local orig = meta.MakePopup
		meta.MakePopup = function(panel, ...)
			orig(panel, ...)
			if not (g_VR and g_VR.threePoints and g_VR.active) then return end
			if not IsValid(panel) or not isfunction(VRUtilMenuOpen) then return end
			timer.Simple(0.05, function()
				if not IsValid(panel) then return end
				panel:SetPaintedManually(true)
				local w, h = panel:GetSize()
				w = math.Clamp(w or 512, 128, 1024)
				h = math.Clamp(h or 512, 128, 1024)
				local uid = "popup_fb_" .. tostring(panel)
				VRUtilMenuOpen(uid, w, h, panel, true, Vector(10, 10, 5), Angle(0, -90, 50), 0.03, true, function()
					if IsValid(panel) then panel:SetPaintedManually(false) end
				end)
			end)
		end
	end)
end)
