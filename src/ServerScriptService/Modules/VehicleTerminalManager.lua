local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleSpawner = require(script.Parent.VehicleSpawner)
local WarehouseManager = require(script.Parent.WarehouseManager)
local VehicleCatalog = require(script.Parent.VehicleCatalog)
local VehicleAccess = require(script.Parent.VehicleAccess)

local VehicleTerminalManager = {}

local BASE_OBJECTS_FOLDER_NAME = "Base_objects"
local PROMPT_ACTION_TEXT = "Open"
local PROMPT_KEY = Enum.KeyCode.E

local startedRemoteListener = false

local function getBaseObjectsFolder()
	return Workspace:FindFirstChild(BASE_OBJECTS_FOLDER_NAME)
end

local function getRemotesFolder()
	return ReplicatedStorage:WaitForChild("Remotes")
end

local function getSpawnRemote()
	return getRemotesFolder():WaitForChild("VehicleSpawnRequest")
end

local function getTerminalConfig(object)
	if not object or not object:IsA("Model") then
		return nil
	end

	return VehicleCatalog.GetTerminalConfig(object:GetAttribute("ObjectType"))
end

local function getScreen(object)
	local screen = object:FindFirstChild("Screen", true)
	if screen and screen:IsA("BasePart") then
		return screen
	end
	return nil
end

local function getSpawnPart(object, config)
	if not config then
		return nil
	end

	local spawnPart = object:FindFirstChild(config.SpawnPartName, true)
	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart
	end

	return nil
end

local function canUseTerminal(player, terminal)
	local playerTeamOwner = VehicleAccess.GetPlayerTeamOwner(player)
	local terminalTeamOwner = terminal:GetAttribute("TeamOwner")

	if playerTeamOwner == nil or terminalTeamOwner == nil then
		return false
	end

	return tonumber(playerTeamOwner) == tonumber(terminalTeamOwner)
end

local function getVehicleTemplate(config, vehicleName)
	local folder = ReplicatedStorage:FindFirstChild(config.FolderName)
	if not folder then
		return nil
	end

	local template = folder:FindFirstChild(vehicleName)
	if template and template:IsA("Model") then
		return template
	end

	return nil
end

local function setupPrompt(object)
	local config = getTerminalConfig(object)
	if not config then
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
	prompt.ObjectText = config.PromptText or "Vehicle Terminal"
	prompt.KeyboardKeyCode = PROMPT_KEY
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = screen

	prompt.Triggered:Connect(function(player)
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

	if not terminal or not terminal:IsA("Model") or not terminal:IsDescendantOf(Workspace) then
		return
	end

	local config = getTerminalConfig(terminal)
	if not config then
		return
	end

	if not canUseTerminal(player, terminal) then
		return
	end

	if not VehicleCatalog.IsAllowed(terminal:GetAttribute("ObjectType"), vehicleName) then
		warn("[VehicleTerminalManager] Vehicle not allowed here:", vehicleName)
		return
	end

	local spawnPart = getSpawnPart(terminal, config)
	if not spawnPart then
		warn(
			"[VehicleTerminalManager] Spawn part not found:",
			config.SpawnPartName,
			terminal:GetFullName()
		)
		return
	end

	local template = getVehicleTemplate(config, vehicleName)
	if not template then
		warn(
			"[VehicleTerminalManager] Vehicle template not found:",
			config.FolderName,
			vehicleName
		)
		return
	end

	local price = tonumber(template:GetAttribute("VPrice")) or 0

	if not WarehouseManager.CanPayCargo(terminal, price) then
		warn("[VehicleTerminalManager] Not enough cargo for:", vehicleName, "Price:", price)
		return
	end

	if not WarehouseManager.PayCargo(terminal, price) then
		warn("[VehicleTerminalManager] Failed to pay cargo for:", vehicleName, "Price:", price)
		return
	end

	local teamOwner = terminal:GetAttribute("TeamOwner") or 0

	-- Для spawn-part використовуємо саме його Pivot.
	-- Це важливо для PSpawn, бо PivotOffset може бути навмисно зміщений.
	local spawnPivot = spawnPart:GetPivot()

	local vehicle = VehicleSpawner.SpawnVehicle(
		player,
		config.FolderName,
		vehicleName,
		spawnPivot,
		teamOwner
	)

	if not vehicle and price > 0 then
		warn("[VehicleTerminalManager] Spawn failed after payment:", vehicleName)
	end
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
	if startedRemoteListener then
		return
	end
	startedRemoteListener = true

	getSpawnRemote().OnServerEvent:Connect(function(player, terminal, vehicleName)
		spawnRequested(player, terminal, vehicleName)
	end)
end

return VehicleTerminalManager
