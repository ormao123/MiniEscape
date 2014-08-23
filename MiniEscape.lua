local version = 1.0
local FLASH_RANGE = 400

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
		return delayedActions, t, #t
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
		Config:addParam("duration", "Duration that Escape Remains on After Press", SCRIPT_PARAM_SLICE, 3, 1, 10)
		Config:addParam("autoLowHP", "Auto Escape on Low HP", SCRIPT_PARAM_ONOFF, false)
		Config:addParam("dist", "Distance Required from Flash Position to myHero to Flash Away", SCRIPT_PARAM_SLICE, 100, 10, 500)
		Config:addParam("Angle", "Angle Required Between Flash Position and myHero to Flash Away", SCRIPT_PARAM_SLICE, 30, 0, 90)
		print("MiniEscape Loaded")
	end)

AddMsgCallback(
	function(msg, key)
		if (key == Config._param.flash.key) then
			if (msg == KEY_UP) then
				buttonDown = false
			end
			if (msg == KEY_DOWN) then
				if (not buttonDown and Config.flash) then
					if (#delayedActions ~= 0) then
						for i, v in ipairs(delayedActions) do
							table.remove(delayedActions, i)
						end
					end
					DelayActionEx(
						function()
							if (Config.flash ~= false) then
								Config.flash = false
							end
						end, Config.duration)
					buttonDown = true
				end
			end
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
								if (GetDistance(vector, actualPos) <= 10) then
									return vector
								end
							end
							return actualPos
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
					local towardsMe = 
						function(pos)
							local myPos = Vector(myHero.visionPos.x, myHero.visionPos.y, myHero.visionPos.z)
							if (pos:dist(myPos) <= Config.dist) then
								local c = myPos:crossP(pos)
								local f = c:crossP(myPos)
								local angle = f:angle(myPos)
								local finalPos = math.cos(angle) * myPos + math.sin(angle) * f
								local angleBetween = finalPos:angle(myPos)
								if (angleBetween <= Config.angle) then
									return true
								end
							end
							return false
						end
					if (towardsMe(pos)) then
						local checkHP =
							function()
								if ((myHero.maxHealth / myHero.health) < HP_LIMIT) then
									return true
								end
								return Config.flash
							end

						if (checkHP()) then
							local flashpos = (Vector(myHero.visionPos) - pos):normalized() * FLASH_RANGE
							Packet("S_CAST", {spellId = flashSlot, toX = flashpos.x, toY = flashpos.z, fromX = flashpos.x, fromY = flashpos.z}):send()
						end
					end
				end
			end
	end)