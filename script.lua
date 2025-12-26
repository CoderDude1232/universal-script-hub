-- [[ UNIVERSAL SCRIPT HUB ]] --

-- Imports
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

-- Services
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- Helpers
local function getChar()
	return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function getHumanoid()
	return getChar():WaitForChild("Humanoid")
end

local function getRoot()
	return getChar():WaitForChild("HumanoidRootPart")
end

local function getRootOf(plr)
	local char = plr.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoidOf(plr)
	local char = plr.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function getBackpack()
	return LocalPlayer:WaitForChild("Backpack")
end

local function isValidTeamName(teamName)
	if teamName == "All" then return true end
	return Teams:FindFirstChild(teamName) ~= nil
end

local function playerMatchesTeam(plr, teamName)
	if teamName == "All" then return true end
	local team = Teams:FindFirstChild(teamName)
	if not team then return true end
	return plr.Team == team
end

-- Window
local MINIMIZE_KEY = Enum.KeyCode.RightShift

local Window = Fluent:CreateWindow({
	Title = "Universal",
	SubTitle = "Script Hub",
	TabWidth = 160,
	Size = UDim2.fromOffset(720, 600),
	Acrylic = true,
	Theme = "Darker",
	MinimizeKey = MINIMIZE_KEY
})

-- Reliable RightShift minimize
UIS.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if Fluent.Unloaded then return end
	if input.KeyCode == MINIMIZE_KEY then
		Window:Minimize()
	end
end)

-- Tabs
local Tabs = {
	Player   = Window:AddTab({ Title = "Player",   Icon = "user" }),
	Movement = Window:AddTab({ Title = "Movement", Icon = "activity" }),
	Teleport = Window:AddTab({ Title = "Teleport", Icon = "map-pin" }),
	Visual   = Window:AddTab({ Title = "Visual",   Icon = "sun" }),
	ESP      = Window:AddTab({ Title = "ESP",      Icon = "eye" }),
	Utility  = Window:AddTab({ Title = "Utility",  Icon = "wrench" }),
	Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
}

-- Sections
local PlayerSec = Tabs.Player:AddSection("Stats")
local AltSpeedSec = Tabs.Player:AddSection("Alt Speed")
local WeaponSec = Tabs.Player:AddSection("Weapons")
local HealthSec = Tabs.Player:AddSection("Health")
local CameraSec = Tabs.Player:AddSection("Camera")

local MoveSec = Tabs.Movement:AddSection("Movement")
local UtilSec = Tabs.Movement:AddSection("Utility")

local TpSec = Tabs.Teleport:AddSection("Players")
local FollowSec = Tabs.Teleport:AddSection("Follow")
local SavedSec = Tabs.Teleport:AddSection("Waypoints")

local VisualSec = Tabs.Visual:AddSection("Lighting")
local FreecamSec = Tabs.Visual:AddSection("Freecam")

local EspSec = Tabs.ESP:AddSection("ESP")
local HitboxSec = Tabs.ESP:AddSection("Hitboxes")

local ServerSec = Tabs.Utility:AddSection("Server")
local TerminateSec = Tabs.Utility:AddSection("Terminate")

-- State
local state = {
	-- movement
	noclip = false,
	infiniteJump = false,
	fly = false,
	flySpeed = 60,

	-- lighting
	storedLighting = nil,

	-- waypoints
	savedPositions = {}, -- {Name=string, CFrame=CFrame}

	-- ESP
	espEnabled = false,
	espShowNames = true,
	espShowDistance = true,
	espShowHealth = true,
	espShowTeam = true,
	espTeamCheck = false,
	espMaxDistance = 1500,
	espRefreshRate = 0.15,
	espTracers = false,

	-- Hitboxes
	hitboxEnabled = false,
	hitboxSize = 8,
	hitboxTransparency = 0.6,

	-- Follow
	followEnabled = false,
	followPaused = false,
	followOffsetBack = 4,
	followOffsetUp = 0,
	followUpdateRate = 0.01,
	followSmoothness = 12,
	equipOnFollowOrTP = false,

	-- Health
	infHealth = false,
	infHealthTarget = 100,
	infHealthRate = 0.1,

	-- Weapons
	autoEquip = false,

	-- Team filter for targets
	targetTeamFilter = "All",

	-- Alt speed (does not change WalkSpeed)
	altSpeedEnabled = false,
	altSpeedBoost = 0,
	altSpeedMaxVel = 120,

	-- Freecam
	freecamEnabled = false,
	freecamSpeed = 48,
	freecamFastMult = 3,

	-- Terminate guard
	terminated = false,
}

-- Connection registry so terminate can cleanly disconnect
local connections = {}
local function track(conn)
	table.insert(connections, conn)
	return conn
end

-- =========================================================
-- Alt Speed (No WalkSpeed): velocity assist while moving
-- =========================================================
local function getMoveDirection()
	local char = LocalPlayer.Character
	if not char then return Vector3.zero end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return Vector3.zero end
	return hum.MoveDirection or Vector3.zero
end

track(RunService.Heartbeat:Connect(function(dt)
	if Fluent.Unloaded or state.terminated then return end
	if not state.altSpeedEnabled then return end
	if state.altSpeedBoost <= 0 then return end

	local char = LocalPlayer.Character
	if not char then return end

	local root = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then return end
	if hum.Health <= 0 then return end

	local dir = getMoveDirection()
	if dir.Magnitude < 0.05 then return end
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.05 then return end
	dir = dir.Unit

	local vel = root.AssemblyLinearVelocity
	local horiz = Vector3.new(vel.X, 0, vel.Z)

	local boosted = horiz + (dir * state.altSpeedBoost)
	local mag = boosted.Magnitude
	if mag > state.altSpeedMaxVel then
		boosted = boosted.Unit * state.altSpeedMaxVel
	end

	root.AssemblyLinearVelocity = Vector3.new(boosted.X, vel.Y, boosted.Z)
end))

-- =========================================================
-- Weapon Equipper
-- =========================================================
local weaponDropdown

local function getToolNames()
	local set = {}
	for _, inst in ipairs(getBackpack():GetChildren()) do
		if inst:IsA("Tool") then set[inst.Name] = true end
	end
	local char = LocalPlayer.Character
	if char then
		for _, inst in ipairs(char:GetChildren()) do
			if inst:IsA("Tool") then set[inst.Name] = true end
		end
	end

	local list = {}
	for name in pairs(set) do table.insert(list, name) end
	table.sort(list)
	return list
