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

--AUTOUPDATER, THANK YOU SUPERX321 SENPAI
AddLoadCallback(
	function()
		print("<font color=\"#FF0F0F\">Loaded MiniEscape version " .. version .. ".</font>")
		TCPU = TCPUpdater()
		TCPU:AddScript(_OwnEnv, "Script", "raw.githubusercontent.com","/germansk8ter/MiniEscape/master/MiniEscape.lua","/germansk8ter/MiniEscape/master/MiniEscape.version", "local version =")
	end)

------------------------
------ TCPUpdater ------
------------------------
class "TCPUpdater"
function TCPUpdater:__init()
	_G.TCPUpdates = {}
	_G.TCPUpdaterLoaded = true
	self.AutoUpdates = {}
	self.LuaSocket = require("socket")
	AddTickCallback(function() self:TCPUpdate() end)
end

function TCPUpdater:TCPUpdate()
	for i=1,#self.AutoUpdates do
		if not self.AutoUpdates[i]["ScriptPath"] then
			self.AutoUpdates[i]["ScriptPath"] = self:GetScriptPath(self.AutoUpdates[i])
		end

		if self.AutoUpdates[i]["ScriptPath"] and not self.AutoUpdates[i]["LocalVersion"] then
			self.AutoUpdates[i]["LocalVersion"] = self:GetLocalVersion(self.AutoUpdates[i])
		end
		if not self.AutoUpdates[i]["ServerVersion"] and self.AutoUpdates[i]["ScriptPath"] and self.AutoUpdates[i]["LocalVersion"] then
			self.AutoUpdates[i]["ServerVersion"] = self:GetOnlineVersion(self.AutoUpdates[i])
		end

		if self.AutoUpdates[i]["ServerVersion"] and self.AutoUpdates[i]["LocalVersion"] and self.AutoUpdates[i]["ScriptPath"] and not _G.TCPUpdates[self.AutoUpdates[i]["Name"]] then
			if self.AutoUpdates[i]["ServerVersion"] > self.AutoUpdates[i]["LocalVersion"] then
				print("<font color=\"#F0Ff8d\"><b>" .. self.AutoUpdates[i]["Name"] .. ":</b></font> <font color=\"#FF0F0F\">Updating ".. self.AutoUpdates[i]["Name"].." to Version "..self.AutoUpdates[i]["ServerVersion"].."</font>")
				self:DownloadUpdate(self.AutoUpdates[i])
			else
				self:LoadScript(self.AutoUpdates[i])
			end
		end
	end
end

function TCPUpdater:LoadScript(TCPScript)
	if TCPScript["ScriptRequire"] then
		if TCPScript["ScriptRequire"] == "VIP" then
			if VIP_USER then
				loadfile(TCPScript["ScriptPath"])()
			end
		else
			loadfile(TCPScript["ScriptPath"])()
		end
	end
	_G.TCPUpdates[TCPScript["Name"]] = true
end

function TCPUpdater:GetScriptPath(TCPScript)
	if TCPScript["Type"] == "Lib" then
		return LIB_PATH..TCPScript["Name"]..".lua"
	else
		return SCRIPT_PATH..TCPScript["Name"]..".lua"
	end
end

function TCPUpdater:GetOnlineVersion(TCPScript)
	if not TCPScript["VersionSocket"] then
		TCPScript["VersionSocket"] = self.LuaSocket.connect("sx-bol.eu", 80)
		TCPScript["VersionSocket"]:send("GET /BoL/TCPUpdater/GetScript.php?script="..TCPScript["Host"]..TCPScript["VersionLink"].."&rand="..tostring(math.random(1000)).." HTTP/1.0\r\n\r\n")
	end

	if TCPScript["VersionSocket"] then
		TCPScript["VersionSocket"]:settimeout(0)
		TCPScript["VersionReceive"], TCPScript["VersionStatus"] = TCPScript["VersionSocket"]:receive('*a')
	end

	if TCPScript["VersionSocket"] and TCPScript["VersionStatus"] ~= 'timeout' then
		if TCPScript["VersionReceive"] == nil then
			return 0
		else
			return tonumber(string.sub(TCPScript["VersionReceive"], string.find(TCPScript["VersionReceive"], "<bols".."cript>")+11, string.find(TCPScript["VersionReceive"], "</bols".."cript>")-1))
		end
	end
end

function TCPUpdater:GetLocalVersion(TCPScript)
	if FileExist(TCPScript["ScriptPath"]) then
		self.FileOpen = io.open(TCPScript["ScriptPath"], "r")
		self.FileString = self.FileOpen:read("*a")
		self.FileOpen:close()
		VersionPos = self.FileString:find(TCPScript["VersionSearchString"])
		if VersionPos ~= nil then
			self.VersionString = string.sub(self.FileString, VersionPos + string.len(TCPScript["VersionSearchString"]) + 1, VersionPos + string.len(TCPScript["VersionSearchString"]) + 11)
			self.VersionSave = tonumber(string.match(self.VersionString, "%d *.*%d"))
		end
		if self.VersionSave == 2.431 then self.VersionSave = math.huge end -- VPred 2.431
		if self.VersionSave == nil then self.VersionSave = 0 end
	else
		self.VersionSave = 0
	end
	return self.VersionSave
end

function TCPUpdater:DownloadUpdate(TCPScript)
	if not TCPScript["ScriptSocket"] then
		TCPScript["ScriptSocket"] = self.LuaSocket.connect("sx-bol.eu", 80)
		TCPScript["ScriptSocket"]:send("GET /BoL/TCPUpdater/GetScript.php?script="..TCPScript["Host"]..TCPScript["ScriptLink"].."&rand="..tostring(math.random(1000)).." HTTP/1.0\r\n\r\n")
	end

	if TCPScript["ScriptSocket"] then
		TCPScript["ScriptReceive"], TCPScript["ScriptStatus"] = TCPScript["ScriptSocket"]:receive('*a')
	end

	if TCPScript["ScriptSocket"] and TCPScript["ScriptStatus"] ~= 'timeout' then
		if TCPScript["ScriptReceive"] == nil then
			print("Error in Loading Module: "..TCPScript["Name"])
		else
			self.FileOpen = io.open(TCPScript["ScriptPath"], "w+")
			self.FileOpen:write(string.sub(TCPScript["ScriptReceive"], string.find(TCPScript["ScriptReceive"], "<bols".."cript>")+11, string.find(TCPScript["ScriptReceive"], "</bols".."cript>")-1))
			self.FileOpen:close()
			print("<font color=\"#FF0F0F\">Updated script. Please double F9.</font>")
			self:LoadScript(TCPScript)
		end
	end
end

function TCPUpdater:AddScript(Name, Type, Host, ScriptLink, VersionLink, VersionSearchString, ScriptRequire, ServerVersion)
	table.insert(self.AutoUpdates, {["Name"] = Name, ["Type"] = Type, ["Host"] = Host, ["ScriptLink"] = ScriptLink, ["VersionLink"] = VersionLink, ["VersionSearchString"] = VersionSearchString, ["ScriptRequire"] = ScriptRequire, ["ServerVersion"] = ServerVersion})
	_G.TCPUpdates[Name] = false
end