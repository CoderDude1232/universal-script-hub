--========================
-- Imports
--========================
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

--========================
-- Services
--========================
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

--========================
-- Helpers
--========================

local function setRFLabel(labelObj, text)
	if not labelObj then return end
	text = tostring(text or "")

	-- Most Rayfield builds
	if type(labelObj) == "table" and type(labelObj.Set) == "function" then
		pcall(function() labelObj:Set(text) end)
		return
	end

	-- Some forks expose Update/Refresh
	if type(labelObj) == "table" and type(labelObj.Update) == "function" then
		pcall(function() labelObj:Update(text) end)
		return
	end
	if type(labelObj) == "table" and type(labelObj.Refresh) == "function" then
		pcall(function() labelObj:Refresh(text) end)
		return
	end

	-- Rare case where it’s an actual Instance
	if typeof(labelObj) == "Instance" and labelObj:IsA("TextLabel") then
		labelObj.Text = text
	end
end

-- Ensure state exists early (prevents nil indexing anywhere)
local state = _G.__ADMIN_STATE or {}
_G.__ADMIN_STATE = state

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

local connections = {}
local function track(conn)
	table.insert(connections, conn)
	return conn
end

-- Rayfield dropdown method compatibility
local function dropdownSetValues(dd, values)
	if not dd or type(values) ~= "table" then return end
	pcall(function()
		if dd.Refresh then dd:Refresh(values) return end
		if dd.Update then dd:Update(values) return end
		if dd.SetOptions then dd:SetOptions(values) return end
		if dd.Set then dd:Set(values) return end
		if dd.SetValues then dd:SetValues(values) return end
	end)
end

local function dropdownSetCurrent(dd, val)
	if not dd then return end
	pcall(function()
		if dd.Set then dd:Set(val) return end
		if dd.SetCurrentOption then dd:SetCurrentOption(val) return end
		if dd.SetValue then dd:SetValue(val) return end
	end)
end

-- Fluent-like section headers for Rayfield
local function Header(tab, title)
	tab:CreateSection(tostring(title or ""))
end

local function notify(title, message, duration, force)
	if state and state.disableNotifications and not force then return end
	Rayfield:Notify({
		Title = title or "Notice",
		Content = message or "",
		Duration = duration or 3,
		Image = "info",
	})
end

local function getRayfieldGui()
	local cg = game:GetService("CoreGui")
	for _, v in ipairs(cg:GetChildren()) do
		if v:IsA("ScreenGui") and (v.Name:lower():find("rayfield") or v:FindFirstChild("Rayfield")) then
			return v
		end
	end
	return nil
end

local function setRayfieldScale(scale)
	scale = math.clamp(tonumber(scale) or 1, 0.7, 1.5)
	local gui = getRayfieldGui()
	if not gui then return false end

	-- Try to apply UIScale to first root frame we can find
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("Frame") then
			local s = d:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
			s.Scale = scale
			s.Parent = d
			state.uiScale = scale
			return true
		end
	end
	return false
end

local function findSpawnCFrame()
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")

	-- Prefer SpawnLocation
	local spawns = {}
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("SpawnLocation") then
			table.insert(spawns, inst)
		end
	end
	if #spawns > 0 then
		-- choose nearest spawn to you if possible
		if hrp then
			table.sort(spawns, function(a,b)
				return (a.Position-hrp.Position).Magnitude < (b.Position-hrp.Position).Magnitude
			end)
		end
		return spawns[1].CFrame + Vector3.new(0, 5, 0)
	end

	-- Fallback: "Spawn" parts commonly used
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("BasePart") and inst.Name:lower():find("spawn") then
			return inst.CFrame + Vector3.new(0, 5, 0)
		end
	end

	return nil
end

local function getMouseHitCFrame(maxDist)
	maxDist = maxDist or 5000
	local mouse = LocalPlayer:GetMouse()
	local origin = Camera.CFrame.Position
	local dir = (mouse.Hit.Position - origin)
	if dir.Magnitude < 1 then dir = Camera.CFrame.LookVector * maxDist end
	dir = dir.Unit * maxDist

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.FilterDescendantsInstances = { LocalPlayer.Character }

	local res = Workspace:Raycast(origin, dir, params)
	if res then
		return CFrame.new(res.Position + Vector3.new(0, 3, 0))
	end
	return CFrame.new(origin + dir)
end

local DEFAULTS = {
	WalkSpeed = 16,
	JumpPower = 50,
	FOV = 70,
	HipHeight = 0,
}

local function applyPlayerDefaults()
	pcall(function()
		local hum = getHumanoid()
		hum.WalkSpeed = DEFAULTS.WalkSpeed
		hum.JumpPower = DEFAULTS.JumpPower
		hum.HipHeight = DEFAULTS.HipHeight
		Camera.FieldOfView = DEFAULTS.FOV
	end)
end

track(LocalPlayer.CharacterAdded:Connect(function(char)
	task.defer(function()
		if state.terminated then return end
		-- Apply hipheight override if enabled
		if state.hipHeightEnabled then
			pcall(function()
				local hum = getHumanoid()
				hum.HipHeight = state.hipHeight
			end)
		end

		-- Auto reset on death: bind Died each spawn
		if state.autoResetOnDeath then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				track(hum.Died:Connect(function()
					-- Wait for respawn, then reset
					task.delay(0.6, function()
						if state.terminated then return end
						applyPlayerDefaults()
						-- re-apply hipheight override after reset
						if state.hipHeightEnabled then
							pcall(function() getHumanoid().HipHeight = state.hipHeight end)
						end
					end)
				end))
			end
		end
	end)
end))

--========================
-- Window
--========================

local MINIMIZE_KEY = Enum.KeyCode.RightShift
local AXIOM_PREMIUM = (_G.AXIOM_PREMIUM == true)
local VERSION = "v1.3"

local Window = Rayfield:CreateWindow({
	Name = "Axiom " .. VERSION,
	LoadingTitle = "Axiom",
	LoadingSubtitle = "Universal Script",
	ConfigurationSaving = {
		Enabled = true,
		FolderName = "AxiomUniversal",
		FileName = "Axiom"
	},
	KeySystem = false,
	DisableRayfieldPrompts = true,
   DisableBuildWarnings = true
})

track(UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode ~= MINIMIZE_KEY then return end
	pcall(function() Rayfield:Toggle() end)
	pcall(function() Rayfield:ToggleUI() end)
	pcall(function() Window:Toggle() end)
end))

local function premium()
	return AXIOM_PREMIUM
end

--========================
-- Tabs
--========================
local Tabs = {
	Credits  = Window:CreateTab("Credits",  10723415903),
	Player   = Window:CreateTab("Player",   10747373176),
	Movement = Window:CreateTab("Movement", 10747382750),
	Teleport = Window:CreateTab("Teleport", 10734886202),
	Visual   = Window:CreateTab("Visual",   10723415040),
	ESP      = Window:CreateTab("ESP",      10723346959),
	Utility  = Window:CreateTab("Utility",  10747383470),
	Settings = Window:CreateTab("Settings", 10734950309)
}

--========================
-- State
--========================
local prev = state or {}

state = {
	-- Player
	hipHeight = prev.hipHeight or 0,
	hipHeightEnabled = (prev.hipHeightEnabled ~= false) and prev.hipHeightEnabled or false,
	autoResetOnDeath = prev.autoResetOnDeath or false,

	-- Movement / Teleport
	spiderWalk = prev.spiderWalk or false,
	tpToGroundOffset = prev.tpToGroundOffset or 3,
	unstuckEnabled = prev.unstuckEnabled or false,

	-- Visual
	noCamShake = prev.noCamShake or false,
	guiHidden = prev.guiHidden or false,

	-- Utility
	rejoinOnKick = prev.rejoinOnKick or false,
	showPerfPanel = (prev.showPerfPanel ~= false) and true or prev.showPerfPanel,
	antiIdlePro = prev.antiIdlePro or false,

	-- movement
	noclip = prev.noclip or false,
	infiniteJump = prev.infiniteJump or false,
	fly = prev.fly or false,
	flySpeed = prev.flySpeed or 60,

	-- lighting
	storedLighting = prev.storedLighting,

	-- waypoints
	savedPositions = prev.savedPositions or {},

	-- ESP
	espEnabled = prev.espEnabled or false,
	espShowNames = (prev.espShowNames ~= false),
	espShowDistance = (prev.espShowDistance ~= false),
	espShowHealth = (prev.espShowHealth ~= false),
	espShowTeam = (prev.espShowTeam ~= false),
	espTeamCheck = prev.espTeamCheck or false,
	espMaxDistance = prev.espMaxDistance or 1500,
	espRefreshRate = prev.espRefreshRate or 0.15,
	espTracers = prev.espTracers or false,

	-- hitboxes
	hitboxEnabled = prev.hitboxEnabled or false,
	hitboxSize = prev.hitboxSize or 8,
	hitboxTransparency = prev.hitboxTransparency or 0.6,

	-- follow
	followEnabled = prev.followEnabled or false,
	followPaused = prev.followPaused or false,
	followOffsetBack = prev.followOffsetBack or 4,
	followOffsetUp = prev.followOffsetUp or 0,
	followUpdateRate = prev.followUpdateRate or 0.01,
	followSmoothness = prev.followSmoothness or 12,
	equipOnFollowOrTP = prev.equipOnFollowOrTP or false,

	-- predictive follow
	followPredictive = prev.followPredictive or false,
	followPredictAhead = prev.followPredictAhead or 0.25,

	-- health
	infHealth = prev.infHealth or false,
	infHealthTarget = prev.infHealthTarget or 100,
	infHealthRate = prev.infHealthRate or 0.1,

	-- weapons
	autoEquip = prev.autoEquip or false,

	-- team filter
	targetTeamFilter = prev.targetTeamFilter or "All",

	-- alt speed
	altSpeedEnabled = prev.altSpeedEnabled or false,
	altSpeedBoost = prev.altSpeedBoost or 0,
	altSpeedMaxVel = prev.altSpeedMaxVel or 120,

	-- freecam
	freecamEnabled = prev.freecamEnabled or false,
	freecamSpeed = prev.freecamSpeed or 48,
	freecamFastMult = prev.freecamFastMult or 3,

	-- terminate
	terminated = prev.terminated or false,

	-- notifications
	disableNotifications = prev.disableNotifications or false,

	-- UI
	uiScale = prev.uiScale or 1,
	uiTheme = prev.uiTheme or "Default",

	-- player info
	infoSelectedPlayer = prev.infoSelectedPlayer or "",
	infoAutoRefresh = (prev.infoAutoRefresh ~= false),
	infoRefreshRate = prev.infoRefreshRate or 0.5,

	-- AFK/session
	antiAfk = prev.antiAfk or false,
	sessionStart = prev.sessionStart or os.clock(),

	-- bunnyhop
	bunnyHop = prev.bunnyHop or false,

	-- teleport extras
	tpCursorEnabled = (prev.tpCursorEnabled ~= false),
	tpCircleEnabled = prev.tpCircleEnabled or false,
	tpCircleRadius = prev.tpCircleRadius or 8,
	tpCircleSpeed = prev.tpCircleSpeed or 1.5,

	-- visuals
	removeEffects = prev.removeEffects or false,
	nightVision = prev.nightVision or false,
	noWeather = prev.noWeather or false,
	noParticles = prev.noParticles or false,

	-- esp modes
	espMode = prev.espMode or "Highlight",
	espTarget = prev.espTarget or "",
	espShowBar = (prev.espShowBar ~= false),

	-- perf
	fpsBoost = prev.fpsBoost or false,

	-- cooldown
	hopCooldown = prev.hopCooldown or 8,
}

local ui = {
	WeaponTool = nil,
	TeamFilter = "All",
	TPPlayer = nil,
	SaveName = "",
	SavedPos = nil,
	WaypointCode = "",
}

--========================
-- CREDITS TAB
--========================

Header(Tabs.Credits, "Credits")

Tabs.Credits:CreateParagraph({
	Title = "Credits",
	Content =
	"- Name: Axiom\n" ..
	"- UI: Rayfield\n" ..
	"- Creator: @etho_gg\n" ..
	"- Version: " .. VERSION .. "\n" ..
	"- Edition: " .. (premium() and "Premium" or "Standard")
})

Header(Tabs.Credits, "Changelog")

Tabs.Credits:CreateParagraph({
	Title = "v1.2",
	Content =
	"- Moved all Player + Server + Performance info into Utility\n" ..
	"- Removed duplicate info panels and singular anti idle"
})

Tabs.Credits:CreateParagraph({
	Title = "v1.1",
	Content =
	"- HipHeight\n" ..
	"- Auto reset on death\n" ..
	"- Spider / wall walk\n" ..
	"- Teleport to ground\n" ..
	"- Unstuck teleport\n" ..
	"- No camera shake\n" ..
	"- GUI toggle\n" ..
	"- Restore visuals\n" ..
	"- Rejoin on kick\n" ..
	"- Ping / FPS / memory usage\n" ..
	"- Improved anti-idle\n" ..
	"- ESP stability fixes"
})