end

local function refreshWeaponDropdown(tryKeepSelection)
	if not weaponDropdown then return end
	local current = Fluent.Options.WeaponTool and Fluent.Options.WeaponTool.Value
	local values = getToolNames()
	weaponDropdown:SetValues(values)

	if tryKeepSelection and current and table.find(values, current) then
		Fluent.Options.WeaponTool:SetValue(current)
	elseif #values > 0 then
		Fluent.Options.WeaponTool:SetValue(values[1])
	end
end

local function findToolByName(name)
	if type(name) ~= "string" or name == "" then return nil end
	local bp = getBackpack()
	local t = bp:FindFirstChild(name)
	if t and t:IsA("Tool") then return t end
	local char = LocalPlayer.Character
	if char then
		local ct = char:FindFirstChild(name)
		if ct and ct:IsA("Tool") then return ct end
	end
	return nil
end

local function equipSelectedTool()
	local name = Fluent.Options.WeaponTool and Fluent.Options.WeaponTool.Value
	local tool = findToolByName(name)
	if not tool then return false end
	if tool.Parent == LocalPlayer.Character then return true end
	local ok = pcall(function()
		getHumanoid():EquipTool(tool)
	end)
	return ok
end

local function maybeEquipAfterAction()
	if not state.equipOnFollowOrTP then return end
	task.defer(equipSelectedTool)
end

WeaponSec:AddParagraph({ Title = "Item Equipper", Content = "Equips your item of choice." })

weaponDropdown = WeaponSec:AddDropdown("WeaponTool", {
	Title = "Tool",
	Description = "Select a Tool to equip.",
	Values = getToolNames(),
	Multi = false,
	Default = 1,
})
WeaponSec:AddButton({ Title = "Equip Selected", Callback = function() equipSelectedTool() end })
WeaponSec:AddToggle("AutoEquip", {
	Title = "Auto Equip Selected",
	Description = "Re-equips on respawn and when the tool returns to Backpack.",
	Default = false,
	Callback = function(on)
		state.autoEquip = on
		if on then equipSelectedTool() end
	end
})
WeaponSec:AddButton({ Title = "Refresh Tool List", Callback = function() refreshWeaponDropdown(true) end })

local function hookToolListeners()
	local bp = getBackpack()

	track(bp.ChildAdded:Connect(function(c)
		if c:IsA("Tool") then
			refreshWeaponDropdown(true)
			if state.autoEquip then task.defer(equipSelectedTool) end
		end
	end))

	track(bp.ChildRemoved:Connect(function(c)
		if c:IsA("Tool") then
			task.defer(function() refreshWeaponDropdown(true) end)
		end
	end))

	track(LocalPlayer.CharacterAdded:Connect(function(char)
		task.defer(function()
			refreshWeaponDropdown(true)
			if state.autoEquip then task.defer(equipSelectedTool) end
		end)

		track(char.ChildAdded:Connect(function(c)
			if c:IsA("Tool") then refreshWeaponDropdown(true) end
		end))

		track(char.ChildRemoved:Connect(function(c)
			if c:IsA("Tool") then task.defer(function() refreshWeaponDropdown(true) end) end
		end))
	end))

	if LocalPlayer.Character then task.defer(function() refreshWeaponDropdown(true) end) end
end
hookToolListeners()

-- =========================================================
-- Fly
-- =========================================================
local flyBV, flyBG, flyConn
local function stopFly()
	state.fly = false
	if flyConn then flyConn:Disconnect(); flyConn = nil end
	if flyBV then flyBV:Destroy(); flyBV = nil end
	if flyBG then flyBG:Destroy(); flyBG = nil end
end

local function startFly()
	stopFly()
	state.fly = true

	local root = getRoot()

	flyBV = Instance.new("BodyVelocity")
	flyBV.MaxForce = Vector3.new(1e9, 1e9, 1e9)
	flyBV.Velocity = Vector3.zero
	flyBV.Parent = root

	flyBG = Instance.new("BodyGyro")
	flyBG.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
	flyBG.P = 1e5
	flyBG.CFrame = root.CFrame
	flyBG.Parent = root

	flyConn = RunService.RenderStepped:Connect(function()
		if Fluent.Unloaded or state.terminated then return end
		if not state.fly then return end

		local camCF = Camera.CFrame
		local move = Vector3.zero

		if UIS:IsKeyDown(Enum.KeyCode.W) then move += camCF.LookVector end
		if UIS:IsKeyDown(Enum.KeyCode.S) then move -= camCF.LookVector end
		if UIS:IsKeyDown(Enum.KeyCode.A) then move -= camCF.RightVector end
		if UIS:IsKeyDown(Enum.KeyCode.D) then move += camCF.RightVector end
		if UIS:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.new(0, 1, 0) end
		if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.new(0, 1, 0) end

		if move.Magnitude > 0 then move = move.Unit * state.flySpeed end
		flyBV.Velocity = move
		flyBG.CFrame = camCF
	end)
end

-- =========================================================
-- Infinite health loop (client-side)
-- =========================================================
local infHealthTaskId = 0
local function stopInfHealth()
	state.infHealth = false
	infHealthTaskId += 1
end

local function startInfHealth()
	state.infHealth = true
	infHealthTaskId += 1
	local myId = infHealthTaskId

	task.spawn(function()
		while state.infHealth and (infHealthTaskId == myId) and not Fluent.Unloaded and not state.terminated do
			pcall(function()
				local hum = getHumanoid()
				if hum.MaxHealth < state.infHealthTarget then hum.MaxHealth = state.infHealthTarget end
				hum.Health = state.infHealthTarget
			end)
			task.wait(state.infHealthRate)
		end
	end)
end

-- =========================================================
-- Follow: pause on YOUR death
-- =========================================================
local localDiedConn
local function bindLocalDeath()
	if localDiedConn then localDiedConn:Disconnect(); localDiedConn = nil end
	local hum
	pcall(function() hum = getHumanoid() end)
	if not hum then return end
	localDiedConn = hum.Died:Connect(function()
		if state.followEnabled then state.followPaused = true end
	end)
	table.insert(connections, localDiedConn)
end

track(LocalPlayer.CharacterAdded:Connect(function()
	stopFly()
	if Fluent.Options.Fly then Fluent.Options.Fly:SetValue(false) end
	state.followPaused = false
	task.defer(bindLocalDeath)
	if state.autoEquip then task.defer(equipSelectedTool) end
	if state.infHealth then startInfHealth() end
end))
task.defer(bindLocalDeath)

