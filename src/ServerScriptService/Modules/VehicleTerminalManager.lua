local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleSpawner = require(script.Parent.VehicleSpawner)

local VehicleTerminalManager = {}

local BASE_OBJECTS_FOLDER_NAME = "Base_objects"

local PROMPT_ACTION_TEXT = "Open"
local PROMPT_OBJECT_TEXT = "Vehicle Terminal"
local PROMPT_KEY = Enum.KeyCode.E

local function getBaseObjectsFolder()
	return Workspace:FindFirstChild(BASE_OBJECTS_FOLDER_NAME)
end

local function getRemotesFolder()
	return ReplicatedStorage:WaitForChild("Remotes")
end

local function getSpawnRemote()
	return getRemotesFolder():WaitForChild("VehicleSpawnRequest")
end

local function isVehicleTerminal(object)
	return object:IsA("Model") and object:GetAttribute("ObjectType") == "VehicleTerminal"
end

local function getScreen(object)
	local screen = object:FindFirstChild("Screen", true)

	if screen and screen:IsA("BasePart") then
		return screen
	end

	return nil
end

local function getWSpawn(object)
	local spawnPart = object:FindFirstChild("WSpawn", true)

	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart
	end

	return nil
end

local function getPlayerTeamOwner(player)
	local attr = player:GetAttribute("TeamOwner")
	if attr ~= nil then
		return attr
	end

	local teamValue = player:GetAttribute("Team")
	if teamValue ~= nil then
		return teamValue
	end

	if player.Team then
		local teamAttr = player.Team:GetAttribute("TeamOwner")
		if teamAttr ~= nil then
			return teamAttr
		end

		local teamNumber = tonumber(player.Team.Name)
		if teamNumber then
			return teamNumber
		end

		local lowerName = string.lower(player.Team.Name)

		if lowerName == "red" or lowerName == "червоні" or lowerName == "червона" then
			return 1
		end

		if lowerName == "blue" or lowerName == "сині" or lowerName == "синя" then
			return 2
		end
	end

	return nil
end

local function canUseTerminal(player, terminal)
	local playerTeamOwner = getPlayerTeamOwner(player)
	local terminalTeamOwner = terminal:GetAttribute("TeamOwner")

	if terminalTeamOwner == nil then
		warn("[VehicleTerminalManager] Terminal has no TeamOwner:", terminal:GetFullName())
		return false
	end

	if playerTeamOwner == nil then
		warn("[VehicleTerminalManager] Player has no TeamOwner:", player.Name)
		return false
	end

	if tonumber(playerTeamOwner) ~= tonumber(terminalTeamOwner) then
		warn(
			"[VehicleTerminalManager] Wrong team terminal denied:",
			player.Name,
			"PlayerTeamOwner:",
			playerTeamOwner,
			"TerminalTeamOwner:",
			terminalTeamOwner
		)

		return false
	end

	return true
end

local function setupPrompt(object)
	if not isVehicleTerminal(object) then
		return
	end

	local screen = getScreen(object)

	if not screen then
		warn("[VehicleTerminalManager] Screen not found:", object:GetFullName())
		return
	end

	local oldPrompt = screen:FindFirstChild("VehicleTerminalPrompt")
	if oldPrompt then
		oldPrompt:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "VehicleTerminalPrompt"
	prompt.ActionText = PROMPT_ACTION_TEXT
	prompt.ObjectText = PROMPT_OBJECT_TEXT
	prompt.KeyboardKeyCode = PROMPT_KEY
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = screen

	prompt.Triggered:Connect(function(player)
		print("[VehicleTerminal] Open requested by", player.Name)

		if not canUseTerminal(player, object) then
			return
		end

		getSpawnRemote():FireClient(player, "OpenMenu", object)
	end)
end

local function spawnRequested(player, terminal, vehicleName)
	if typeof(vehicleName) ~= "string" then
		return
	end

	if not terminal or not terminal:IsA("Model") then
		return
	end

	if not terminal:IsDescendantOf(Workspace) then
		return
	end

	if not isVehicleTerminal(terminal) then
		return
	end

	if not canUseTerminal(player, terminal) then
		return
	end

	if vehicleName ~= "Cargo" then
		warn("[VehicleTerminalManager] Unknown vehicle requested:", vehicleName)
		return
	end

	local spawnPart = getWSpawn(terminal)

	if not spawnPart then
		warn("[VehicleTerminalManager] WSpawn not found:", terminal:GetFullName())
		return
	end

	local teamOwner = terminal:GetAttribute("TeamOwner") or 0

	VehicleSpawner.SpawnVehicle(player, vehicleName, spawnPart.CFrame, teamOwner)
end

function VehicleTerminalManager.SetupAll()
	local folder = getBaseObjectsFolder()

	if not folder then
		warn("[VehicleTerminalManager] Workspace.Base_objects not found")
		return
	end

	for _, object in ipairs(folder:GetChildren()) do
		setupPrompt(object)
	end
end

function VehicleTerminalManager.StartAutoSetup()
	local folder = getBaseObjectsFolder()

	if not folder then
		warn("[VehicleTerminalManager] Workspace.Base_objects not found")
		return
	end

	folder.ChildAdded:Connect(function(child)
		task.wait(0.1)
		setupPrompt(child)
	end)
end

function VehicleTerminalManager.StartRemoteListener()
	getSpawnRemote().OnServerEvent:Connect(function(player, terminal, vehicleName)
		spawnRequested(player, terminal, vehicleName)
	end)
end


return VehicleTerminalManager