Tabs.Credits:CreateParagraph({
	Title = "v1.0",
	Content =
	"- Initial Axiom release\n" ..
	"- Core features"
})

--========================
-- Weapon Equipper
--========================
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
	local name = ui.WeaponTool
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

local function refreshWeaponDropdown(tryKeep)
	local values = getToolNames()
	if weaponDropdown then dropdownSetValues(weaponDropdown, values) end

	if tryKeep and ui.WeaponTool and table.find(values, ui.WeaponTool) then
		-- keep
	elseif #values > 0 then
		ui.WeaponTool = values[1]
		dropdownSetCurrent(weaponDropdown, ui.WeaponTool)
	else
		ui.WeaponTool = nil
	end
end

--========================
-- Alt Speed (velocity assist)
--========================
local function getMoveDirection()
	local char = LocalPlayer.Character
	if not char then return Vector3.zero end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return Vector3.zero end
	return hum.MoveDirection or Vector3.zero
end

track(RunService.Heartbeat:Connect(function()
	if state.terminated then return end
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
	if boosted.Magnitude > state.altSpeedMaxVel then
		boosted = boosted.Unit * state.altSpeedMaxVel
	end

	root.AssemblyLinearVelocity = Vector3.new(boosted.X, vel.Y, boosted.Z)
end))

--========================
-- Fly
--========================
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
		if state.terminated then return end
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

	table.insert(connections, flyConn)
end

--========================
-- Infinite health loop (client)
--========================
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
		while state.infHealth and (infHealthTaskId == myId) and not state.terminated do
			pcall(function()
				local hum = getHumanoid()
				if hum.MaxHealth < state.infHealthTarget then hum.MaxHealth = state.infHealthTarget end
				hum.Health = state.infHealthTarget
			end)
			task.wait(state.infHealthRate)
		end
	end)
end

-- Pause follow on YOUR death
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
task.defer(bindLocalDeath)

--========================
-- PLAYER TAB (Fluent-style "sections")
--========================
Header(Tabs.Player, "Stats")
Tabs.Player:CreateSlider({
	Name = "WalkSpeed",
	Range = {0, 200}, -- reduced (was 250)
	Increment = 1,
	Suffix = " WS",
	CurrentValue = 16,
	Flag = "WalkSpeed",
	Callback = function(v) pcall(function() getHumanoid().WalkSpeed = v end) end
})
Tabs.Player:CreateSlider({
	Name = "JumpPower",
	Range = {0, 200}, -- reduced (was 250)
	Increment = 1,
	Suffix = " JP",
	CurrentValue = 50,
	Flag = "JumpPower",
	Callback = function(v) pcall(function() getHumanoid().JumpPower = v end) end
})

Header(Tabs.Player, "Velocity Speed")
Tabs.Player:CreateToggle({
	Name = "Velocity Speed",
	CurrentValue = false,
	Flag = "AltSpeedEnabled",
	Callback = function(on) state.altSpeedEnabled = on end
})
Tabs.Player:CreateSlider({
	Name = "Boost Amount",
	Range = {0, 60}, -- reduced (was 150)
	Increment = 1,
	Suffix = "",
	CurrentValue = 6,
	Flag = "AltSpeedBoost",
	Callback = function(v) state.altSpeedBoost = v end
})
Tabs.Player:CreateSlider({
	Name = "Max Horizontal Velocity",
	Range = {20, 160}, -- reduced (was 300)
	Increment = 1,
	Suffix = "",
	CurrentValue = 70,
	Flag = "AltSpeedMaxVel",
	Callback = function(v) state.altSpeedMaxVel = v end
})

Header(Tabs.Player, "Hip Height")

Tabs.Player:CreateToggle({
	Name = "HipHeight Override",
	CurrentValue = state.hipHeightEnabled,
	Flag = "HipHeightEnabled",
	Callback = function(on)
		state.hipHeightEnabled = on and true or false
		pcall(function()
			if state.hipHeightEnabled then
				getHumanoid().HipHeight = state.hipHeight
			end
		end)
	end
})

Tabs.Player:CreateSlider({
	Name = "HipHeight",
	Range = {-2, 10},
	Increment = 0.1,
	Suffix = "",
	CurrentValue = state.hipHeight,
	Flag = "HipHeight",
	Callback = function(v)
		state.hipHeight = v
		if state.hipHeightEnabled then
			pcall(function() getHumanoid().HipHeight = v end)
		end
	end
})

Header(Tabs.Player, "Auto Reset")

Tabs.Player:CreateToggle({
	Name = "Auto Reset on Death",
	CurrentValue = state.autoResetOnDeath,
	Flag = "AutoResetOnDeath",
	Callback = function(on)
		state.autoResetOnDeath = on and true or false
	end
})

Header(Tabs.Player, "Weapons")
weaponDropdown = Tabs.Player:CreateDropdown({
	Name = "Tool",
	Options = getToolNames(),
	CurrentOption = {},
	MultipleOptions = false,
	Flag = "WeaponTool",
	Callback = function(opt)
		if type(opt) == "table" then opt = opt[1] end
		ui.WeaponTool = (type(opt) == "string" and opt) or ui.WeaponTool
	end
})
Tabs.Player:CreateButton({ Name = "Equip Selected", Callback = function() equipSelectedTool() end })
Tabs.Player:CreateToggle({
	Name = "Auto Equip Selected",
	CurrentValue = false,
	Flag = "AutoEquip",
	Callback = function(on)
		state.autoEquip = on
		if on then equipSelectedTool() end
	end
})
Tabs.Player:CreateButton({ Name = "Refresh Tool List", Callback = function() refreshWeaponDropdown(true) end })

Header(Tabs.Player, "Health")
Tabs.Player:CreateToggle({
	Name = "Client Infinite Health",
	CurrentValue = false,
	Flag = "InfHealth",
	Callback = function(on) if on then startInfHealth() else stopInfHealth() end end
})
Tabs.Player:CreateSlider({
	Name = "Health Target",
	Range = {1, 250}, -- reduced (was 500)
	Increment = 1,
	Suffix = "",
	CurrentValue = 100,
	Flag = "InfHealthTarget",
	Callback = function(v) state.infHealthTarget = v end
})
Tabs.Player:CreateSlider({
	Name = "Loop Rate (sec)",
	Range = {0.05, 1},
	Increment = 0.01,
	Suffix = "s",
	CurrentValue = 0.10,
	Flag = "InfHealthRate",
	Callback = function(v) state.infHealthRate = v end
})

Header(Tabs.Player, "Camera")
Tabs.Player:CreateSlider({
	Name = "FOV",
	Range = {30, 120}, -- keep (useful range)
	Increment = 1,
	Suffix = "",
	CurrentValue = 70,
	Flag = "FOV",
	Callback = function(v) Camera.FieldOfView = v end
})

Tabs.Player:CreateButton({
	Name = "Reset Player",
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
		notify("Reset", "Player reset.", 2)
	end
})