-- =========================================================
-- Player tab UI
-- =========================================================
PlayerSec:AddSlider("WalkSpeed", {
	Title = "WalkSpeed",
	Default = 16, Min = 0, Max = 250, Rounding = 0,
	Callback = function(v) pcall(function() getHumanoid().WalkSpeed = v end) end
})
PlayerSec:AddSlider("JumpPower", {
	Title = "JumpPower",
	Default = 50, Min = 0, Max = 250, Rounding = 0,
	Callback = function(v) pcall(function() getHumanoid().JumpPower = v end) end
})

AltSpeedSec:AddToggle("AltSpeedEnabled", {
	Title = "Speed",
	Description = "Adds extra horizontal velocity while moving. Works even if the game resets WalkSpeed.",
	Default = false,
	Callback = function(on) state.altSpeedEnabled = on end
})
AltSpeedSec:AddSlider("AltSpeedBoost", {
	Title = "Boost Amount",
	Description = "Extra studs/sec added while moving.",
	Default = 0, Min = 0, Max = 150, Rounding = 0,
	Callback = function(v) state.altSpeedBoost = v end
})
AltSpeedSec:AddSlider("AltSpeedMaxVel", {
	Title = "Max Horizontal Velocity",
	Default = 120, Min = 20, Max = 300, Rounding = 0,
	Callback = function(v) state.altSpeedMaxVel = v end
})

HealthSec:AddToggle("InfHealth", {
	Title = "Infinite Health",
	Description = "Infinite health on client. Other clients can bypass.",
	Default = false,
	Callback = function(on) if on then startInfHealth() else stopInfHealth() end end
})
HealthSec:AddSlider("InfHealthTarget", {
	Title = "Health Target",
	Default = 100, Min = 1, Max = 500, Rounding = 0,
	Callback = function(v) state.infHealthTarget = v end
})
HealthSec:AddSlider("InfHealthRate", {
	Title = "Loop Rate",
	Default = 0.1, Min = 0.05, Max = 1, Rounding = 2,
	Callback = function(v) state.infHealthRate = v end
})

CameraSec:AddSlider("FOV", {
	Title = "FOV",
	Default = 70, Min = 30, Max = 120, Rounding = 0,
	Callback = function(v) Camera.FieldOfView = v end
})

PlayerSec:AddButton({
	Title = "Reset Player",
	Callback = function()
		pcall(function()
			local hum = getHumanoid()
			hum.WalkSpeed = 16
			hum.JumpPower = 50
			Camera.FieldOfView = 70
		end)

		state.altSpeedEnabled = false
		state.altSpeedBoost = 0
		state.altSpeedMaxVel = 120

		if Fluent.Options.WalkSpeed then Fluent.Options.WalkSpeed:SetValue(16) end
		if Fluent.Options.JumpPower then Fluent.Options.JumpPower:SetValue(50) end
		if Fluent.Options.FOV then Fluent.Options.FOV:SetValue(70) end
		if Fluent.Options.AltSpeedEnabled then Fluent.Options.AltSpeedEnabled:SetValue(false) end
		if Fluent.Options.AltSpeedBoost then Fluent.Options.AltSpeedBoost:SetValue(0) end
		if Fluent.Options.AltSpeedMaxVel then Fluent.Options.AltSpeedMaxVel:SetValue(120) end
	end
})

-- =========================================================
-- Movement tab UI + logic
-- =========================================================
MoveSec:AddToggle("Noclip", { Title = "Noclip", Default = false, Callback = function(on) state.noclip = on end })
MoveSec:AddToggle("InfiniteJump", { Title = "Infinite Jump", Default = false, Callback = function(on) state.infiniteJump = on end })

MoveSec:AddSlider("Gravity", {
	Title = "Gravity",
	Default = Workspace.Gravity,
	Min = 0, Max = 300, Rounding = 0,
	Callback = function(v) Workspace.Gravity = v end
})

MoveSec:AddToggle("Fly", { Title = "Fly", Default = false, Callback = function(on) if on then startFly() else stopFly() end end })
MoveSec:AddSlider("FlySpeed", { Title = "Fly Speed", Default = 60, Min = 10, Max = 250, Rounding = 0, Callback = function(v) state.flySpeed = v end })

MoveSec:AddButton({
	Title = "Reset Movement",
	Callback = function()
		state.noclip = false
		state.infiniteJump = false
		stopFly()
		Workspace.Gravity = 196.2
		state.flySpeed = 60
		pcall(function()
			local hum = getHumanoid()
			hum.WalkSpeed = 16
			hum.JumpPower = 50
		end)
		if Fluent.Options.Noclip then Fluent.Options.Noclip:SetValue(false) end
		if Fluent.Options.InfiniteJump then Fluent.Options.InfiniteJump:SetValue(false) end
		if Fluent.Options.Fly then Fluent.Options.Fly:SetValue(false) end
		if Fluent.Options.Gravity then Fluent.Options.Gravity:SetValue(196.2) end
		if Fluent.Options.FlySpeed then Fluent.Options.FlySpeed:SetValue(60) end
		if Fluent.Options.WalkSpeed then Fluent.Options.WalkSpeed:SetValue(16) end
		if Fluent.Options.JumpPower then Fluent.Options.JumpPower:SetValue(50) end
	end
})

UtilSec:AddButton({
	Title = "Sit / Unsit",
	Callback = function()
		pcall(function()
			local hum = getHumanoid()
			hum.Sit = not hum.Sit
		end)
	end
})

track(UIS.JumpRequest:Connect(function()
	if Fluent.Unloaded or state.terminated then return end
	if not state.infiniteJump then return end
	pcall(function() getHumanoid():ChangeState(Enum.HumanoidStateType.Jumping) end)
end))

track(RunService.Stepped:Connect(function()
	if Fluent.Unloaded or state.terminated then return end
	if not state.noclip then return end
	local char = LocalPlayer.Character
	if not char then return end
	for _, v in ipairs(char:GetDescendants()) do
		if v:IsA("BasePart") then v.CanCollide = false end
	end
end))

-- =========================================================
-- Teleport tab (+ Follow) with Team Filter
-- =========================================================
local TeamDropdown
local TpDropdown

local function getTeamNames()
	local values = { "All" }
	for _, team in ipairs(Teams:GetChildren()) do
		if team:IsA("Team") then table.insert(values, team.Name) end
	end
	table.sort(values, function(a, b)
		if a == "All" then return true end
		if b == "All" then return false end
		return a < b
	end)
	return values
