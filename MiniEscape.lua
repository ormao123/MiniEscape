local version = 1.0

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
		Config = Config:addParam()
		print("MiniEscape Loaded")
	end)

AddTickCallback(
	function()
		
	end)

AddRecvPacketCallback(
	function(p)
		if (flashSlot ~= nil and p.header == 181) then
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
					local pos = vStartPos - (vStartPos - vEndPos):normalized() * 475
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
						local healthCheck =
							function()
								
							end
						local flashpos = (Vector(myHero.visionPos) - pos):normalized() * 475
						Packet("S_CAST", {spellId = flashSlot, toX = flashpos.x, toY = flashpos.z, fromX = flashpos.x, fromY = flashpos.z}):send()
					end
				end
			end
	end)