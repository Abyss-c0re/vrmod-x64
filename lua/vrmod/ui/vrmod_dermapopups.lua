if SERVER then return end
local meta = getmetatable(vgui.GetWorldPanel())
local orig = meta.MakePopup
local popupCount = 0
local basePos, baseAng
local _, convarValues = vrmod.GetConvars()
local sW, sH = ScrW(), ScrH()

-- All active popups
local allPopups = {}
meta.MakePopup = function(...)
	local args = {...}
	orig(unpack(args))
	if not g_VR.threePoints then return end
	local panel = args[1]
	local uid = "popup_" .. popupCount
	-- Add the new popup to the list
	table.insert(allPopups, uid)
	
	--wait because makepopup might be called before menu is fully built
	timer.Simple(
		0.1,
		function()
			if not IsValid(panel) then return end
			panel:SetPaintedManually(true)
			if panel:GetName() == "DMenu" then
				--temporary hack because paintmanual doesnt seem to work on the dmenu for some reason
				panel = panel:GetChildren()[1]
				panel.Paint = function(self, w, h)
					surface.SetDrawColor(150, 149, 160)
					surface.DrawRect(0, 0, w, h)
				end
				popupCount = popupCount + 1
			end

			if panel:GetName() == "DImage" then
				--temporary hack because paintmanual doesnt seem to work on the dmenu for some reason
				panel = panel:GetChildren()[1]
				panel.Paint = function(self, w, h)
					surface.SetDrawColor(175, 174, 187)
					surface.DrawRect(0, 0, w, h)
				end

				popupCount = popupCount + 1
			end

			if panel:GetName() == "DPanel" then
				panel = panel:GetChildren()[1]
				panel.Paint = function(self, w, h)
					surface.SetDrawColor(175, 174, 187)
					surface.DrawRect(0, 0, w, h)
				end

				popupCount = popupCount + 1

			end

			if popupCount == 0 then
				local ang = Angle(0, g_VR.tracking.hmd.ang.yaw - 90, 45)
				basePos, baseAng = WorldToLocal(g_VR.tracking.hmd.pos + Vector(0, 0, -20) + Angle(0, g_VR.tracking.hmd.ang.yaw, 0):Forward() * 30 + ang:Forward() * sW * -0.02 + ang:Right() * sH * -0.02, ang, g_VR.origin, g_VR.originAngle)
			end

			--right = down, up = normal, forward = right
			local ang = baseAng
			local pos = basePos + ang:Up() * popupCount * 0.1
			local mode = convarValues.vrmod_attach_popup
			if mode == 1 then
				--
				--forw, left, up
				VRUtilMenuOpen(uid,sW,sH,panel,mode,Vector(20, 11, 8),Angle(0, -90, 50),0.03,true,function()
					timer.Simple(
						0.1,
						function()
							if not g_VR.active and IsValid(panel) then
								panel:MakePopup() --make sure we don't leave unclickable panels open when exiting vr
								panel:RequestFocus()
							end
						end
					)

					popupCount = popupCount - 1
					-- Remove the popup from the list when it closes
					for i, v in ipairs(allPopups) do
						if v == uid then
							table.remove(allPopups, i)
							break
						end
					end
				end)

				popupCount = popupCount + 1
				VRUtilMenuRenderPanel(uid)
				--
			elseif mode == 3 then
				--forw, left, up
				VRUtilMenuOpen(uid,sW,sH,panel,3,Vector(30, 20, 10),Angle(0, -90, 90),0.03,true,function()
					timer.Simple(
						0.1,
						function()
							if not g_VR.active and IsValid(panel) then
								panel:MakePopup() --make sure we don't leave unclickable panels open when exiting vr
								panel:RequestFocus()
							end
						end
					)

					popupCount = popupCount - 1
					-- Remove the popup from the list when it closes
					for i, v in ipairs(allPopups) do
						if v == uid then
							table.remove(allPopups, i)
							break
						end
					end
				end)

				popupCount = popupCount + 1
				VRUtilMenuRenderPanel(uid)
			else --
				--forw, left, up
				VRUtilMenuOpen(uid,sW,sH,panel,mode,pos,ang,0.03,true,function()
					timer.Simple(
						0.1,
						function()
							if not g_VR.active and IsValid(panel) then
								panel:MakePopup() --make sure we don't leave unclickable panels open when exiting vr
								panel:RequestFocus()

							end
						end
					)

					popupCount = popupCount - 1
					-- Remove the popup from the list when it closes
					for i, v in ipairs(allPopups) do
						if v == uid then
							table.remove(allPopups, i)
							break
						end
					end
				end)

				popupCount = popupCount + 1
				VRUtilMenuRenderPanel(uid)
			end
		end
	)
end

-- Render all popups every frame
hook.Add(
	"Think",
	"update_all_popups",
	function()
		for _, uid in ipairs(allPopups) do
			VRUtilMenuRenderPanel(uid)
		end
	end
)

hook.Add("VRMod_Start","dermapopups",function(ply)
	if ply ~= LocalPlayer() then return end
	vgui.GetWorldPanel():SetSize(sW,sH)
end)

hook.Add("VRMod_Exit","dermapopups",function(ply)
	if ply ~= LocalPlayer() then return end
	vgui.GetWorldPanel():SetSize(ScrW(),ScrH())
end)