end

local function getPlayerNamesFiltered()
	local teamName = state.targetTeamFilter
	if not isValidTeamName(teamName) then teamName = "All" end
	local names = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if playerMatchesTeam(p, teamName) then table.insert(names, p.Name) end
	end
	table.sort(names)
	return names
end

local function refreshTeamDropdown(tryKeep)
	if not TeamDropdown then return end
	local current = Fluent.Options.TeamFilter and Fluent.Options.TeamFilter.Value or "All"
	local values = getTeamNames()
	TeamDropdown:SetValues(values)
	if tryKeep and table.find(values, current) then
		Fluent.Options.TeamFilter:SetValue(current)
	else
		Fluent.Options.TeamFilter:SetValue("All")
	end
end

local function refreshTargetDropdown(tryKeepTarget)
	if not TpDropdown then return end
	local current = Fluent.Options.TPPlayer and Fluent.Options.TPPlayer.Value
	local values = getPlayerNamesFiltered()
	TpDropdown:SetValues(values)
	if tryKeepTarget and current and table.find(values, current) then
		Fluent.Options.TPPlayer:SetValue(current)
	elseif #values > 0 then
		Fluent.Options.TPPlayer:SetValue(values[1])
	end
end

local function getFollowablePlayersOrdered()
	local teamName = state.targetTeamFilter
	if not isValidTeamName(teamName) then teamName = "All" end
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer and playerMatchesTeam(p, teamName) then
			table.insert(list, p.Name)
		end
	end
	table.sort(list)
	return list
end

local function pickNextName(currentName)
	local list = getFollowablePlayersOrdered()
	if #list == 0 then return nil end
	if not currentName then return list[1] end
	local idx
	for i, name in ipairs(list) do
		if name == currentName then idx = i break end
	end
	if not idx then return list[1] end
	local nextIdx = idx + 1
	if nextIdx > #list then nextIdx = 1 end
	return list[nextIdx]
end

local function setTargetDropdown(name)
	if not name then return end
	if Fluent.Options.TPPlayer and Fluent.Options.TPPlayer.SetValue then
		Fluent.Options.TPPlayer:SetValue(name)
	end
end

TeamDropdown = TpSec:AddDropdown("TeamFilter", {
	Title = "Team Filter",
	Description = "Target list will only show players on this team.",
	Values = getTeamNames(),
	Multi = false,
	Default = 1,
})

TeamDropdown:OnChanged(function(val)
	if type(val) ~= "string" then return end
	if not isValidTeamName(val) then val = "All" end
	state.targetTeamFilter = val
	refreshTargetDropdown(false)
end)

TpDropdown = TpSec:AddDropdown("TPPlayer", {
	Title = "Target",
	Values = getPlayerNamesFiltered(),
	Multi = false,
	Default = 1,
})

track(Teams.ChildAdded:Connect(function() refreshTeamDropdown(true); refreshTargetDropdown(true) end))
track(Teams.ChildRemoved:Connect(function() refreshTeamDropdown(true); refreshTargetDropdown(true) end))
track(Players.PlayerAdded:Connect(function() refreshTargetDropdown(true) end))
track(Players.PlayerRemoving:Connect(function() refreshTargetDropdown(true) end))

local teamConns = {}
local function hookTeamChange(plr)
	if teamConns[plr] then teamConns[plr]:Disconnect() end
	teamConns[plr] = plr:GetPropertyChangedSignal("Team"):Connect(function()
		if Fluent.Unloaded or state.terminated then return end
		refreshTargetDropdown(true)
	end)
end
for _, p in ipairs(Players:GetPlayers()) do hookTeamChange(p) end
track(Players.PlayerAdded:Connect(hookTeamChange))
track(Players.PlayerRemoving:Connect(function(plr)
	if teamConns[plr] then teamConns[plr]:Disconnect(); teamConns[plr] = nil end
end))

TpSec:AddButton({
	Title = "Teleport",
	Callback = function()
		local targetName = Fluent.Options.TPPlayer and Fluent.Options.TPPlayer.Value
		if type(targetName) ~= "string" then return end
		local target = Players:FindFirstChild(targetName)
		if not target then return end
		if not playerMatchesTeam(target, state.targetTeamFilter) then return end
		local theirRoot = getRootOf(target)
		if not theirRoot then return end
		getRoot().CFrame = theirRoot.CFrame * CFrame.new(0, 0, 3)
		maybeEquipAfterAction()
	end
})

-- Follow UI
FollowSec:AddToggle("FollowToggle", {
	Title = "Follow Target",
	Default = false,
	Callback = function(on)
		state.followEnabled = on
		if not on then state.followPaused = false end
	end
})
FollowSec:AddSlider("FollowBack", { Title = "Offset Back", Default = 4, Min = 0, Max = 25, Rounding = 0, Callback = function(v) state.followOffsetBack = v end })
FollowSec:AddSlider("FollowUp", { Title = "Offset Up", Default = 0, Min = -10, Max = 25, Rounding = 0, Callback = function(v) state.followOffsetUp = v end })
FollowSec:AddSlider("FollowSmooth", { Title = "Smoothness", Description = "Higher is more smooth and more detectable. Lower is less smooth and less detectable.", Default = 12, Min = 1, Max = 25, Rounding = 0, Callback = function(v) state.followSmoothness = v end })
FollowSec:AddSlider("FollowRate", { Title = "Update Rate", Default = 0.01, Min = 0.01, Max = 1, Rounding = 2, Callback = function(v) state.followUpdateRate = v end })

FollowSec:AddToggle("EquipOnTPFollow", {
	Title = "Equip Selected Weapon on TP",
	Description = "Uses the Player tab's weapon dropdown selection.",
	Default = false,
	Callback = function(on) state.equipOnFollowOrTP = on end
})

FollowSec:AddButton({
	Title = "Stop Follow",
	Callback = function()
		state.followEnabled = false
		state.followPaused = false
		if Fluent.Options.FollowToggle then Fluent.Options.FollowToggle:SetValue(false) end
	end
})

-- Auto-next on TARGET death
local followDiedConn
local function disconnectFollowDied()
	if followDiedConn then followDiedConn:Disconnect(); followDiedConn = nil end
end

