local version = 1.0
local FLASH_RANGE = 400
local HP_LIMIT = 0.8

local delayedActions, delayedActionsExecuter = {}, nil
local DelayActionEx = 
	function(func, delay, args)
		if (not delayedActionsExecuter) then
			function delayedActionsExecuter()
				for t, funcs in pairs(delayedActions) do
					if (t <= os.clock()) then
						for _, f in ipairs(funcs) do 
							f.func(table.unpack(f.args or {})) 
						end
						delayedActions[t] = nil
					end
				end
			end

			AddTickCallback(delayedActionsExecuter)
		end
		local t = os.clock() + (delay or 0)
		if (delayedActions[t]) then 
			table.insert(delayedActions[t], { func = func, args = args })
		else
			delayedActions[t] = { { func = func, args = args } }
		end
	end

AddLoadCallback(
	function()
		local findFlashSlot = 
			function()
				if (string.find(player:GetSpellData(SUMMONER_1).name, "SummonerFlash") ~= nil) then
					return SUMMONER_1
				elseif (string.find(player:GetSpellData(SUMMONER_2).name, "SummonerFlash") ~= nil) then
					return SUMMONER_2
				end
				return nil
			end
		flashSlot = findFlashSlot()
		if (flashSlot == nil) then
			print("No flash found. Exiting script.")
			return
		end
		Config = scriptConfig("MiniEscape", "MiniEscape")
		Config:addParam("flash", "Escape!", SCRIPT_PARAM_ONKEYTOGGLE, false, GetKey("V"))
		Config:addParam("duration", "Duration that Escape Remains on", SCRIPT_PARAM_SLICE, 3, 1, 10)
		Config:addParam("autoLowHP", "Auto Escape on Low HP", SCRIPT_PARAM_ONOFF, false)
		Config:addParam("dist", "Distance Required", SCRIPT_PARAM_SLICE, 100, 10, 800)
		Config:addParam("angle", "Angle Required", SCRIPT_PARAM_SLICE, 180, 0, 180)
		Config:addParam("draw", "Notify When Escape is On", SCRIPT_PARAM_ONOFF, true)
		print("MiniEscape Loaded")
	end)

AddMsgCallback(
	function(msg, key)
		if (key == Config._param[1].key) then
			if (msg == KEY_DOWN) then
				if (not Config.flash) then
					DelayActionEx(
						function()
							if (Config.flash ~= false and #delayedActions ~= 1) then
								Config.flash = false
							end
						end, Config.duration)
					buttonDown = true
				end
			end
		end
	end)

AddDrawCallback(
	function()
		if (Config.flash) then
			local x, y = WINDOW_W / 2, (WINDOW_H - (WINDOW_H * 0.82))
			DrawTextA("FLASH ESCAPE ON", 20, x, y, ARGB(255, 255, 0, 0), "center", "center")
		end
	end)

AddRecvPacketCallback(
	function(p)
		if (flashSlot ~= nil and (Config.flash or Config.autoLowHP) and p.header == 0xB5) then
			p.pos = 1
			local blinker = objManager:GetObjectByNetworkId(p:DecodeF())
			if (blinker ~= nil and blinker.valid and blinker.type == myHero.type and blinker.visible and blinker.team ~= myHero.team) then	
				p.pos = 12
				local spell = p:Decode1()
				if (spell == 0xA8) then
					p.pos = 41
					local x, y, z = p:DecodeF(), p:DecodeF(), p:DecodeF()
					p.pos = 92
					local startX, startY, startZ = p:DecodeF(), p:DecodeF(), p:DecodeF()
					local checkData = 
						function(x, y, z, actualPos)
							if (x and y and z) then
								local vector = Vector(x, y, z)
								if (GetDistance(vector, actualPos) <= 30) then
									return vector
								end
							end
							return Vector(actualPos)
						end

					local vStartPos = checkData(startX, startY, startZ, blinker.visionPos)
					local vEndPos = Vector(x, y, z)
					local checkFinalPos = 
						function(startPos, endPos)
							if (GetDistance(startPos, endPos) <= FLASH_RANGE) then
								return endPos
							end

							return (startPos - (startPos - endPos):normalized() * FLASH_RANGE)
						end
					local pos = checkFinalPos(vStartPos, vEndPos)
					local rotateVector =
						function(from, towrads)
							local c = from:crossP(towrads)
							local f = c:crossP(from)
							local angle = f:angleBetween(f, from)
							finalPos = math.cos(angle) * from + math.sin(angle) * f
							return finalPos
						end
					local towardsMe = 
						function(pos)
							local myPos = Vector(myHero.visionPos.x, myHero.visionPos.y, myHero.visionPos.z)
							print(pos:dist(myPos))
							if (pos:dist(myPos) <= Config.dist) then
								local newPos = rotateVector(myPos, pos)
								local angleBetween = newPos:angleBetween(newPos, pos)
								if (angleBetween <= Config.angle) then
									return true
								end
								return true
							end
							return false
						end
					if (towardsMe(pos)) then
						local checkHP =
							function()
								if (not Config.flash and (myHero.maxHealth / myHero.health) < HP_LIMIT) then
									return true
								end
								return Config.flash
							end

						if (checkHP()) then
							local myVisionPos = rotateVector(Vector(myHero.visionPos), pos)
							local enemyPos = rotateVector(pos, myVisionPos)
							local flashpos = (myVisionPos - pos):normalized() * FLASH_RANGE
							Packet("S_CAST", {spellId = flashSlot, toX = flashpos.x, toY = flashpos.z, fromX = flashpos.x, fromY = flashpos.z}):send()
						end
					end
				end
			end
		end
	end)