-- Tool listeners
track(getBackpack().ChildAdded:Connect(function(c)
	if c:IsA("Tool") then
		refreshWeaponDropdown(true)
		if state.autoEquip then task.defer(equipSelectedTool) end
	end
end))
track(getBackpack().ChildRemoved:Connect(function(c)
	if c:IsA("Tool") then task.defer(function() refreshWeaponDropdown(true) end) end
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

--========================
-- MOVEMENT TAB
--========================
local spiderConn
local spiderUp = Vector3.new(0, 1, 0)

local function stopSpider()
	if spiderConn then spiderConn:Disconnect(); spiderConn = nil end
	pcall(function()
		local hum = getHumanoid()
		hum.PlatformStand = false
	end)
end

local function startSpider()
	stopSpider()
	spiderConn = RunService.RenderStepped:Connect(function(dt)
		if state.terminated then return end
		if not state.spiderWalk then return end

		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum or hum.Health <= 0 then return end

		-- Raycast forward to find a wall
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Blacklist
		params.FilterDescendantsInstances = { char }

		local origin = hrp.Position
		local forward = hrp.CFrame.LookVector * 4
		local hit = Workspace:Raycast(origin, forward, params)

		if hit and hit.Normal then
			-- Align "up" to wall normal (simple spider)
			local n = hit.Normal.Unit
			-- Build a basis using camera right to keep control stable
			local camRight = Camera.CFrame.RightVector
			local right = (camRight - camRight:Dot(n) * n)
			if right.Magnitude < 0.1 then
				right = Vector3.new(1,0,0)
			else
				right = right.Unit
			end
			local back = right:Cross(n).Unit

			-- stick to wall
			local targetPos = hit.Position + n * 2
			hrp.CFrame = CFrame.fromMatrix(targetPos, right, n, -back)
			hum.PlatformStand = false
		end
	end)
	table.insert(connections, spiderConn)
end

-- Keep spider loop managed
track(RunService.Heartbeat:Connect(function()
	if state.terminated then return end
	if state.spiderWalk then
		if not spiderConn then startSpider() end
	else
		if spiderConn then stopSpider() end
	end
end))

Header(Tabs.Movement, "Movement")
Tabs.Movement:CreateToggle({ Name = "Noclip", CurrentValue = false, Flag = "Noclip", Callback = function(on) state.noclip = on end })
Tabs.Movement:CreateToggle({ Name = "Infinite Jump", CurrentValue = false, Flag = "InfiniteJump", Callback = function(on) state.infiniteJump = on end })
Tabs.Movement:CreateSlider({
	Name = "Gravity",
	Range = {0, 250}, -- reduced (was 300)
	Increment = 1,
	Suffix = "",
	CurrentValue = Workspace.Gravity,
	Flag = "Gravity",
	Callback = function(v) Workspace.Gravity = v end
})
Tabs.Movement:CreateToggle({ Name = "Fly", CurrentValue = false, Flag = "Fly", Callback = function(on) if on then startFly() else stopFly() end end })
Tabs.Movement:CreateSlider({
	Name = "Fly Speed",
	Range = {10, 180}, -- reduced (was 250)
	Increment = 1,
	Suffix = "",
	CurrentValue = 60,
	Flag = "FlySpeed",
	Callback = function(v) state.flySpeed = v end
})

if premium() then
	Header(Tabs.Movement, "Bunny Hop")

	Tabs.Movement:CreateToggle({
		Name = "Bunny Hop",
		CurrentValue = state.bunnyHop,
		Flag = "BunnyHop",
		Callback = function(on)
			state.bunnyHop = on and true or false
		end
	})
end

Header(Tabs.Movement, "Spider")

if premium() then
	Header(Tabs.Movement, "Spider")

	Tabs.Movement:CreateToggle({
		Name = "Spider (Broken)",
		CurrentValue = state.spiderWalk,
		Flag = "SpiderWalk",
		Callback = function(on)
			state.spiderWalk = on and true or false
		end
	})
end

track(RunService.Heartbeat:Connect(function()
	if state.terminated then return end
	if not state.bunnyHop then return end

	local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end

	local st = hum:GetState()
	if st == Enum.HumanoidStateType.Running or st == Enum.HumanoidStateType.RunningNoPhysics or st == Enum.HumanoidStateType.Landed then
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end))

Header(Tabs.Movement, "Utility")
Tabs.Movement:CreateButton({
	Name = "Sit / Unsit",
	Callback = function()
		pcall(function()
			local hum = getHumanoid()
			hum.Sit = not hum.Sit
		end)
	end
})
Tabs.Movement:CreateButton({
	Name = "Reset Movement",
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
		notify("Reset", "Movement reset.", 2)
	end
})

track(UIS.JumpRequest:Connect(function()
	if state.terminated then return end
	if not state.infiniteJump then return end
	pcall(function() getHumanoid():ChangeState(Enum.HumanoidStateType.Jumping) end)
end))

track(RunService.Stepped:Connect(function()
	if state.terminated then return end
	if not state.noclip then return end
	local char = LocalPlayer.Character
	if not char then return end
	for _, v in ipairs(char:GetDescendants()) do
		if v:IsA("BasePart") then v.CanCollide = false end
	end
end))

--========================
-- TELEPORT TAB
--========================
local TeamDropdown
local TpDropdown

local function getTeamNames()
	local values = { "All" }
	for _, team in ipairs(Teams:GetChildren()) do
		if team:IsA("Team") then table.insert(values, team.Name) end
	end
	table.sort(values, function(a,b)
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

local function getFollowablePlayersOrdered()
	local teamName = state.targetTeamFilter
	if not isValidTeamName(teamName) then teamName = "All" end
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer and playerMatchesTeam(p, teamName) then table.insert(list, p.Name) end
	end
	table.sort(list)
	return list
end

local function pickNextName(currentName)
	local list = getFollowablePlayersOrdered()
	if #list == 0 then return nil end
	if not currentName then return list[1] end
	local idx
	for i, name in ipairs(list) do if name == currentName then idx = i break end end
	if not idx then return list[1] end
	local nextIdx = idx + 1
	if nextIdx > #list then nextIdx = 1 end
	return list[nextIdx]
end

local function refreshTeamDropdown(tryKeep)
	local values = getTeamNames()
	if TeamDropdown then dropdownSetValues(TeamDropdown, values) end
	if tryKeep and ui.TeamFilter and table.find(values, ui.TeamFilter) then
		-- keep
	else
		ui.TeamFilter = "All"
		dropdownSetCurrent(TeamDropdown, "All")
	end
end

local function refreshTargetDropdown(tryKeepTarget)
	local values = getPlayerNamesFiltered()
	if TpDropdown then dropdownSetValues(TpDropdown, values) end

	if tryKeepTarget and ui.TPPlayer and table.find(values, ui.TPPlayer) then
		-- keep
	elseif #values > 0 then
		ui.TPPlayer = values[1]
		dropdownSetCurrent(TpDropdown, ui.TPPlayer)
	else
		ui.TPPlayer = nil
	end
end

local function getCurrentTarget()
	local name = ui.TPPlayer
	if type(name) ~= "string" or name == "" then return nil end
	local plr = Players:FindFirstChild(name)
	if not plr or plr == LocalPlayer then return nil end
	if not playerMatchesTeam(plr, state.targetTeamFilter) then return nil end
	return plr
end

local function teleportBehindTarget(targetPlr)
	if not targetPlr then return false end
	local theirRoot = getRootOf(targetPlr)
	if not theirRoot then return false end
	local myRoot = getRoot()
	myRoot.CFrame = theirRoot.CFrame * CFrame.new(0, state.followOffsetUp, -state.followOffsetBack)
	return true
end

local followDiedConn
local function disconnectFollowDied()
	if followDiedConn then followDiedConn:Disconnect(); followDiedConn = nil end
end

local function bindDeathListenerForTarget(plr)
	disconnectFollowDied()
	if not plr then return end
	local hum = getHumanoidOf(plr)
	if not hum then return end

	followDiedConn = hum.Died:Connect(function()
		if not state.followEnabled then return end
		local nextName = pickNextName(ui.TPPlayer)
		if not nextName then
			state.followEnabled = false
			state.followPaused = false
			disconnectFollowDied()
			notify("Follow", "No valid players left.", 3)
			return
		end
		ui.TPPlayer = nextName
		dropdownSetCurrent(TpDropdown, nextName)
		local nextPlr = Players:FindFirstChild(nextName)
		if nextPlr then
			teleportBehindTarget(nextPlr)
			maybeEquipAfterAction()
			bindDeathListenerForTarget(nextPlr)
		end
	end)

	table.insert(connections, followDiedConn)
end

Header(Tabs.Teleport, "Players")
TeamDropdown = Tabs.Teleport:CreateDropdown({
	Name = "Team Filter",
	Options = getTeamNames(),
	CurrentOption = {"All"},
	MultipleOptions = false,
	Flag = "TeamFilter",
	Callback = function(val)
		if type(val) == "table" then val = val[1] end
		if type(val) ~= "string" then return end
		if not isValidTeamName(val) then val = "All" end
		ui.TeamFilter = val
		state.targetTeamFilter = val
		refreshTargetDropdown(false)
	end
})

TpDropdown = Tabs.Teleport:CreateDropdown({
	Name = "Target",
	Options = getPlayerNamesFiltered(),
	CurrentOption = {},
	MultipleOptions = false,
	Flag = "TPPlayer",
	Callback = function(val)
		if type(val) == "table" then val = val[1] end
		if type(val) ~= "string" then return end
		ui.TPPlayer = val

		if state.followEnabled then
			local target = getCurrentTarget()
			if target then
				teleportBehindTarget(target)
				maybeEquipAfterAction()
				bindDeathListenerForTarget(target)
			end
		end
	end
})

Tabs.Teleport:CreateButton({
	Name = "Teleport",
	Callback = function()
		local target = getCurrentTarget()
		if not target then return end
		local theirRoot = getRootOf(target)
		if not theirRoot then return end
		getRoot().CFrame = theirRoot.CFrame * CFrame.new(0, 0, 3)
		maybeEquipAfterAction()
	end
})

Tabs.Teleport:CreateButton({
	Name = "Next Player (Teleport)",
	Callback = function()
		local nextName = pickNextName(ui.TPPlayer)
		if not nextName then
			notify("Teleport", "No valid players in this filter.", 3)
			return
		end

		ui.TPPlayer = nextName
		dropdownSetCurrent(TpDropdown, nextName)

		local target = Players:FindFirstChild(nextName)
		if not target then return end

		if state.followEnabled then
			teleportBehindTarget(target)
			maybeEquipAfterAction()
			bindDeathListenerForTarget(target)
		else
			local theirRoot = getRootOf(target)
			if not theirRoot then return end
			getRoot().CFrame = theirRoot.CFrame * CFrame.new(0, 0, 3)
			maybeEquipAfterAction()
		end
	end
})

track(Teams.ChildAdded:Connect(function() refreshTeamDropdown(true); refreshTargetDropdown(true) end))
track(Teams.ChildRemoved:Connect(function() refreshTeamDropdown(true); refreshTargetDropdown(true) end))
track(Players.PlayerAdded:Connect(function() refreshTargetDropdown(true) end))
track(Players.PlayerRemoving:Connect(function() refreshTargetDropdown(true) end))

local teamConns = {}
local function hookTeamChange(plr)
	if teamConns[plr] then teamConns[plr]:Disconnect() end
	teamConns[plr] = plr:GetPropertyChangedSignal("Team"):Connect(function()
		if state.terminated then return end
		refreshTargetDropdown(true)
	end)
end
for _, p in ipairs(Players:GetPlayers()) do hookTeamChange(p) end
track(Players.PlayerAdded:Connect(hookTeamChange))
track(Players.PlayerRemoving:Connect(function(plr)
	if teamConns[plr] then teamConns[plr]:Disconnect(); teamConns[plr] = nil end
end))

Header(Tabs.Teleport, "Follow")
local followAcc = 0

Tabs.Teleport:CreateToggle({
	Name = "Follow Target",
	CurrentValue = false,
	Flag = "FollowToggle",
	Callback = function(on)
		state.followEnabled = on
		state.followPaused = false
		followAcc = 0

		if not on then
			disconnectFollowDied()
			return
		end

		local target = getCurrentTarget()
		if not target then
			local nextName = pickNextName(nil)
			if nextName then
				ui.TPPlayer = nextName
				dropdownSetCurrent(TpDropdown, nextName)
				target = Players:FindFirstChild(nextName)
			end
		end

		if not target then
			state.followEnabled = false
			notify("Follow", "No valid target.", 3)
			return
		end

		teleportBehindTarget(target)
		maybeEquipAfterAction()
		bindDeathListenerForTarget(target)
	end
})

Tabs.Teleport:CreateSlider({ Name = "Offset Back", Range = {0, 25}, Increment = 1, CurrentValue = 4, Flag = "FollowBack", Callback = function(v) state.followOffsetBack = v end })
Tabs.Teleport:CreateSlider({ Name = "Offset Up", Range = {-10, 25}, Increment = 1, CurrentValue = 0, Flag = "FollowUp", Callback = function(v) state.followOffsetUp = v end })
Tabs.Teleport:CreateSlider({ Name = "Smoothness", Range = {1, 25}, Increment = 1, CurrentValue = 12, Flag = "FollowSmooth", Callback = function(v) state.followSmoothness = v end })
Tabs.Teleport:CreateSlider({
	Name = "Update Rate (sec)",
	Range = {0.01, 0.5}, -- reduced (was 1)
	Increment = 0.01,
	Suffix = "s",
	CurrentValue = 0.01,
	Flag = "FollowRate",
	Callback = function(v) state.followUpdateRate = v end
})

Tabs.Teleport:CreateToggle({
	Name = "Predictive Follow",
	CurrentValue = state.followPredictive,
	Flag = "FollowPredictive",
	Callback = function(on) state.followPredictive = on and true or false end
})

Tabs.Teleport:CreateSlider({
	Name = "Predict Ahead",
	Range = {0, 1.0},
	Increment = 0.05,
	Suffix = "s",
	CurrentValue = state.followPredictAhead,
	Flag = "FollowPredictAhead",
	Callback = function(v) state.followPredictAhead = v end
})

Tabs.Teleport:CreateToggle({
	Name = "Equip Weapon on Follow",
	CurrentValue = false,
	Flag = "EquipOnTPFollow",
	Callback = function(on) state.equipOnFollowOrTP = on end
})
Tabs.Teleport:CreateButton({
	Name = "Stop Follow",
	Callback = function()
		state.followEnabled = false
		state.followPaused = false
		disconnectFollowDied()
		notify("Follow", "Stopped.", 2)
	end
})

Header(Tabs.Teleport, "Safety Teleports")

Tabs.Teleport:CreateSlider({
	Name = "Ground Offset",
	Range = {1, 10},
	Increment = 0.5,
	Suffix = "m",
	CurrentValue = state.tpToGroundOffset,
	Flag = "GroundOffset",
	Callback = function(v) state.tpToGroundOffset = v end
})

Tabs.Teleport:CreateButton({
	Name = "Teleport to Ground",
	Callback = function()
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Blacklist
		params.FilterDescendantsInstances = { char }

		local res = Workspace:Raycast(hrp.Position, Vector3.new(0, -5000, 0), params)
		if res then
			hrp.CFrame = CFrame.new(res.Position + Vector3.new(0, state.tpToGroundOffset, 0))
		end
	end
})

Tabs.Teleport:CreateButton({
	Name = "Unstuck Teleport",
	Callback = function()
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Blacklist
		params.FilterDescendantsInstances = { char }

		local function isFree(pos)
			local parts = Workspace:GetPartBoundsInBox(CFrame.new(pos), Vector3.new(4, 6, 4), params)
			return #parts == 0
		end

		local base = hrp.Position
		local offsets = {
			Vector3.new(0, 3, 0),
			Vector3.new(0, 6, 0),
			Vector3.new(2, 0, 0),
			Vector3.new(-2, 0, 0),
			Vector3.new(0, 0, 2),
			Vector3.new(0, 0, -2),
			Vector3.new(2, 0, 2),
			Vector3.new(-2, 0, -2),
			Vector3.new(4, 0, 0),
			Vector3.new(-4, 0, 0),
			Vector3.new(0, 0, 4),
			Vector3.new(0, 0, -4),
			Vector3.new(0, 10, 0),
		}

		for _, off in ipairs(offsets) do
			local p = base + off
			if isFree(p) then
				hrp.CFrame = CFrame.new(p)
				return
			end
		end
	end
})

Header(Tabs.Teleport, "Circle Target")

Tabs.Teleport:CreateToggle({
	Name = "Circle Target",
	CurrentValue = state.tpCircleEnabled,
	Flag = "CircleTarget",
	Callback = function(on) state.tpCircleEnabled = on and true or false end
})

Tabs.Teleport:CreateSlider({
	Name = "Radius",
	Range = {3, 25},
	Increment = 1,
	Suffix = "m",
	CurrentValue = state.tpCircleRadius,
	Flag = "CircleRadius",
	Callback = function(v) state.tpCircleRadius = v end
})

Tabs.Teleport:CreateSlider({
	Name = "Speed",
	Range = {0.2, 5},
	Increment = 0.1,
	Suffix = "x",
	CurrentValue = state.tpCircleSpeed,
	Flag = "CircleSpeed",
	Callback = function(v) state.tpCircleSpeed = v end
})

track(RunService.RenderStepped:Connect(function(dt)
	if state.terminated then return end
	if not state.tpCircleEnabled then return end
	local target = getCurrentTarget()
	if not target then return end
	local tr = getRootOf(target)
	local mr = getRoot()
	if not tr or not mr then return end

	state._circleT = (state._circleT or 0) + dt * state.tpCircleSpeed
	local ang = state._circleT
	local offset = Vector3.new(math.cos(ang), 0, math.sin(ang)) * state.tpCircleRadius
	local desired = CFrame.new(tr.Position + offset + Vector3.new(0, state.followOffsetUp, 0), tr.Position)
	mr.CFrame = mr.CFrame:Lerp(desired, 1 - math.exp(-12 * dt))
end))

Header(Tabs.Teleport, "Quick Teleports")

Tabs.Teleport:CreateButton({
	Name = "Teleport to Cursor",
	Callback = function()
		local cf = getMouseHitCFrame(5000)
		local r = getRoot()
		r.CFrame = cf
		maybeEquipAfterAction()
	end
})

Tabs.Teleport:CreateButton({
	Name = "Teleport to Spawn",
	Callback = function()
		local cf = findSpawnCFrame()
		if not cf then
			notify("Teleport", "Spawn location not found in this game.", 4, true)
			return
		end
		getRoot().CFrame = cf
		maybeEquipAfterAction()
	end
})

track(RunService.RenderStepped:Connect(function(dt)
	if state.terminated then return end
	if not state.followEnabled then return end
	if state.followPaused then return end

	followAcc += dt
	if followAcc < state.followUpdateRate then return end
	followAcc = 0

	local target = getCurrentTarget()
	if not target then return end

	local theirRoot = getRootOf(target)
	local myRoot = getRoot()
	if not theirRoot or not myRoot then return end

	local baseCF = theirRoot.CFrame
	if state.followPredictive then
		local vel = theirRoot.AssemblyLinearVelocity
		local predictedPos = theirRoot.Position + (vel * state.followPredictAhead)
		baseCF = CFrame.new(predictedPos, predictedPos + baseCF.LookVector)
	end
	local desired = baseCF * CFrame.new(0, state.followOffsetUp, -state.followOffsetBack)
	local alpha = 1 - math.exp(-state.followSmoothness * dt)
	myRoot.CFrame = myRoot.CFrame:Lerp(desired, alpha)
end))

Header(Tabs.Teleport, "Waypoints")

local SavedDropdown = Tabs.Teleport:CreateDropdown({
	Name = "Waypoints",
	Options = {},
	CurrentOption = {},
	MultipleOptions = false,
	Flag = "SavedPos",
	Callback = function(val)
		if type(val) == "table" then val = val[1] end
		if type(val) ~= "string" then return end
		ui.SavedPos = val
	end
})

Tabs.Teleport:CreateInput({
	Name = "Waypoint Name",
	PlaceholderText = "Spawn / Shop / etc",
	RemoveTextAfterFocusLost = false,
	Callback = function(text)
		ui.SaveName = tostring(text or "")
	end
})

local function refreshSavedDropdown()
	local values = {}
	for _, item in ipairs(state.savedPositions) do table.insert(values, item.Name) end
	dropdownSetValues(SavedDropdown, values)

	if ui.SavedPos and table.find(values, ui.SavedPos) then
		dropdownSetCurrent(SavedDropdown, ui.SavedPos)
	elseif #values > 0 then
		ui.SavedPos = values[1]
		dropdownSetCurrent(SavedDropdown, ui.SavedPos)
	else
		ui.SavedPos = nil
	end
end

Tabs.Teleport:CreateButton({
	Name = "Save Current Position",
	Callback = function()
		local name = ui.SaveName
		if type(name) ~= "string" or name:gsub("%s+", "") == "" then
			notify("Waypoints", "Enter a name first.", 3)
			return
		end
		table.insert(state.savedPositions, { Name = name, CFrame = getRoot().CFrame })
		refreshSavedDropdown()
	end
})

Tabs.Teleport:CreateButton({
	Name = "Teleport to Waypoint",
	Callback = function()
		local pick = ui.SavedPos
		for _, item in ipairs(state.savedPositions) do
			if item.Name == pick then
				getRoot().CFrame = item.CFrame
				return
			end
		end
		notify("Waypoints", "No waypoint selected.", 3)
	end
})

Tabs.Teleport:CreateButton({
	Name = "Delete Selected Waypoint",
	Callback = function()
		local pick = ui.SavedPos
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

Tabs.Teleport:CreateButton({
	Name = "Clear All Waypoints",
	Callback = function()
		state.savedPositions = {}
		refreshSavedDropdown()
	end
})

Tabs.Teleport:CreateInput({
	Name = "Waypoint Code",
	PlaceholderText = "Paste waypoint code here...",
	RemoveTextAfterFocusLost = false,
	Callback = function(text)
		ui.WaypointCode = tostring(text or "")
	end
})

local function serializeWaypoints()
	local out = { placeId = game.PlaceId, waypoints = {} }
	for _, w in ipairs(state.savedPositions) do
		table.insert(out.waypoints, { name = w.Name, cf = { w.CFrame:GetComponents() } })
	end
	return HttpService:JSONEncode(out)
end

local function deserializeWaypoints(json)
	local ok, data = pcall(function() return HttpService:JSONDecode(json) end)
	if not ok or type(data) ~= "table" then return false, "Invalid JSON" end
	if data.placeId ~= game.PlaceId then return false, "Code is for a different placeId" end
	if type(data.waypoints) ~= "table" then return false, "Missing waypoints" end

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

Tabs.Teleport:CreateButton({
	Name = "Export Waypoints",
	Callback = function()
		local code = serializeWaypoints()
		ui.WaypointCode = code
		if typeof(setclipboard) == "function" then
			pcall(function() setclipboard(code) end)
			notify("Waypoints", "Exported + copied to clipboard.", 3)
		else
			notify("Waypoints", "Exported. Copy from the input box.", 4)
		end
	end
})

Tabs.Teleport:CreateButton({
	Name = "Import Waypoints",
	Callback = function()
		local code = ui.WaypointCode
		if type(code) ~= "string" or #code < 5 then return end
		local ok, err = deserializeWaypoints(code)
		if ok then notify("Waypoints", "Imported successfully.", 3)
		else notify("Waypoints", "Import failed: " .. tostring(err), 5) end
	end
})

--========================
-- VISUAL TAB
--========================
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
			for k, v in pairs(state.storedLighting) do
				Lighting[k] = v
			end
		end
	end
end

Header(Tabs.Visual, "Lighting")
Tabs.Visual:CreateToggle({ Name = "Fullbright", CurrentValue = false, Flag = "Fullbright", Callback = function(on) setFullbright(on) end })

Header(Tabs.Visual, "Visual Filters")

local savedVisual = savedVisual or {}

local function setRemoveEffects(on)
	if on then
		if savedVisual._effectsSaved then return end
		savedVisual._effectsSaved = {}
		for _, inst in ipairs(Lighting:GetChildren()) do
			if inst:IsA("BloomEffect") or inst:IsA("BlurEffect") or inst:IsA("ColorCorrectionEffect") or inst:IsA("SunRaysEffect") or inst:IsA("DepthOfFieldEffect") then
				savedVisual._effectsSaved[inst] = inst.Enabled
				inst.Enabled = false
			end
		end
	else
		if not savedVisual._effectsSaved then return end
		for inst, was in pairs(savedVisual._effectsSaved) do
			if inst and inst.Parent then inst.Enabled = was end
		end
		savedVisual._effectsSaved = nil
	end
end

local nightCC = nightCC or Instance.new("ColorCorrectionEffect")
nightCC.Name = "AdminNightVision"
nightCC.Parent = Lighting
nightCC.Enabled = false

local function setNightVision(on)
	nightCC.Enabled = on and true or false
	if nightCC.Enabled then
		nightCC.Contrast = 0.2
		nightCC.Brightness = 0.05
		nightCC.Saturation = 0.1
		nightCC.TintColor = Color3.fromRGB(120, 255, 160)
	end
end

local savedWeather = savedWeather or {}
local function setNoWeather(on)
	if on then
		if savedWeather._saved then return end
		savedWeather._saved = {
			FogEnd = Lighting.FogEnd,
			FogStart = Lighting.FogStart,
			FogColor = Lighting.FogColor
		}
		Lighting.FogEnd = 1e9
		Lighting.FogStart = 0
	else
		if not savedWeather._saved then return end
		for k,v in pairs(savedWeather._saved) do Lighting[k] = v end
		savedWeather._saved = nil
	end

	-- Disable Atmosphere/Clouds when enabled
	for _, inst in ipairs(Lighting:GetChildren()) do
		if inst:IsA("Atmosphere") or inst:IsA("Clouds") then
			inst.Enabled = not on
		end
	end
end

local particleCache = particleCache or {}
local function setNoParticles(on)
	if on then
		if particleCache._saved then return end
		particleCache._saved = {}
		for _, inst in ipairs(Workspace:GetDescendants()) do
			if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") then
				particleCache._saved[inst] = inst.Enabled
				inst.Enabled = false
			end
		end
	else
		if not particleCache._saved then return end
		for inst, was in pairs(particleCache._saved) do
			if inst and inst.Parent then inst.Enabled = was end
		end
		particleCache._saved = nil
	end
end

-- GUI toggle (safe exclude Rayfield)
local savedGuiState = {}

local function setGuiHidden(hide)
	local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then return end

	for _, gui in ipairs(pg:GetChildren()) do
		if gui:IsA("ScreenGui") then
			local n = gui.Name:lower()
			if n:find("rayfield") then
				continue
			end
			if hide then
				if savedGuiState[gui] == nil then
					savedGuiState[gui] = gui.Enabled
				end
				gui.Enabled = false
			else
				if savedGuiState[gui] ~= nil then
					gui.Enabled = savedGuiState[gui]
				end
			end
		end
	end

	if not hide then
		table.clear(savedGuiState)
	end
end

-- No camera shake: low-pass filter camera position (reduces jitter)
local camFilterConn
local camSmoothPos, camSmoothLook

local function startNoShake()
	if camFilterConn then return end
	camSmoothPos = nil
	camSmoothLook = nil

	camFilterConn = RunService:BindToRenderStep("Axiom_NoShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if not state.noCamShake then return end
		local cam = Workspace.CurrentCamera
		if not cam then return end

		local cf = cam.CFrame
		local pos = cf.Position
		local look = cf.LookVector

		if not camSmoothPos then
			camSmoothPos = pos
			camSmoothLook = look
		end

		-- filter high frequency shake
		local a = 1 - math.exp(-12 * dt)
		camSmoothPos = camSmoothPos:Lerp(pos, a)
		camSmoothLook = (camSmoothLook:Lerp(look, a)).Unit

		cam.CFrame = CFrame.new(camSmoothPos, camSmoothPos + camSmoothLook)
	end)
end

local function stopNoShake()
	pcall(function()
		RunService:UnbindFromRenderStep("Axiom_NoShake")
	end)
	camFilterConn = nil
end

-- Save/restore visuals
local savedLighting = nil
local savedEffects = nil

local function captureVisuals()
	if savedLighting then return end
	savedLighting = {
		Brightness = Lighting.Brightness,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		ClockTime = Lighting.ClockTime,
		FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart,
		FogColor = Lighting.FogColor,
	}
	savedEffects = {}
	for _, inst in ipairs(Lighting:GetChildren()) do
		if inst:IsA("BloomEffect") or inst:IsA("BlurEffect") or inst:IsA("ColorCorrectionEffect")
			or inst:IsA("SunRaysEffect") or inst:IsA("DepthOfFieldEffect") then
			savedEffects[inst] = inst.Enabled
		end
	end
end

local function restoreVisuals()
	-- stop special camera stuff
	state.noCamShake = false
	stopNoShake()

	-- restore lighting
	if savedLighting then
		for k,v in pairs(savedLighting) do
			pcall(function() Lighting[k] = v end)
		end
		savedLighting = nil
	end
	if savedEffects then
		for inst, was in pairs(savedEffects) do
			if inst and inst.Parent then inst.Enabled = was end
		end
		savedEffects = nil
	end

	-- restore particles/weather toggles you already have
	pcall(function()
		-- if you have your own setters, call them here:
		-- setRemoveEffects(false)
		-- setNightVision(false)
		-- setNoWeather(false)
		-- setNoParticles(false)
	end)

	-- restore GUI
	state.guiHidden = false
	setGuiHidden(false)

	notify("Visuals", "Restored.", 2)
end

_G.__AXIOM_VISUALS_RESTORE = restoreVisuals

-- keep systems updated
track(RunService.Heartbeat:Connect(function()
	if state.terminated then return end

	-- capture baseline once
	captureVisuals()

	-- gui hide/show
	if state.guiHidden then
		setGuiHidden(true)
	else
		-- do not constantly restore; only when toggled off
	end

	-- no shake
	if state.noCamShake then
		startNoShake()
	else
		stopNoShake()
	end
end))

Tabs.Visual:CreateToggle({ Name = "Remove Lighting Effects", CurrentValue = state.removeEffects, Flag="RemoveEffects", Callback = function(on) state.removeEffects = on; setRemoveEffects(on) end })
if premium() then
	Header(Tabs.Visual, "Night Vision")

	Tabs.Visual:CreateToggle({
		Name = "Night Vision",
		CurrentValue = state.nightVision,
		Flag = "NightVision",
		Callback = function(on)
			state.nightVision = on and true or false
			setNightVision(on)
		end
	})
end
Tabs.Visual:CreateToggle({ Name = "No Weather (Fog/Atmosphere)", CurrentValue = state.noWeather, Flag="NoWeather", Callback = function(on) state.noWeather = on; setNoWeather(on) end })
Tabs.Visual:CreateToggle({ Name = "No Particles", CurrentValue = state.noParticles, Flag="NoParticles", Callback = function(on) state.noParticles = on; setNoParticles(on) end })

if premium() then
	Header(Tabs.Visual, "Camera")

	Tabs.Visual:CreateToggle({
		Name = "No Camera Shake",
		CurrentValue = state.noCamShake,
		Flag = "NoCamShake",
		Callback = function(on)
			state.noCamShake = on and true or false
		end
	})
end

Header(Tabs.Visual, "UI")

Tabs.Visual:CreateToggle({
	Name = "Hide Game UI (Safe)",
	CurrentValue = state.guiHidden,
	Flag = "HideGUI",
	Callback = function(on)
		state.guiHidden = on and true or false
		-- handled by logic below
	end
})

Tabs.Visual:CreateButton({
	Name = "Restore Visuals",
	Callback = function()
		if _G.__AXIOM_VISUALS_RESTORE then
			_G.__AXIOM_VISUALS_RESTORE()
		end
	end
})

Header(Tabs.Visual, "Freecam")

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
		if state.terminated then return end
		if not state.freecamEnabled then return end

		local speed = state.freecamSpeed
		if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then speed *= state.freecamFastMult end

		local forward, right, up = 0, 0, 0
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
		if move.Magnitude > 0 then move = move.Unit * speed * dt end

		freecamPos += (basis.RightVector * move.X) + (Vector3.new(0,1,0) * move.Y) + (basis.LookVector * move.Z)
		Camera.CFrame = CFrame.new(freecamPos) * rotCF
	end)

	table.insert(connections, freecamConn)
end

Tabs.Visual:CreateToggle({ Name = "Freecam", CurrentValue = false, Flag = "Freecam", Callback = function(on) if on then startFreecam() else stopFreecam() end end })
Tabs.Visual:CreateSlider({
	Name = "Freecam Speed",
	Range = {10, 150}, -- reduced (was 250)
	Increment = 1,
	Suffix = "",
	CurrentValue = 48,
	Flag = "FreecamSpeed",
	Callback = function(v) state.freecamSpeed = v end
})
Tabs.Visual:CreateSlider({
	Name = "Shift Multiplier",
	Range = {2, 6}, -- reduced (was 8)
	Increment = 1,
	Suffix = "x",
	CurrentValue = 3,
	Flag = "FreecamFastMult",
	Callback = function(v) state.freecamFastMult = v end
})
Tabs.Visual:CreateButton({ Name = "Reset Camera", Callback = function() stopFreecam(); notify("Camera", "Reset.", 2) end })

--========================
-- ESP TAB
--========================
Header(Tabs.ESP, "ESP")

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
	if billboardsByPlayer[plr] then
		return billboardsByPlayer[plr]
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = "ESPLabel_" .. plr.Name
	bb.Size = UDim2.fromOffset(280, 54)
	bb.AlwaysOnTop = true
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.MaxDistance = state.espMaxDistance
	bb.Parent = espFolder

	-- Text
	local tl = Instance.new("TextLabel")
	tl.BackgroundTransparency = 1
	tl.Size = UDim2.fromScale(1, 1)
	tl.TextScaled = false
	tl.TextSize = 14
	tl.TextWrapped = false
	tl.Font = Enum.Font.GothamSemibold
	tl.TextStrokeTransparency = 0.5
	tl.TextColor3 = Color3.new(1, 1, 1)
	tl.Text = ""
	tl.Parent = bb

	-- Health bar background
	local barBg = Instance.new("Frame")
	barBg.Name = "HP_BG"
	barBg.AnchorPoint = Vector2.new(0.5, 0)
	barBg.Position = UDim2.new(0.5, 0, 1, -10)
	barBg.Size = UDim2.fromOffset(160, 6)
	barBg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	barBg.BackgroundTransparency = 0.35
	barBg.BorderSizePixel = 0
	barBg.Visible = false
	barBg.Parent = bb

	-- Health bar fill
	local bar = Instance.new("Frame")
	bar.Name = "HP"
	bar.Position = UDim2.fromOffset(0, 0)
	bar.Size = UDim2.fromScale(1, 1)
	bar.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
	bar.BorderSizePixel = 0
	bar.Parent = barBg

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
		if state.terminated then return end
		if not state.espEnabled then return end

		acc += dt
		if acc < state.espRefreshRate then return end
		acc = 0

		local localRoot = getRootOf(LocalPlayer)
		if not localRoot then return end

		for _, plr in ipairs(Players:GetPlayers()) do
			if plr == LocalPlayer then continue end
			local root = getRootOf(plr)
			if not root then cleanupESPPlayer(plr) continue end

			local dist = (root.Position - localRoot.Position).Magnitude
			if not shouldShowESP(plr, dist) then cleanupESPPlayer(plr) continue end

			local h = ensureHighlight(plr)
			h.Adornee = plr.Character

			if state.espShowNames or state.espShowDistance or state.espShowHealth or state.espShowTeam then
				local bb = ensureBillboard(plr)
				bb.Enabled = (state.espMode == "Highlight")
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
					local hum = getHumanoidOf(plr)
					local isTarget = (state.espTarget ~= "" and plr.Name == state.espTarget)

					-- Health bar (Billboard)
					local bg = bb:FindFirstChild("HP_BG")
					local bar = bg and bg:FindFirstChild("HP")

					-- Only allow Billboard HP bar in Highlight mode
					local allowBillboardHP = (state.espMode == "Highlight")

					if bg then
						if allowBillboardHP and state.espShowBar and hum and hum.MaxHealth > 0 then
							local ratio = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
							bg.Visible = true
							bar.Size = UDim2.new(ratio, 0, 1, 0)
							bar.BackgroundColor3 = Color3.fromRGB(
								math.floor(255 - ratio * 255),
								math.floor(ratio * 255),
								80
							)
						else
							bg.Visible = false
						end
					end


					-- Target emphasis (Highlight + label)
					if h then
						h.FillTransparency = isTarget and 0.35 or 0.6
						h.OutlineTransparency = 0
					end
						tl.Font = isTarget and Enum.Font.GothamBold or Enum.Font.GothamSemibold
						tl.TextStrokeTransparency = isTarget and 0.25 or 0.5
				end
			else
				if billboardsByPlayer[plr] then billboardsByPlayer[plr]:Destroy(); billboardsByPlayer[plr] = nil end
			end

			if state.espTracers then
				local tr = ensureTracer(plr)
				tr.A0.Parent = localRoot
				tr.A1.Parent = root
				tr.A0.WorldPosition = localRoot.Position
				tr.A1.WorldPosition = root.Position
				tr.Beam.Enabled = true
			else
				if tracersByPlayer[plr] then tracersByPlayer[plr].Beam.Enabled = false end
			end
		end
	end)

	table.insert(connections, espConn)
end

--========================
-- Drawing ESP (single manager, no duplicates, nukes leftovers)
--========================
local DrawingOK = (typeof(Drawing) == "table" and typeof(Drawing.new) == "function")
local drawingConn = nil

-- Global registry so drawings from previous executions can be removed too
_G.__ADMIN_DRAW_REG = _G.__ADMIN_DRAW_REG or {}

local function reg(obj)
	table.insert(_G.__ADMIN_DRAW_REG, obj)
	return obj
end

local function nukeGlobalDrawings()
	local regt = _G.__ADMIN_DRAW_REG
	if type(regt) ~= "table" then return end
	for i = #regt, 1, -1 do
		local obj = regt[i]
		regt[i] = nil
		if obj then
			pcall(function() obj.Visible = false end)
			pcall(function()
				if obj.Remove then obj:Remove()
				elseif obj.Destroy then obj:Destroy()
				end
			end)
		end
	end
end

local drawObjects = {} -- [plr] = { box,name,hpbg,hp,lines={} }

local function dremove(plr)
	local o = drawObjects[plr]
	if not o then return end

	if o.lines then
		for _, ln in ipairs(o.lines) do
			pcall(function() ln.Visible = false end)
			pcall(function() ln:Remove() end)
		end
	end

	for _, k in ipairs({ "box","name","hpbg","hp" }) do
		local obj = o[k]
		if obj then
			pcall(function() obj.Visible = false end)
			pcall(function() obj:Remove() end)
		end
	end

	drawObjects[plr] = nil
end

local function clearAllDrawings()
	for plr in pairs(drawObjects) do
		dremove(plr)
	end
end

local function dget(plr)
	if drawObjects[plr] then return drawObjects[plr] end

	local o = { lines = {} }

	o.box = reg(Drawing.new("Square"))
	o.box.Thickness = 1
	o.box.Filled = false
	o.box.Visible = false

	o.name = reg(Drawing.new("Text"))
	o.name.Size = 14
	o.name.Center = true
	o.name.Outline = true
	o.name.Visible = false
	o.name.Text = ""

	o.hpbg = reg(Drawing.new("Square"))
	o.hpbg.Filled = true
	o.hpbg.Thickness = 0
	o.hpbg.Visible = false
	o.hpbg.Transparency = 0.55

	o.hp = reg(Drawing.new("Square"))
	o.hp.Filled = true
	o.hp.Thickness = 0
	o.hp.Visible = false
	o.hp.Transparency = 0.15

	for i = 1, 12 do
		local ln = reg(Drawing.new("Line"))
		ln.Thickness = 1
		ln.Visible = false
		table.insert(o.lines, ln)
	end

	drawObjects[plr] = o
	return o
end

local skelPairsR15 = {
	{"Head","UpperTorso"},
	{"UpperTorso","LowerTorso"},
	{"UpperTorso","LeftUpperArm"},
	{"LeftUpperArm","LeftLowerArm"},
	{"LeftLowerArm","LeftHand"},
	{"UpperTorso","RightUpperArm"},
	{"RightUpperArm","RightLowerArm"},
	{"RightLowerArm","RightHand"},
	{"LowerTorso","LeftUpperLeg"},
	{"LeftUpperLeg","LeftLowerLeg"},
	{"LowerTorso","RightUpperLeg"},
	{"RightUpperLeg","RightLowerLeg"},
}

local skelPairsR6 = {
	{"Head","Torso"},
	{"Torso","Left Arm"},
	{"Torso","Right Arm"},
	{"Torso","Left Leg"},
	{"Torso","Right Leg"},
}

local function startDrawingESP()
	if drawingConn then
		drawingConn:Disconnect()
		drawingConn = nil
	end

	drawingConn = RunService.RenderStepped:Connect(function()
		if state.terminated then return end
		if not DrawingOK then return end

		-- Only run in drawing modes and when ESP enabled
		if not state.espEnabled then
			clearAllDrawings()
			return
		end

		local mode = state.espMode
		local drawingModes = { Box=true, Skeleton=true, ["Box+Skeleton"]=true }
		if not drawingModes[mode] then
			clearAllDrawings()
			return
		end

		local lroot = getRootOf(LocalPlayer)
		if not lroot then clearAllDrawings(); return end

		for _, plr in ipairs(Players:GetPlayers()) do
			if plr == LocalPlayer then dremove(plr) continue end

			local root = getRootOf(plr)
			local hum = getHumanoidOf(plr)
			if not root then dremove(plr) continue end

			local dist = (root.Position - lroot.Position).Magnitude
			if dist > state.espMaxDistance then dremove(plr) continue end
			if state.espTeamCheck and plr.Team == LocalPlayer.Team then dremove(plr) continue end

			local o = dget(plr)

			-- hide all first
			o.box.Visible = false
			o.name.Visible = false
			o.hp.Visible = false
			o.hpbg.Visible = false
			for _, ln in ipairs(o.lines) do ln.Visible = false end

			local pos, onscreen = Camera:WorldToViewportPoint(root.Position)
			if not onscreen then
				continue
			end

			local scale = math.clamp(1 / (dist / 30), 0.6, 2.0)
			local w, h = 60 * scale, 90 * scale

			-- box
			if mode == "Box" or mode == "Box+Skeleton" then
				o.box.Size = Vector2.new(w, h)
				o.box.Position = Vector2.new(pos.X - w/2, pos.Y - h/2)
				o.box.Visible = true
			end

			-- name
			o.name.Text = plr.Name
			o.name.Position = Vector2.new(pos.X, pos.Y - h/2 - 16)
			o.name.Visible = true

			-- hp bar (Drawing)
			if state.espShowBar and hum and hum.MaxHealth > 0 then
				local hpRatio = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
				o.hpbg.Size = Vector2.new(w, 5)
				o.hpbg.Position = Vector2.new(pos.X - w/2, pos.Y + h/2 + 6)
				o.hpbg.Visible = true

				o.hp.Size = Vector2.new(w * hpRatio, 5)
				o.hp.Position = o.hpbg.Position
				o.hp.Visible = true
			end

			-- skeleton
			if mode == "Skeleton" or mode == "Box+Skeleton" then
				local char = plr.Character
				if char then
					local pairsToUse = char:FindFirstChild("UpperTorso") and skelPairsR15 or skelPairsR6
					local lineIdx = 1

					for _, pair in ipairs(pairsToUse) do
						local a = char:FindFirstChild(pair[1])
						local b = char:FindFirstChild(pair[2])
						local ln = o.lines[lineIdx]
						lineIdx += 1

						if ln and a and b and a:IsA("BasePart") and b:IsA("BasePart") then
							local ap, ao = Camera:WorldToViewportPoint(a.Position)
							local bp, bo = Camera:WorldToViewportPoint(b.Position)
							if ao and bo then
								ln.From = Vector2.new(ap.X, ap.Y)
								ln.To = Vector2.new(bp.X, bp.Y)
								ln.Visible = true
							end
						end
					end

					for i = lineIdx, #o.lines do
						o.lines[i].Visible = false
					end
				end
			end
		end
	end)

	table.insert(connections, drawingConn)
end

local function stopDrawingESP()
	if drawingConn then
		drawingConn:Disconnect()
		drawingConn = nil
	end
	clearAllDrawings()
	nukeGlobalDrawings()
end

-- Safety: never allow drawing ESP in Standard build
if not premium() then
	stopDrawingESP()
end

-- Clear stuck drawings from previous executions immediately
task.defer(stopDrawingESP)

Tabs.ESP:CreateToggle({
	Name = "ESP Enabled",
	CurrentValue = false,
	Flag = "ESPEnabled",
	Callback = function(on)
	state.espEnabled = on
	if on then
		startESP()

		local drawingModes = { Box=true, Skeleton=true, ["Box+Skeleton"]=true }
		if drawingModes[state.espMode] then
			startDrawingESP()
		else
			stopDrawingESP()
		end
	else
		stopESP()
		stopDrawingESP()
	end
	end
})

if opt == "Off" or opt == "Highlight" then
	stopDrawingESP()
end

local espModeOptions = premium()
	and {"Off","Highlight","Box","Skeleton","Box+Skeleton"}
	or  {"Off","Highlight"}

Tabs.ESP:CreateDropdown({
	Name = "Mode",
	Options = espModeOptions,
	CurrentOption = {state.espMode},
	MultipleOptions = false,
	Flag = "ESPMode",
	Callback = function(opt)
		if type(opt) == "table" then opt = opt[1] end
		opt = tostring(opt or "Highlight")

		-- If not premium, force safe mode
		if not premium() and (opt == "Box" or opt == "Skeleton" or opt == "Box+Skeleton") then
			opt = "Highlight"
		end

		state.espMode = opt

		local drawingModes = { Box=true, Skeleton=true, ["Box+Skeleton"]=true }
		if drawingModes[opt] and premium() then
			startDrawingESP()
		else
			stopDrawingESP()
		end
	end
})

Tabs.ESP:CreateToggle({ Name = "Show Names",    CurrentValue = true,  Flag = "ESPNames",     Callback = function(on) state.espShowNames = on end })
Tabs.ESP:CreateToggle({ Name = "Show Team",     CurrentValue = true,  Flag = "ESPTeam",      Callback = function(on) state.espShowTeam = on end })
Tabs.ESP:CreateToggle({ Name = "Show Health",   CurrentValue = true,  Flag = "ESPHealth",    Callback = function(on) state.espShowHealth = on end })
Tabs.ESP:CreateToggle({ Name = "Show Distance", CurrentValue = true,  Flag = "ESPDistance",  Callback = function(on) state.espShowDistance = on end })
Tabs.ESP:CreateToggle({ Name = "Team Check",    CurrentValue = false, Flag = "ESPTeamCheck", Callback = function(on) state.espTeamCheck = on end })

Tabs.ESP:CreateToggle({
	Name = "Health Bar",
	CurrentValue = state.espShowBar,
	Flag = "ESPBar",
	Callback = function(on) state.espShowBar = on and true or false end
})

local espTargetDropdown = Tabs.ESP:CreateDropdown({
	Name = "Target Player",
	Options = (function()
		local t = {"None"}
		for _,p in ipairs(Players:GetPlayers()) do
			if p ~= LocalPlayer then table.insert(t, p.Name) end
		end
		table.sort(t, function(a,b)
			if a == "None" then return true end
			if b == "None" then return false end
			return a < b
		end)
		return t
	end)(),
	CurrentOption = {state.espTarget ~= "" and state.espTarget or "None"},
	MultipleOptions = false,
	Flag = "ESPTarget",
	Callback = function(opt)
		if type(opt) == "table" then opt = opt[1] end
		opt = tostring(opt or "None")
		state.espTarget = (opt == "None") and "" or opt
	end
})

local function buildESPTargetList()
	local t = { "None" }
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then
			table.insert(t, p.Name)
		end
	end
	table.sort(t, function(a, b)
		if a == "None" then return true end
		if b == "None" then return false end
		return a < b
	end)
	return t
end

local function refreshESPTargetDropdown(tryKeep)
	if not espTargetDropdown then return end

	local values = buildESPTargetList()
	dropdownSetValues(espTargetDropdown, values)

	local wanted = (state.espTarget ~= "" and state.espTarget) or "None"

	if tryKeep and table.find(values, wanted) then
		dropdownSetCurrent(espTargetDropdown, wanted)
	else
		state.espTarget = ""
		dropdownSetCurrent(espTargetDropdown, "None")
	end
end

-- Refresh when players join/leave
track(Players.PlayerAdded:Connect(function()
	if state.terminated then return end
	task.defer(function() refreshESPTargetDropdown(true) end)
end))

track(Players.PlayerRemoving:Connect(function()
	if state.terminated then return end
	task.defer(function() refreshESPTargetDropdown(true) end)
end))

-- Initial fill (after UI builds)
task.defer(function()
	refreshESPTargetDropdown(true)
end)

Tabs.ESP:CreateToggle({ Name = "Tracers", CurrentValue = false, Flag = "ESPTracers", Callback = function(on) state.espTracers = on end })

Tabs.ESP:CreateSlider({
	Name = "Max Distance",
	Range = {50, 3000}, -- reduced (was 5000)
	Increment = 25,
	Suffix = "",
	CurrentValue = 1500,
	Flag = "ESPMaxDistance",
	Callback = function(v)
		state.espMaxDistance = v
		for _, bb in pairs(billboardsByPlayer) do bb.MaxDistance = v end
	end
})

Tabs.ESP:CreateSlider({
	Name = "Refresh (sec)",
	Range = {0.08, 1}, -- raised min slightly (was 0.05) to reduce load
	Increment = 0.01,
	Suffix = "s",
	CurrentValue = 0.15,
	Flag = "ESPRefresh",
	Callback = function(v) state.espRefreshRate = v end
})

Header(Tabs.ESP, "Hitboxes")

local originalHitboxes = {}
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

--========================
-- Hitbox Respawn Fix (Drop-in)
--========================

local function safeApplyOrRestore(plr)
	if state.hitboxEnabled then
		applyHitbox(plr)
	else
		restoreHitbox(plr)
	end
end

local function hookCharacter(plr)
	-- Apply once character exists (and again when HRP loads)
	local function onChar(char)
		-- wait a moment so HumanoidRootPart exists
		task.defer(function()
			if state.terminated then return end
			if not plr or not plr.Parent then return end

			-- If HRP isn't ready yet, wait briefly
			local ok = pcall(function()
				char:WaitForChild("HumanoidRootPart", 3)
			end)
			if not ok then return end

			safeApplyOrRestore(plr)
		end)
	end

	-- Hook current + future respawns
	if plr.Character then
		onChar(plr.Character)
	end

	track(plr.CharacterAdded:Connect(function(char)
		onChar(char)
	end))
end

-- Hook all existing players
for _, plr in ipairs(Players:GetPlayers()) do
	if plr ~= LocalPlayer then
		hookCharacter(plr)
	end
end

-- Hook new players
track(Players.PlayerAdded:Connect(function(plr)
	if plr == LocalPlayer then return end
	hookCharacter(plr)
end))

-- Cleanup when players leave (prevents memory issues + restores table)
track(Players.PlayerRemoving:Connect(function(plr)
	restoreHitbox(plr)
end))

Tabs.ESP:CreateToggle({
	Name = "Hitbox Toggle",
	CurrentValue = false,
	Flag = "HitboxEnabled",
	Callback = function(on)
		state.hitboxEnabled = on
		refreshAllHitboxes()
	end
})

Tabs.ESP:CreateSlider({
	Name = "Hitbox Size",
	Range = {2, 15}, -- reduced (was 20)
	Increment = 1,
	Suffix = "",
	CurrentValue = 8,
	Flag = "HitboxSize",
	Callback = function(v)
		state.hitboxSize = v
		if state.hitboxEnabled then refreshAllHitboxes() end
	end
})

Tabs.ESP:CreateSlider({
	Name = "Hitbox Transparency",
	Range = {0, 1},
	Increment = 0.05,
	Suffix = "",
	CurrentValue = 0.6,
	Flag = "HitboxTransparency",
	Callback = function(v)
		state.hitboxTransparency = v
		if state.hitboxEnabled then refreshAllHitboxes() end
	end
})

--========================
-- UTILITY TAB
--========================

Header(Tabs.Utility, "Server")

local ServerHop = (function()
	local Players = game:GetService("Players")
	local TeleportService = game:GetService("TeleportService")
	local HttpService = game:GetService("HttpService")

	local FILE_NAME = "server-hop-temp.json"
	local AllIDs = {}
	local cursor = ""
	local hour = os.date("!*t").hour

	local function fsOK()
		return typeof(readfile) == "function" and typeof(writefile) == "function"
	end

	local function loadIDs()
		if not fsOK() then
			AllIDs = { hour }
			return
		end
		local ok, data = pcall(function()
			return HttpService:JSONDecode(readfile(FILE_NAME))
		end)
		if ok and type(data) == "table" then
			AllIDs = data
		else
			AllIDs = { hour }
			pcall(function() writefile(FILE_NAME, HttpService:JSONEncode(AllIDs)) end)
		end
	end

	local function resetIfNewHour()
		local first = AllIDs[1]
		if type(first) == "number" and first ~= hour then
			if typeof(delfile) == "function" then pcall(function() delfile(FILE_NAME) end) end
			AllIDs = { hour }
			if fsOK() then pcall(function() writefile(FILE_NAME, HttpService:JSONEncode(AllIDs)) end) end
		end
	end

	local function seen(id)
		for i = 2, #AllIDs do
			if tostring(AllIDs[i]) == tostring(id) then return true end
		end
		return false
	end

	local function markSeen(id)
		table.insert(AllIDs, tostring(id))
		if fsOK() then pcall(function() writefile(FILE_NAME, HttpService:JSONEncode(AllIDs)) end) end
	end

	local function fetch(placeId, limit)
		limit = math.clamp(limit or 100, 10, 100)
		local url
		if cursor == "" then
			url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=%d"):format(placeId, limit)
		else
			url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=%d&cursor=%s"):format(placeId, limit, cursor)
		end
		-- Uses executor HTTP (works where HttpService:GetAsync is blocked)
		local raw = game:HttpGet(url)
		return HttpService:JSONDecode(raw)
	end

	local function teleportToInstance(placeId, serverId)
		return pcall(function()
			TeleportService:TeleportToPlaceInstance(placeId, serverId, Players.LocalPlayer)
		end)
	end

	-- Fallback matchmaking hop (no server list)
	local function fallbackMatchmake(placeId)
		-- Try Teleport() first
		local ok1 = pcall(function()
			TeleportService:Teleport(placeId, Players.LocalPlayer)
		end)
		if ok1 then return true end

		-- Then TeleportAsync
		local ok2 = pcall(function()
			local tpOpts = Instance.new("TeleportOptions")
			tpOpts:SetTeleportData({ _hop = os.time() })
			TeleportService:TeleportAsync(placeId, { Players.LocalPlayer }, tpOpts)
		end)
		return ok2
	end

	loadIDs()
	resetIfNewHour()

	local hopBusy = false

	return {
		Hop = function(_, placeId, mode)
			if hopBusy then
				notify("Server Hop", "A hop is already in progress.", 2)
				return
			end
			hopBusy = true

			-- readable pacing
			notify("Server Hop", "Searching for available servers…", 3)
			task.wait(0.9)

			-- Try server-list hop via game:HttpGet (supports least/random)
			local pages = 4
			local limit = 100
			local found = false
			local lastErr

			for _ = 1, pages do
				local ok, site = pcall(function()
					return fetch(placeId, limit)
				end)

				if not ok or type(site) ~= "table" then
					lastErr = "HTTP access is unavailable."
					break
				end

				if site.nextPageCursor and site.nextPageCursor ~= "null" then
					cursor = site.nextPageCursor
				else
					cursor = ""
				end

				local candidates = {}
				if type(site.data) == "table" then
					for _, srv in ipairs(site.data) do
						local id = srv and srv.id
						local playing = srv and srv.playing
						local maxPlayers = srv and srv.maxPlayers
						if id and playing and maxPlayers then
							if tostring(id) ~= game.JobId and tonumber(maxPlayers) > tonumber(playing) and not seen(id) then
								table.insert(candidates, srv)
							end
						end
					end
				end

				if #candidates > 0 then
					if mode == "least" then
						table.sort(candidates, function(a, b) return (a.playing or 0) < (b.playing or 0) end)
					else
						-- random
						local pick = candidates[math.random(1, #candidates)]
						candidates = { pick }
					end

					local chosen = candidates[1]
					local id = tostring(chosen.id)
					markSeen(id)

					notify("Server Hop", "Teleporting to a new server…", 3)
					task.wait(1.1)

					local okTp, errTp = teleportToInstance(placeId, id)
					if okTp then
						found = true
						break
					end

					-- Teleport blocked? stop server-list loop and use fallback
					lastErr = "Teleport was blocked by the client environment."
					break
				end

				-- no candidates this page
				task.wait(0.25)
				if cursor == "" then break end
			end

			if found then
				hopBusy = false
				return
			end

			-- Fallback
			notify("Server Hop", (lastErr or "No suitable servers found.") .. " Using fallback method.", 4)
			task.wait(1.0)

			local okFallback = fallbackMatchmake(placeId)
			hopBusy = false

			if not okFallback then
				notify("Server Hop Failed", "Teleport is blocked in this environment.", 5)
			end
		end
	}
end)()

-- FPS / Ping / Memory
local Stats = game:GetService("Stats")
local lastFrame = os.clock()
local fps = 0

local function getPingMs()
	-- Works on many clients; falls back gracefully
	local ok, ping = pcall(function()
		local net = Stats:FindFirstChild("Network")
		local ssv = net and net:FindFirstChild("ServerStatsItem")
		local dpi = ssv and ssv:FindFirstChild("Data Ping")
		local v = dpi and dpi:GetValue()
		return tonumber(v)
	end)
	if ok and ping then return math.floor(ping + 0.5) end
	return nil
end

local function getMemMb()
	local ok, mem = pcall(function()
		return Stats:GetTotalMemoryUsageMb()
	end)
	if ok and mem then return math.floor(mem + 0.5) end
	return nil
end

track(RunService.RenderStepped:Connect(function()
	local now = os.clock()
	local dt = now - lastFrame
	lastFrame = now
	if dt > 0 then fps = fps * 0.9 + (1/dt) * 0.1 end
end))

track(RunService.Heartbeat:Connect(function()
	if state.terminated then return end
	if not state.showPerfPanel then
		setRFLabel(perfPing, "Ping: -")
		setRFLabel(perfFps, "FPS: -")
		setRFLabel(perfMem, "Memory: -")
		return
	end

	local p = getPingMs()
	local m = getMemMb()

	setRFLabel(perfPing, "Ping: " .. (p and (tostring(p) .. " ms") or "-"))
	setRFLabel(perfFps, ("FPS: %.0f"):format(fps))
	setRFLabel(perfMem, "Memory: " .. (m and (tostring(m) .. " MB") or "-"))
end))

-- Rejoin on kick (best-effort via GuiService error message)
local GuiService = game:GetService("GuiService")
track(GuiService.ErrorMessageChanged:Connect(function()
	if state.terminated then return end
	if not state.rejoinOnKick then return end

	local msg = GuiService:GetErrorMessage() or ""
	msg = msg:lower()

	if msg:find("kicked") or msg:find("disconnected") or msg:find("connection") then
		pcall(function()
			TeleportService:Teleport(game.PlaceId, LocalPlayer)
		end)
	end
end))

-- Anti idle pro: small camera nudge + virtual user fallback
local VirtualUser = game:GetService("VirtualUser")

-- One handler only
track(LocalPlayer.Idled:Connect(function()
	if state.terminated then return end
	if not state.antiIdlePro then return end

	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
end))

-- Optional subtle nudge (kept minimal)
track(RunService.Heartbeat:Connect(function(dt)
	if state.terminated then return end
	if not state.antiIdlePro then return end

	state._antiIdleAcc = (state._antiIdleAcc or 0) + dt
	if state._antiIdleAcc < 20 then return end
	state._antiIdleAcc = 0

	pcall(function()
		Camera.CFrame = Camera.CFrame * CFrame.Angles(0, math.rad(0.25), 0)
	end)
end))

-- Buttons
Tabs.Utility:CreateButton({
	Name = "Rejoin Server",
	Callback = function()
		notify("Server", "Rejoining current server…", 3)
		task.wait(1.0)
		local ok = pcall(function()
			TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)
		end)
		if not ok then
			notify("Server", "Rejoin request was blocked in this environment.", 5)
		end
	end
})

Tabs.Utility:CreateButton({
	Name = "Server Hop (Random)",
	Callback = function()
		ServerHop:Hop(game.PlaceId, "random")
	end
})

if premium() then
	Tabs.Utility:CreateButton({
		Name = "Server Hop (Least Players)",
		Callback = function()
			ServerHop:Hop(game.PlaceId, "least")
		end
	})
end

Header(Tabs.Utility, "Info Panel")

-- UI
local infoPanel = Tabs.Utility:CreateParagraph({
	Title = "Info",
	Content = "Loading..."
})

local infoPlayerDropdown = Tabs.Utility:CreateDropdown({
	Name = "Player",
	Options = {"LocalPlayer"},
	CurrentOption = {state.infoSelectedPlayer ~= "" and state.infoSelectedPlayer or "LocalPlayer"},
	MultipleOptions = false,
	Flag = "InfoSelectedPlayer_Utility",
	Callback = function(opt)
		if type(opt) == "table" then opt = opt[1] end
		state.infoSelectedPlayer = tostring(opt or "LocalPlayer")
	end
})

Tabs.Utility:CreateToggle({
	Name = "Enabled",
	CurrentValue = true,
	Flag = "InfoEnabled_Utility",
	Callback = function(on)
		state.infoEnabled = on and true or false
	end
})

Tabs.Utility:CreateSlider({
	Name = "Refresh Rate",
	Range = {0.2, 2.0},
	Increment = 0.1,
	Suffix = "s",
	CurrentValue = state.infoRefreshRate or 0.5,
	Flag = "InfoRefreshRate_Utility",
	Callback = function(v)
		state.infoRefreshRate = v
	end
})

-- Logic
local Stats = game:GetService("Stats")
local lastFrame = os.clock()
local fps = 0

track(RunService.RenderStepped:Connect(function()
	local now = os.clock()
	local dt = now - lastFrame
	lastFrame = now
	if dt > 0 then fps = fps * 0.9 + (1/dt) * 0.1 end
end))

local function getPingMs()
	local ok, ping = pcall(function()
		local net = Stats:FindFirstChild("Network")
		local ssv = net and net:FindFirstChild("ServerStatsItem")
		local dpi = ssv and ssv:FindFirstChild("Data Ping")
		return dpi and tonumber(dpi:GetValue())
	end)
	if ok and ping then return math.floor(ping + 0.5) end
	return nil
end

local function getMemMb()
	local ok, mem = pcall(function() return Stats:GetTotalMemoryUsageMb() end)
	if ok and mem then return math.floor(mem + 0.5) end
	return nil
end

local function rebuildInfoPlayerOptions()
	local t = {"LocalPlayer"}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then table.insert(t, p.Name) end
	end
	table.sort(t, function(a,b)
		if a == "LocalPlayer" then return true end
		if b == "LocalPlayer" then return false end
		return a < b
	end)

	dropdownSetValues(infoPlayerDropdown, t)

	-- keep selection if possible
	local wanted = state.infoSelectedPlayer ~= "" and state.infoSelectedPlayer or "LocalPlayer"
	if not table.find(t, wanted) then
		state.infoSelectedPlayer = "LocalPlayer"
		dropdownSetCurrent(infoPlayerDropdown, "LocalPlayer")
	end
end

rebuildInfoPlayerOptions()
track(Players.PlayerAdded:Connect(function() task.defer(rebuildInfoPlayerOptions) end))
track(Players.PlayerRemoving:Connect(function() task.defer(rebuildInfoPlayerOptions) end))

local function getSelectedPlayer()
	if state.infoSelectedPlayer == "LocalPlayer" or state.infoSelectedPlayer == "" then
		return LocalPlayer
	end
	return Players:FindFirstChild(state.infoSelectedPlayer)
end

state.infoEnabled = (state.infoEnabled ~= false)
state.infoRefreshRate = state.infoRefreshRate or 0.5

track(RunService.Heartbeat:Connect(function(dt)
	if state.terminated then return end
	if not state.infoEnabled then return end

	state._infoPanelAcc = (state._infoPanelAcc or 0) + dt
	if state._infoPanelAcc < (state.infoRefreshRate or 0.5) then return end
	state._infoPanelAcc = 0

	-- FREE (always): server player count + FPS
	local serverLine = ("Server: %d/%d players"):format(#Players:GetPlayers(), Players.MaxPlayers)
	local perfLine = ("Performance: FPS %.0f"):format(fps)

	-- PREMIUM-ONLY: ping/memory/placeId/jobId/session time
	if premium() then
		local ping = getPingMs()
		local mem = getMemMb()

		local jobShort = tostring(game.JobId):sub(1,12) .. "…"
		local elapsed = os.clock() - (state.sessionStart or os.clock())
		local hh = math.floor(elapsed / 3600)
		local mm = math.floor((elapsed % 3600) / 60)
		local ss = math.floor(elapsed % 60)
		local session = ("%02d:%02d:%02d"):format(hh, mm, ss)

		serverLine = serverLine .. ("\nPlaceId: %d\nJobId: %s\nSession: %s"):format(game.PlaceId, jobShort, session)
		perfLine = perfLine .. (" | Ping %s | Mem %s"):format(
			ping and (tostring(ping).."ms") or "-",
			mem and (tostring(mem).."MB") or "-"
		)
	end

	local target = getSelectedPlayer()
	if not target then
		infoPanel:Set({
			Title = "Info",
			Content = serverLine .. "\n\n" .. perfLine .. "\n\nPlayer: (not found)"
		})
		return
	end

	local char = target.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local lroot = getRootOf(LocalPlayer)

	-- FREE (always): selected name + distance + velocity
	local dist = (root and lroot) and ("%.0fm"):format((root.Position - lroot.Position).Magnitude) or "-"
	local vel = (root and root.AssemblyLinearVelocity) and ("%.0f"):format(root.AssemblyLinearVelocity.Magnitude) or "-"

	local playerLine = ("Player: %s%s\nDistance: %s\nVelocity: %s studs/s")
		:format(target.Name, (target==LocalPlayer) and " (Local)" or "", dist, vel)

	-- PREMIUM-ONLY: team/health + local position details
	if premium() then
		local team = (target.Team and target.Team.Name) or "None"
		local hp = (hum and hum.MaxHealth) and ("%d/%d"):format(math.floor(hum.Health+0.5), math.floor(hum.MaxHealth+0.5)) or "-"

		playerLine = playerLine .. ("\nTeam: %s\nHealth: %s"):format(team, hp)

		if target == LocalPlayer and root then
			local v = root.AssemblyLinearVelocity
			playerLine = playerLine .. ("\n\nLocal:\nPos: %.0f, %.0f, %.0f\nVel: %.0f studs/s")
				:format(root.Position.X, root.Position.Y, root.Position.Z, v.Magnitude)
		end
	end

	infoPanel:Set({
		Title = "Info",
		Content = serverLine .. "\n\n" .. perfLine .. "\n\n" .. playerLine
	})
end))

Header(Tabs.Utility, "Anti-Idle")

-- One name, one toggle, one implementation
Tabs.Utility:CreateToggle({
	Name = "Anti-Idle",
	CurrentValue = (state.antiIdlePro == true), -- reuse existing saved value
	Flag = "AntiIdle",
	Callback = function(on)
		-- store into existing field to avoid changing your state table right now
		state.antiIdlePro = on and true or false
	end
})

--[[
Header(Tabs.Utility, "Diagnostics")

Tabs.Utility:CreateToggle({
	Name = "Show Performance Panel",
	CurrentValue = state.showPerfPanel,
	Flag = "ShowPerfPanel",
	Callback = function(on) state.showPerfPanel = on and true or false end
})

local perfPing = Tabs.Utility:CreateLabel("Ping: -")
local perfFps  = Tabs.Utility:CreateLabel("FPS: -")
local perfMem  = Tabs.Utility:CreateLabel("Memory: -")
]]--

if premium() then
	Header(Tabs.Utility, "Recovery")

	Tabs.Utility:CreateToggle({
		Name = "Rejoin on Kick",
		CurrentValue = state.rejoinOnKick,
		Flag = "RejoinOnKick",
		Callback = function(on)
			state.rejoinOnKick = on and true or false
		end
	})
end

--[[
Header(Tabs.Utility, "Anti Idle")

Tabs.Utility:CreateToggle({
	Name = "Anti Idle",
	CurrentValue = state.antiIdlePro,
	Flag = "AntiIdle",
	Callback = function(on) state.antiIdlePro = on and true or false end
})
]]--

--[[
Header(Tabs.Utility, "AFK")

local VirtualUser = game:GetService("VirtualUser")

Tabs.Utility:CreateToggle({
	Name = "Anti-AFK",
	CurrentValue = state.antiAfk,
	Flag = "AntiAfk",
	Callback = function(on) state.antiAfk = on and true or false end
})

track(LocalPlayer.Idled:Connect(function()
	if not state.antiAfk or state.terminated then return end
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
end))
]]--

--[[
Header(Tabs.Utility, "Info")

local utilServer = Tabs.Utility:CreateLabel("Server: -")
local utilSession = Tabs.Utility:CreateLabel("Session: -")
local utilPlr = Tabs.Utility:CreateLabel("Player: -")

Tabs.Utility:CreateButton({
	Name = "Reset Session Timer",
	Callback = function()
		state.sessionStart = os.clock()
	end
})

track(RunService.Heartbeat:Connect(function(dt)
	if state.terminated then return end

	state._utilAcc = (state._utilAcc or 0) + dt
	if state._utilAcc < 0.5 then return end
	state._utilAcc = 0

	local elapsed = os.clock() - (state.sessionStart or os.clock())
	local h = math.floor(elapsed / 3600)
	local m = math.floor((elapsed % 3600) / 60)
	local s = math.floor(elapsed % 60)

	setRFLabel(utilServer, ("Server: %d players | JobId: %s"):format(#Players:GetPlayers(), tostring(game.JobId):sub(1,12) .. "…"))

	setRFLabel(utilSession, ("Session: %02d:%02d:%02d"):format(h, m, s))

	local hum = getHumanoid()
	setRFLabel(utilPlr, ("Player: %s | HP: %d"):format(LocalPlayer.Name, hum and math.floor(hum.Health+0.5) or 0))
end))
]]--

Header(Tabs.Utility, "Performance")

local savedPerf = nil

local function applyFPSBoost(on)
	if on then
		if savedPerf then return end
		savedPerf = {
			GlobalShadows = Lighting.GlobalShadows,
			FogEnd = Lighting.FogEnd,
			Technology = Lighting.Technology,
			WaterWaveSize = Workspace.Terrain.WaterWaveSize,
			WaterWaveSpeed = Workspace.Terrain.WaterWaveSpeed,
			WaterReflectance = Workspace.Terrain.WaterReflectance,
			WaterTransparency = Workspace.Terrain.WaterTransparency
		}

		Lighting.GlobalShadows = false
		Lighting.FogEnd = 1e9
		pcall(function() Lighting.Technology = Enum.Technology.Compatibility end)

		Workspace.Terrain.WaterWaveSize = 0
		Workspace.Terrain.WaterWaveSpeed = 0
		Workspace.Terrain.WaterReflectance = 0
		Workspace.Terrain.WaterTransparency = 1
	else
		if not savedPerf then return end
		for k,v in pairs(savedPerf) do
			pcall(function()
				if k:find("^Water") then
					Workspace.Terrain[k] = v
				else
					Lighting[k] = v
				end
			end)
		end
		savedPerf = nil
	end
end

Tabs.Utility:CreateToggle({
	Name = "FPS Booster",
	CurrentValue = state.fpsBoost,
	Flag = "FPSBoost",
	Callback = function(on)
		state.fpsBoost = on and true or false
		applyFPSBoost(state.fpsBoost)
	end
})

Header(Tabs.Utility, "Terminate")

local terminateArmedUntil = 0
local function terminateAll()
	if state.terminated then return end
	state.terminated = true

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

	for _, plr in ipairs(Players:GetPlayers()) do restoreHitbox(plr) end

	pcall(stopESP)
	pcall(function()
		if espFolder then espFolder:Destroy() end
	end)

	for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
	table.clear(connections)

	pcall(function() Rayfield:Destroy() end)
end

Tabs.Utility:CreateButton({
	Name = "Reset and Close",
	Callback = function()
		local now = os.clock()
		if now < terminateArmedUntil then
			terminateAll()
			return
		end
		terminateArmedUntil = now + 6
		notify("Terminate", "Press again within 6 seconds to confirm.", 6)
	end
})

--========================
-- SETTINGS TAB
--========================
Header(Tabs.Settings, "Configuration") -- your Header() now uses CreateSection

local function rf_call(name, ...)
	if type(Rayfield) ~= "table" then return false, "Rayfield not table" end
	local fn = Rayfield[name]
	if type(fn) ~= "function" then return false, "Missing Rayfield:" .. tostring(name) end
	local ok, res = pcall(fn, Rayfield, ...)
	if not ok then return false, res end
	return true, res
end

local function config_path()
	-- Matches Rayfield defaults: FolderName + FileName + ".rfld"
	-- In your CreateWindow you used:
	-- FolderName = "AllGamesHub"
	-- FileName = "Config"
	return "Rayfield/Configurations/" .. "Config" .. ".rfld"
end

Tabs.Settings:CreateButton({
	Name = "Load Config",
	Callback = function()
		local ok, err = rf_call("LoadConfiguration")
		if ok then
			notify("Config", "Loaded.", 2)
		else
			notify("Config", "Load failed: " .. tostring(err), 5)
		end
	end
})

Tabs.Settings:CreateButton({
	Name = "Save Config",
	Callback = function()
		-- Some Rayfield builds expose this, some don't (auto-saves anyway)
		local ok, err = rf_call("SaveConfiguration")
		if ok then
			notify("Config", "Saved.", 2)
		else
			notify("Config", "Save not supported here (auto-save may still work).", 4)
		end
	end
})

Tabs.Settings:CreateButton({
	Name = "Reset Config File",
	Callback = function()
		local path = config_path()
		if typeof(delfile) == "function" then
			local ok, err = pcall(function() delfile(path) end)
			if ok then
				notify("Config", "Deleted config file. Press Load Config to reapply defaults.", 4)
			else
				notify("Config", "Delete failed: " .. tostring(err), 5)
			end
		else
			notify("Config", "delfile() not available in this executor.", 5)
		end
	end
})

Header(Tabs.Settings, "Preferences")

Tabs.Settings:CreateToggle({
	Name = "Disable Notifications",
	CurrentValue = state.disableNotifications,
	Flag = "DisableNotifications",
	Callback = function(on) state.disableNotifications = on and true or false end
})

--[[Tabs.Settings:CreateSlider({
	Name = "UI Scale",
	Range = {0.7, 1.5},
	Increment = 0.05,
	Suffix = "x",
	CurrentValue = state.uiScale,
	Flag = "UIScale",
	Callback = function(v)
		local ok = setRayfieldScale(v)
		if not ok then notify("UI", "Unable to locate Rayfield UI to scale.", 3, true) end
	end
})]]

Tabs.Settings:CreateDropdown({
	Name = "UI Theme",
	Options = {"Default", "AmberGlow", "Amethyst", "Bloom", "DarkBlue", "Green", "Light", "Ocean", "Serenity"},
	CurrentOption = {state.uiTheme},
	MultipleOptions = false,
	Flag = "UITheme",
	Callback = function(opt)
		if type(opt) == "table" then opt = opt[1] end
		state.uiTheme = tostring(opt or "Default")
		-- Best-effort: some Rayfield forks expose SetTheme / ChangeTheme
		local applied = false
		pcall(function()
			Window.ModifyTheme(state.uiTheme)
		end)
	end
})

Tabs.Settings:CreateButton({
	Name = "Reset All Settings",
	Callback = function()
		-- best-effort: remove config file if executor supports files
		local ok = false
		pcall(function()
			if typeof(delfile) == "function" then
				delfile("Rayfield/Configurations/Config.rfld")
				ok = true
			end
		end)
		if ok then
			notify("Settings", "Configuration reset. Reopen UI to apply defaults.", 4, true)
		else
			notify("Settings", "Reset not supported in this environment.", 4, true)
		end
	end
})

--[[Header(Tabs.Settings, "Player Info")

local function listPlayers()
	local t = {}
	for _, p in ipairs(Players:GetPlayers()) do table.insert(t, p.Name) end
	table.sort(t)
	return t
end

local infoDropdown = Tabs.Settings:CreateDropdown({
	Name = "Player",
	Options = listPlayers(),
	CurrentOption = {LocalPlayer.Name},
	MultipleOptions = false,
	Flag = "InfoPlayer",
	Callback = function(opt)
		if type(opt) == "table" then opt = opt[1] end
		state.infoSelectedPlayer = tostring(opt or "")
	end
})

setRFLabel(infoL1, "Name: " .. plr.Name)
setRFLabel(infoL2, "Team: " .. teamName)
setRFLabel(infoL3, "Health: " .. hp)
setRFLabel(infoL4, "Distance: " .. dist)
setRFLabel(infoL5, (plr == LocalPlayer and root) and string.format("Local: Pos(%.0f,%.0f,%.0f) Vel(%.0f)", root.Position.X, root.Position.Y, root.Position.Z, v.Magnitude) or "Local: -")

Tabs.Settings:CreateToggle({
	Name = "Auto Refresh",
	CurrentValue = state.infoAutoRefresh,
	Flag = "InfoAuto",
	Callback = function(on) state.infoAutoRefresh = on and true or false end
})

Tabs.Settings:CreateSlider({
	Name = "Refresh Rate",
	Range = {0.2, 2},
	Increment = 0.1,
	Suffix = "s",
	CurrentValue = state.infoRefreshRate,
	Flag = "InfoRate",
	Callback = function(v) state.infoRefreshRate = v end
})

Tabs.Settings:CreateButton({
	Name = "Refresh Now",
	Callback = function()
		-- force one update
		state._forceInfoRefresh = true
	end
})

-- Force first update on load
task.defer(function()
	state._forceInfoRefresh = true
end)

track(Players.PlayerAdded:Connect(function()
	dropdownSetValues(infoDropdown, listPlayers())
end))
track(Players.PlayerRemoving:Connect(function()
	dropdownSetValues(infoDropdown, listPlayers())
end))

track(RunService.Heartbeat:Connect(function(dt)
	if state.terminated then return end
	if not state.infoAutoRefresh and not state._forceInfoRefresh then return end

	state._infoAcc = (state._infoAcc or 0) + dt
	if not state._forceInfoRefresh and state._infoAcc < state.infoRefreshRate then return end
	state._infoAcc = 0
	state._forceInfoRefresh = false

	local name = state.infoSelectedPlayer ~= "" and state.infoSelectedPlayer or LocalPlayer.Name
	local plr = Players:FindFirstChild(name)
	if not plr then return end

	local hum = getHumanoidOf(plr)
	local root = getRootOf(plr)
	local lroot = getRootOf(LocalPlayer)

	local teamName = (plr.Team and plr.Team.Name) or "None"
	local hp = hum and (math.floor(hum.Health + 0.5) .. "/" .. math.floor(hum.MaxHealth + 0.5)) or "-"
	local dist = (root and lroot) and string.format("%.0fm", (root.Position - lroot.Position).Magnitude) or "-"

	infoL1.Text = "Name: " .. plr.Name
	infoL2.Text = "Team: " .. teamName
	infoL3.Text = "Health: " .. hp
	infoL4.Text = "Distance: " .. dist

	if plr == LocalPlayer and root then
		local v = root.AssemblyLinearVelocity
		infoL5.Text = string.format("Local: Pos(%.0f,%.0f,%.0f) Vel(%.0f)", root.Position.X, root.Position.Y, root.Position.Z, v.Magnitude)
	else
		infoL5.Text = "Local: -"
	end
end))
]]--

Header(Tabs.Settings, "UI") -- section

Tabs.Settings:CreateToggle({
	Name = "UI Visible",
	CurrentValue = true,
	Flag = "UIVisible",
	Callback = function(on)
		-- per docs: SetVisibility / IsVisible :contentReference[oaicite:2]{index=2}
		local ok, err = rf_call("SetVisibility", on)
		if not ok then
			notify("UI", "SetVisibility failed: " .. tostring(err), 5)
		end
	end
})

Tabs.Settings:CreateButton({
	Name = "Destroy UI",
	Callback = function()
		-- per docs: Destroy :contentReference[oaicite:3]{index=3}
		local ok, err = rf_call("Destroy")
		if not ok then
			notify("UI", "Destroy failed: " .. tostring(err), 5)
		end
	end
})

--========================
-- Initial refresh
--========================
task.defer(function()
	refreshWeaponDropdown(true)
	refreshTeamDropdown(true)
	refreshTargetDropdown(true)
	refreshSavedDropdown()
end)

Rayfield:LoadConfiguration()