local function switchToNextTarget()
	local currentName = Fluent.Options.TPPlayer and Fluent.Options.TPPlayer.Value
	local nextName = pickNextName(currentName)
	if not nextName then
		state.followEnabled = false
		state.followPaused = false
		if Fluent.Options.FollowToggle then Fluent.Options.FollowToggle:SetValue(false) end
		disconnectFollowDied()
		return
	end
	setTargetDropdown(nextName)
	disconnectFollowDied()

	local nextPlr = Players:FindFirstChild(nextName)
	if nextPlr then
		local hum = getHumanoidOf(nextPlr)
		if hum then
			followDiedConn = hum.Died:Connect(function()
				if state.followEnabled then switchToNextTarget() end
			end)
		end
	end
end

local function bindDeathListenerForCurrentTarget()
	disconnectFollowDied()
	if not state.followEnabled then return end
	if not Fluent.Options.TPPlayer then return end

	local name = Fluent.Options.TPPlayer.Value
	local plr = Players:FindFirstChild(name)
	if not plr or plr == LocalPlayer then switchToNextTarget(); return end
	if not playerMatchesTeam(plr, state.targetTeamFilter) then switchToNextTarget(); return end

	local hum = getHumanoidOf(plr)
	if not hum then switchToNextTarget(); return end

	followDiedConn = hum.Died:Connect(function()
		if state.followEnabled then switchToNextTarget() end
	end)
end

TpDropdown:OnChanged(function()
	if state.followEnabled then bindDeathListenerForCurrentTarget() end
end)

-- Follow loop (smooth lerp)
local followAcc = 0
local followEquippedThisSession = false

track(RunService.RenderStepped:Connect(function(dt)
	if Fluent.Unloaded or state.terminated then return end

	if not state.followEnabled then
		followEquippedThisSession = false
		if followDiedConn then disconnectFollowDied() end
		return
	end
	if state.followPaused then return end

	if not followDiedConn then bindDeathListenerForCurrentTarget() end

	followAcc += dt
	if followAcc < state.followUpdateRate then return end
	followAcc = 0

	local targetName = Fluent.Options.TPPlayer and Fluent.Options.TPPlayer.Value
	if type(targetName) ~= "string" then return end

	local target = Players:FindFirstChild(targetName)
	if not target or target == LocalPlayer then switchToNextTarget(); return end
	if not playerMatchesTeam(target, state.targetTeamFilter) then switchToNextTarget(); return end

	local theirRoot = getRootOf(target)
	if not theirRoot then switchToNextTarget(); return end

	local myRoot
	pcall(function() myRoot = getRoot() end)
	if not myRoot then return end

	if state.equipOnFollowOrTP and not followEquippedThisSession then
		followEquippedThisSession = true
		maybeEquipAfterAction()
	end

	local desired = theirRoot.CFrame * CFrame.new(0, state.followOffsetUp, -state.followOffsetBack)
	local alpha = 1 - math.exp(-state.followSmoothness * dt)
	myRoot.CFrame = myRoot.CFrame:Lerp(desired, alpha)
end))

-- =========================================================
-- Waypoints (save + export/import code for cross-server use)
-- =========================================================
local SavedDropdown = SavedSec:AddDropdown("SavedPos", { Title = "Waypoints", Values = {}, Multi = false })
SavedSec:AddInput("SaveName", { Title = "Waypoint Name", Default = "", Placeholder = "Spawn / Shop / etc", Callback = function() end })

local function refreshSavedDropdown()
	local values = {}
	for _, item in ipairs(state.savedPositions) do table.insert(values, item.Name) end
	SavedDropdown:SetValues(values)
end

SavedSec:AddButton({
	Title = "Save Current Position",
	Callback = function()
		local name = Fluent.Options.SaveName and Fluent.Options.SaveName.Value
		if type(name) ~= "string" or name:gsub("%s+", "") == "" then return end
		table.insert(state.savedPositions, { Name = name, CFrame = getRoot().CFrame })
		refreshSavedDropdown()
	end
})

SavedSec:AddButton({
	Title = "Teleport to Waypoint",
	Callback = function()
		local pick = Fluent.Options.SavedPos and Fluent.Options.SavedPos.Value
		for _, item in ipairs(state.savedPositions) do
			if item.Name == pick then
				getRoot().CFrame = item.CFrame
				return
			end
		end
	end
})

SavedSec:AddButton({
	Title = "Delete Selected Waypoint",
	Callback = function()
		local pick = Fluent.Options.SavedPos and Fluent.Options.SavedPos.Value
		if type(pick) ~= "string" then return end
		for i = #state.savedPositions, 1, -1 do
			if state.savedPositions[i].Name == pick then
				table.remove(state.savedPositions, i)
				break
			end
		end
		refreshSavedDropdown()
	end
})

SavedSec:AddButton({ Title = "Clear All Waypoints", Callback = function() state.savedPositions = {}; refreshSavedDropdown() end })

local function serializeWaypoints()
	local out = { placeId = game.PlaceId, waypoints = {} }
	for _, w in ipairs(state.savedPositions) do
		table.insert(out.waypoints, {
			name = w.Name,
			cf = { w.CFrame:GetComponents() } -- 12 numbers
		})
	end
	return HttpService:JSONEncode(out)
end

local function deserializeWaypoints(json)
	local ok, data = pcall(function() return HttpService:JSONDecode(json) end)
	if not ok or type(data) ~= "table" then return false, "Invalid JSON" end
	if data.placeId ~= game.PlaceId then
		return false, "Waypoint code is for a different placeId"
	end
	if type(data.waypoints) ~= "table" then
		return false, "Missing waypoints"
	end

	local newList = {}
	for _, it in ipairs(data.waypoints) do
		if type(it) == "table" and type(it.name) == "string" and type(it.cf) == "table" and #it.cf >= 12 then
			local c = it.cf
			local cf = CFrame.new(c[1],c[2],c[3], c[4],c[5],c[6], c[7],c[8],c[9], c[10],c[11],c[12])
			table.insert(newList, { Name = it.name, CFrame = cf })
		end
	end
	state.savedPositions = newList
	refreshSavedDropdown()
	return true
end

SavedSec:AddInput("WaypointCode", {
	Title = "Waypoint Code",
	Description = "Export/Import so waypoints can be reused in different servers.",
	Default = "",
	Placeholder = "Paste waypoint code here...",
	Finished = false,
	Callback = function() end
})

