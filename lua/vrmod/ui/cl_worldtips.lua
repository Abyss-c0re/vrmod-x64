if SERVER then return end
local tips = {}
local localAng = Angle(0, -90, 90)
local AddWorldTip_orig
timer.Simple(0, function() AddWorldTip_orig = AddWorldTip end)
hook.Add("VRMod_Start", "worldtips", function(ply)
	if ply ~= LocalPlayer() then return end
	AddWorldTip = function(entindex, text, dietime, pos, ent)
		if #tips == 0 then
			hook.Add("PostDrawTranslucentRenderables", "vrmod_worldtips", function(depth, sky)
				if depth or sky or EyePos() ~= g_VR.view.origin then return end
				local curtime = SysTime()
				surface.SetDrawColor(255, 255, 255, 255)
				cam.IgnoreZ(true) --$ignorez in material didn't seem to work
				local tms = render.GetToneMappingScaleLinear()
				render.SetToneMappingScaleLinear(Vector(0.75, 0.75, 0.75))
				local i = 1
				while tips[i] do
					local v = tips[i]
					if curtime > v.dietime or not IsValid(v.ent) then
						table.remove(tips, i)
						continue
					end

					local pos = v.ent and v.ent:GetPos() or v.pos
					local scale = (g_VR.tracking.hmd.pos - pos):Length() * math.tan(0.0014)
					local pos, ang = LocalToWorld(Vector(0, scale * 512, scale * 512), localAng, pos, (pos - g_VR.tracking.hmd.pos):Angle())
					cam.Start3D2D(pos, ang, scale)
					surface.SetMaterial(v.mat)
					surface.DrawTexturedRect(0, 0, 512, 512)
					cam.End3D2D()
					i = i + 1
				end

				cam.IgnoreZ(false)
				render.SetToneMappingScaleLinear(tms)
				if #tips == 0 then hook.Remove("PostDrawTranslucentRenderables", "vrmod_worldtips") end
			end)
		end

		local index = #tips + 1
		for i = 1, #tips do
			if tips[i].ent == ent or tips[i].pos == pos then
				index = i
				break
			end
		end

		if not tips[index] or tips[index].text ~= text then
			local rt = GetRenderTarget("worldtip" .. index, 512, 512, false)
			local mat = CreateMaterial("worldtip" .. index, "UnlitGeneric", {
				["$basetexture"] = rt:GetName(),
				["$translucent"] = 1
			})

			render.PushRenderTarget(rt)
			render.ClearDepth()
			render.Clear(0, 0, 0, 0)
			cam.Start2D()
			local pos = {
				x = 512,
				y = 512
			}

			local black = Color(0, 0, 0, 255)
			local tipcol = Color(250, 250, 200, 255)
			local x = 0
			local y = 0
			local padding = 10
			local offset = 50
			surface.SetFont("GModWorldtip")
			local w, h = surface.GetTextSize(text)
			x = pos.x - w
			y = pos.y - h
			x = x - offset
			y = y - offset
			draw.RoundedBox(8, x - padding - 2, y - padding - 2, w + padding * 2 + 4, h + padding * 2 + 4, black)
			local verts = {}
			verts[1] = {
				x = x + w / 1.5 - 2,
				y = y + h + 2
			}

			verts[2] = {
				x = x + w + 2,
				y = y + h / 2 - 1
			}

			verts[3] = {
				x = pos.x - offset / 2 + 2,
				y = pos.y - offset / 2 + 2
			}

			draw.NoTexture()
			surface.SetDrawColor(0, 0, 0, tipcol.a)
			surface.DrawPoly(verts)
			draw.RoundedBox(8, x - padding, y - padding, w + padding * 2, h + padding * 2, tipcol)
			local verts = {}
			verts[1] = {
				x = x + w / 1.5,
				y = y + h
			}

			verts[2] = {
				x = x + w,
				y = y + h / 2
			}

			verts[3] = {
				x = pos.x - offset / 2,
				y = pos.y - offset / 2
			}

			draw.NoTexture()
			surface.SetDrawColor(tipcol.r, tipcol.g, tipcol.b, tipcol.a)
			surface.DrawPoly(verts)
			draw.DrawText(text, "GModWorldtip", x + w / 2, y, black, TEXT_ALIGN_CENTER)
			--
			cam.End2D()
			render.PopRenderTarget()
			tips[index] = {
				text = text,
				pos = pos,
				ent = ent,
				mat = mat
			}
			--LocalPlayer():ChatPrint(tostring(SysTime()).." AddWorldTip update")
		end

		tips[index].dietime = SysTime() + 0.1
	end
end)

hook.Add("VRMod_Exit", "worldtips", function(ply)
	if ply ~= LocalPlayer() then return end
	AddWorldTip = AddWorldTip_orig
	hook.Remove("PostDrawTranslucentRenderables", "vrmod_worldtips")
	tips = {}
end)