SavedSec:AddButton({
	Title = "Export Waypoints",
	Callback = function()
		local code = serializeWaypoints()
		if Fluent.Options.WaypointCode then
			Fluent.Options.WaypointCode:SetValue(code)
		end
		if typeof(setclipboard) == "function" then
			pcall(function() setclipboard(code) end)
			Fluent:Notify({ Title = "Waypoints", Content = "Exported and copied to clipboard", Duration = 3 })
		else
			Fluent:Notify({ Title = "Waypoints", Content = "Exported you must copy the code from the input box.", Duration = 4 })
		end
	end
})

SavedSec:AddButton({
	Title = "Import Waypoints",
	Callback = function()
		local code = Fluent.Options.WaypointCode and Fluent.Options.WaypointCode.Value
		if type(code) ~= "string" or #code < 5 then return end
		local ok, err = deserializeWaypoints(code)
		if ok then
			Fluent:Notify({ Title = "Waypoints", Content = "Imported successfully.", Duration = 3 })
		else
			Fluent:Notify({ Title = "Waypoints", Content = "Import failed: " .. tostring(err), Duration = 5 })
		end
	end
})

-- =========================================================
-- Visual tab: Fullbright + Freecam
-- =========================================================
local function setFullbright(on)
	if on then
		if not state.storedLighting then
			state.storedLighting = {
				Brightness = Lighting.Brightness,
				Ambient = Lighting.Ambient,
				OutdoorAmbient = Lighting.OutdoorAmbient,
				ClockTime = Lighting.ClockTime,
				FogEnd = Lighting.FogEnd,
			}
		end
		Lighting.Brightness = 3
		Lighting.Ambient = Color3.fromRGB(255, 255, 255)
		Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
		Lighting.ClockTime = 14
		Lighting.FogEnd = 1e9
	else
		if state.storedLighting then
			for k, v in pairs(state.storedLighting) do Lighting[k] = v end
		end
	end
end

VisualSec:AddToggle("Fullbright", { Title = "Fullbright", Default = false, Callback = function(on) setFullbright(on) end })

-- Freecam
local freecamConn
local freecamPos
local freecamRot = Vector2.zero
local oldCam = { Type=nil, Subject=nil, CFrame=nil }

local function stopFreecam()
	state.freecamEnabled = false
	if freecamConn then freecamConn:Disconnect(); freecamConn = nil end
	UIS.MouseBehavior = Enum.MouseBehavior.Default

	if oldCam.Type then Camera.CameraType = oldCam.Type end
	if oldCam.Subject then Camera.CameraSubject = oldCam.Subject end
	if oldCam.CFrame then Camera.CFrame = oldCam.CFrame end
end

local function startFreecam()
	stopFreecam()
	state.freecamEnabled = true

	oldCam.Type = Camera.CameraType
	oldCam.Subject = Camera.CameraSubject
	oldCam.CFrame = Camera.CFrame

	freecamPos = Camera.CFrame.Position
	freecamRot = Vector2.zero

	Camera.CameraType = Enum.CameraType.Scriptable
	UIS.MouseBehavior = Enum.MouseBehavior.LockCenter

	freecamConn = RunService.RenderStepped:Connect(function(dt)
		if Fluent.Unloaded or state.terminated then return end
		if not state.freecamEnabled then return end

		local speed = state.freecamSpeed
		if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then speed *= state.freecamFastMult end

		local forward = 0
		local right = 0
		local up = 0
		if UIS:IsKeyDown(Enum.KeyCode.W) then forward += 1 end
		if UIS:IsKeyDown(Enum.KeyCode.S) then forward -= 1 end
		if UIS:IsKeyDown(Enum.KeyCode.D) then right += 1 end
		if UIS:IsKeyDown(Enum.KeyCode.A) then right -= 1 end
		if UIS:IsKeyDown(Enum.KeyCode.E) then up += 1 end
		if UIS:IsKeyDown(Enum.KeyCode.Q) then up -= 1 end

		local md = UIS:GetMouseDelta()
		freecamRot += Vector2.new(-md.Y, -md.X) * 0.0025

		local rotCF = CFrame.fromOrientation(freecamRot.X, freecamRot.Y, 0)
		local basis = CFrame.new(freecamPos) * rotCF

		local move = Vector3.new(right, up, forward)
		if move.Magnitude > 0 then
			move = move.Unit * speed * dt
		end

		freecamPos += (basis.RightVector * move.X) + (Vector3.new(0,1,0) * move.Y) + (basis.LookVector * move.Z)
		Camera.CFrame = CFrame.new(freecamPos) * rotCF
	end)

	table.insert(connections, freecamConn)
end

FreecamSec:AddToggle("Freecam", {
	Title = "Freecam",
	Description = "Camera-only movement. Q/E up-down. Shift = faster.",
	Default = false,
	Callback = function(on) if on then startFreecam() else stopFreecam() end end
})

FreecamSec:AddSlider("FreecamSpeed", {
	Title = "Speed",
	Default = 48, Min = 10, Max = 250, Rounding = 0,
	Callback = function(v) state.freecamSpeed = v end
})

FreecamSec:AddSlider("FreecamFastMult", {
	Title = "Shift Multiplier",
	Default = 3, Min = 2, Max = 8, Rounding = 0,
	Callback = function(v) state.freecamFastMult = v end
})

FreecamSec:AddButton({
	Title = "Reset Camera",
	Callback = function()
		stopFreecam()
		if Fluent.Options.Freecam then Fluent.Options.Freecam:SetValue(false) end
	end
})

-- =========================================================
-- ESP + Tracers + Hitboxes
-- =========================================================
local espFolder = Instance.new("Folder")
espFolder.Name = "AdminESP"
espFolder.Parent = Workspace

local highlightsByPlayer = {}
local billboardsByPlayer = {}
local tracersByPlayer = {}
local espConn

local function ensureHighlight(plr)
	if highlightsByPlayer[plr] then return highlightsByPlayer[plr] end
	local h = Instance.new("Highlight")
	h.Name = "ESP_" .. plr.Name
	h.FillTransparency = 0.6
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Parent = espFolder
	highlightsByPlayer[plr] = h
	return h
end

local function ensureBillboard(plr)
	if billboardsByPlayer[plr] then return billboardsByPlayer[plr] end

	local bb = Instance.new("BillboardGui")
	bb.Name = "ESPLabel_" .. plr.Name
	bb.Size = UDim2.fromOffset(280, 54)
	bb.AlwaysOnTop = true
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.MaxDistance = state.espMaxDistance
	bb.Parent = espFolder

	local tl = Instance.new("TextLabel")
	tl.BackgroundTransparency = 1
	tl.Size = UDim2.fromScale(1, 1)
	tl.TextScaled = true
	tl.Font = Enum.Font.GothamSemibold
	tl.TextStrokeTransparency = 0.5
	tl.Text = ""
	tl.Parent = bb

	billboardsByPlayer[plr] = bb
	return bb
end

local function ensureTracer(plr)
	if tracersByPlayer[plr] then return tracersByPlayer[plr] end

	local beam = Instance.new("Beam")
	beam.Name = "Tracer_" .. plr.Name
	beam.Width0 = 0.08
	beam.Width1 = 0.08
	beam.FaceCamera = true
	beam.Parent = espFolder

	local a0 = Instance.new("Attachment")
	a0.Name = "TracerA0_" .. plr.Name
	a0.Parent = espFolder

	local a1 = Instance.new("Attachment")
	a1.Name = "TracerA1_" .. plr.Name
	a1.Parent = espFolder

	beam.Attachment0 = a0
	beam.Attachment1 = a1

	tracersByPlayer[plr] = { Beam = beam, A0 = a0, A1 = a1 }
	return tracersByPlayer[plr]
end

local function cleanupESPPlayer(plr)
	local h = highlightsByPlayer[plr]
	if h then h:Destroy(); highlightsByPlayer[plr] = nil end

	local bb = billboardsByPlayer[plr]
	if bb then bb:Destroy(); billboardsByPlayer[plr] = nil end

	local tr = tracersByPlayer[plr]
	if tr then
		if tr.Beam then tr.Beam:Destroy() end
		if tr.A0 then tr.A0:Destroy() end
		if tr.A1 then tr.A1:Destroy() end
		tracersByPlayer[plr] = nil
	end
end

local function shouldShowESP(plr, dist)
	if plr == LocalPlayer then return false end
	if state.espTeamCheck and plr.Team == LocalPlayer.Team then return false end
	if dist > state.espMaxDistance then return false end
	return true
end

local function stopESP()
	if espConn then espConn:Disconnect(); espConn = nil end
	for plr in pairs(highlightsByPlayer) do cleanupESPPlayer(plr) end
end

local function startESP()
	if espConn then espConn:Disconnect() end
	local acc = 0

	espConn = RunService.RenderStepped:Connect(function(dt)
		if Fluent.Unloaded or state.terminated then return end
		if not state.espEnabled then return end

		acc += dt
		if acc < state.espRefreshRate then return end
		acc = 0

		local localRoot = getRootOf(LocalPlayer)
		if not localRoot then return end

		for _, plr in ipairs(Players:GetPlayers()) do
			local root = getRootOf(plr)
			if not root then cleanupESPPlayer(plr) continue end

			local dist = (root.Position - localRoot.Position).Magnitude
			if not shouldShowESP(plr, dist) then cleanupESPPlayer(plr) continue end

			local h = ensureHighlight(plr)
			h.Adornee = plr.Character

			-- label
			if state.espShowNames or state.espShowDistance or state.espShowHealth or state.espShowTeam then
				local bb = ensureBillboard(plr)
				bb.Adornee = root
				bb.MaxDistance = state.espMaxDistance
				local tl = bb:FindFirstChildOfClass("TextLabel")
				if tl then
					local parts = {}
					if state.espShowNames then table.insert(parts, plr.Name) end
					if state.espShowTeam then
						local tname = (plr.Team and plr.Team.Name) or "NoTeam"
						table.insert(parts, "[" .. tname .. "]")
					end
					if state.espShowHealth then
						local hum = getHumanoidOf(plr)
						if hum then table.insert(parts, ("HP:%d"):format(math.floor(hum.Health + 0.5))) end
					end
					if state.espShowDistance then table.insert(parts, ("%.0fm"):format(dist)) end
					tl.Text = table.concat(parts, "  •  ")
				end
			else
				if billboardsByPlayer[plr] then billboardsByPlayer[plr]:Destroy(); billboardsByPlayer[plr] = nil end
			end

			-- tracers
			if state.espTracers then
				local tr = ensureTracer(plr)
				tr.A0.Parent = localRoot
				tr.A1.Parent = root
				tr.A0.WorldPosition = localRoot.Position
				tr.A1.WorldPosition = root.Position
				tr.Beam.Enabled = true
			else
				if tracersByPlayer[plr] then
					tracersByPlayer[plr].Beam.Enabled = false
				end
			end
		end
	end)

	table.insert(connections, espConn)
end

EspSec:AddToggle("ESPEnabled", {
	Title = "Enabled",
	Default = false,
	Callback = function(on)
		state.espEnabled = on
		if on then startESP() else stopESP() end
	end
})

EspSec:AddToggle("ESPNames", { Title = "Show Names", Default = true, Callback = function(on) state.espShowNames = on end })
EspSec:AddToggle("ESPTeam",  { Title = "Show Team", Default = true, Callback = function(on) state.espShowTeam = on end })
EspSec:AddToggle("ESPHealth",{ Title = "Show Health", Default = true, Callback = function(on) state.espShowHealth = on end })
EspSec:AddToggle("ESPDistance", { Title = "Show Distance", Default = true, Callback = function(on) state.espShowDistance = on end })
EspSec:AddToggle("ESPTeamCheck", { Title = "Team Check", Default = false, Callback = function(on) state.espTeamCheck = on end })

EspSec:AddToggle("ESPTracers", {
	Title = "Tracers",
	Description = "Draws a beam from you to each ESP player.",
	Default = false,
	Callback = function(on) state.espTracers = on end
})

EspSec:AddSlider("ESPMaxDistance", {
	Title = "Max Distance",
	Default = 1500, Min = 50, Max = 5000, Rounding = 0,
	Callback = function(v)
		state.espMaxDistance = v
		for _, bb in pairs(billboardsByPlayer) do bb.MaxDistance = v end
	end
})

EspSec:AddSlider("ESPRefresh", {
	Title = "Refresh (sec)",
	Default = 0.15, Min = 0.05, Max = 1, Rounding = 2,
	Callback = function(v) state.espRefreshRate = v end
})

EspSec:AddButton({
	Title = "Clear ESP Objects",
	Callback = function()
		stopESP()
		if state.espEnabled then startESP() end
	end
})

track(Players.PlayerRemoving:Connect(function(plr) cleanupESPPlayer(plr) end))
track(LocalPlayer.CharacterAdded:Connect(function()
	if state.espEnabled then stopESP(); startESP() end
end))

-- Hitbox expander (local-only)
local originalHitboxes = {} -- [plr] = {Size=Vector3, Trans=number}

local function applyHitbox(plr)
	if plr == LocalPlayer then return end
	local root = getRootOf(plr)
	if not root then return end

	if not originalHitboxes[plr] then
		originalHitboxes[plr] = { Size = root.Size, Transparency = root.Transparency }
	end

	root.Size = Vector3.new(state.hitboxSize, state.hitboxSize, state.hitboxSize)
	root.Transparency = state.hitboxTransparency
	root.CanCollide = false
end

local function restoreHitbox(plr)
	local root = getRootOf(plr)
	local saved = originalHitboxes[plr]
	if root and saved then
		root.Size = saved.Size
		root.Transparency = saved.Transparency
	end
	originalHitboxes[plr] = nil
end

local function refreshAllHitboxes()
	for _, plr in ipairs(Players:GetPlayers()) do
		if state.hitboxEnabled then applyHitbox(plr) else restoreHitbox(plr) end
	end
end

HitboxSec:AddToggle("HitboxEnabled", {
	Title = "Hitbox Toggle",
	Description = "Local-only HRP hitbox size change for visibility/testing.",
	Default = false,
	Callback = function(on)
		state.hitboxEnabled = on
		refreshAllHitboxes()
	end
})

HitboxSec:AddSlider("HitboxSize", {
	Title = "Hitbox Size",
	Default = 8, Min = 2, Max = 20, Rounding = 0,
	Callback = function(v)
		state.hitboxSize = v
		if state.hitboxEnabled then refreshAllHitboxes() end
	end
})

HitboxSec:AddSlider("HitboxTransparency", {
	Title = "Hitbox Transparency",
	Default = 0.6, Min = 0, Max = 1, Rounding = 2,
	Callback = function(v)
		state.hitboxTransparency = v
		if state.hitboxEnabled then refreshAllHitboxes() end
	end
})

track(Players.PlayerAdded:Connect(function(plr)
	track(plr.CharacterAdded:Connect(function()
		task.wait(0.25)
		if state.hitboxEnabled then applyHitbox(plr) end
	end))
end))

track(Players.PlayerRemoving:Connect(function(plr)
	restoreHitbox(plr)
end))

-- =========================================================
-- Utility tab: Serverhopping (no detection; will error if LocalScript)
-- =========================================================
local function fetchPublicServers(limit)
	limit = math.clamp(limit or 100, 10, 100)
	local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=2&limit=%d"):format(game.PlaceId, limit)
	local res = HttpService:GetAsync(url) -- will fail in normal LocalScript
	return HttpService:JSONDecode(res)
end

local function pickServer(data, mode)
	if type(data) ~= "table" or type(data.data) ~= "table" then return nil end

	local candidates = {}
	for _, s in ipairs(data.data) do
		if type(s) == "table" and s.id and s.playing and s.maxPlayers then
			if s.id ~= game.JobId and s.playing < s.maxPlayers then
				table.insert(candidates, s)
			end
		end
	end
	if #candidates == 0 then return nil end

	if mode == "least" then
		table.sort(candidates, function(a, b) return a.playing < b.playing end)
		return candidates[1]
	end

	return candidates[math.random(1, #candidates)]
end

local function serverhop(mode)
	local ok, dataOrErr = pcall(function()
		return fetchPublicServers(100)
	end)

	if not ok then
		Fluent:Notify({
			Title = "Serverhop Failed",
			Content = "HTTP not available here.\nError: " .. tostring(dataOrErr),
			Duration = 7
		})
		return
	end

	local server = pickServer(dataOrErr, mode)
	if not server then
		Fluent:Notify({ Title = "Serverhop", Content = "No suitable servers found.", Duration = 4 })
		return
	end

	local ok2, err2 = pcall(function()
		TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, Players.LocalPlayer)
	end)

	if not ok2 then
		Fluent:Notify({ Title = "Serverhop Failed", Content = "Teleport failed: " .. tostring(err2), Duration = 6 })
	end
end

ServerSec:AddParagraph({
	Title = "Serverhop",
	Content = "Attempts client HTTP. Works only in environments that support HttpService:GetAsync() on client."
})

ServerSec:AddButton({
	Title = "Rejoin Server",
	Callback = function()
		local ok, err = pcall(function()
			TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)
		end)
		if not ok then
			Fluent:Notify({ Title = "Rejoin Failed", Content = tostring(err), Duration = 5 })
		end
	end
})

ServerSec:AddButton({
	Title = "Server Hop (Random)",
	Callback = function() serverhop("random") end
})

ServerSec:AddButton({
	Title = "Server Hop (Least Players)",
	Callback = function() serverhop("least") end
})


-- =========================================================
-- Terminate: reset everything + close UI
-- =========================================================
local function terminateAll()
	if state.terminated then return end
	state.terminated = true

	-- stop features
	state.noclip = false
	state.infiniteJump = false
	state.fly = false
	state.followEnabled = false
	state.followPaused = false
	state.espEnabled = false
	state.espTracers = false
	state.hitboxEnabled = false
	state.altSpeedEnabled = false
	stopInfHealth()
	stopFly()
	stopFreecam()
	setFullbright(false)

	-- restore hitboxes
	for _, plr in ipairs(Players:GetPlayers()) do
		restoreHitbox(plr)
	end

	-- stop esp
	pcall(stopESP)

	-- destroy ESP folder
	pcall(function()
		if espFolder then espFolder:Destroy() end
	end)

	-- disconnect everything we tracked
	for _, c in ipairs(connections) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(connections)

	-- hard destroy Fluent
	pcall(function()
		Fluent:Destroy()
	end)
end

TerminateSec:AddButton({
	Title = "Terminate",
	Description = "Resets all toggles/features and destroys the UI.",
	Callback = function()
		Window:Dialog({
			Title = "Terminate",
			Content = "This will reset everything and close the UI. Continue?",
			Buttons = {
				{ Title = "Confirm", Callback = function() terminateAll() end },
				{ Title = "Cancel", Callback = function() end }
			}
		})
	end
})

-- =========================================================
-- Settings tab (InterfaceManager + SaveManager ONLY)
-- =========================================================
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)
SaveManager:LoadAutoloadConfig()

-- Initial refresh
task.defer(function()
	refreshTeamDropdown(true)
	refreshTargetDropdown(true)
	refreshSavedDropdown()
end)

Window:SelectTab(1)
