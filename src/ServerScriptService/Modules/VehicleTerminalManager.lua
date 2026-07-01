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
	if not object:IsA("Model") then
		return nil
	end

	local objectType = object:GetAttribute("ObjectType")
	return VehicleCatalog.GetTerminalConfig(objectType)
end

local function isKnownTerminal(object)
	return getTerminalConfig(object) ~= nil
end

local function getScreen(object)
	local screen = object:FindFirstChild("Screen", true)

	if screen and screen:IsA("BasePart") then
		return screen
	end

	return nil
end

local function getSpawnPart(object, spawnPartName)
	local spawnPart = object:FindFirstChild(spawnPartName, true)

	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart
	end

	return nil
end

local function getVehicleTemplate(folderName, vehicleName)
	local folder = ReplicatedStorage:FindFirstChild(folderName)

	if not folder then
		return nil
	end

	return folder:FindFirstChild(vehicleName)
end

local function getVehiclePrice(folderName, vehicleName)
	local template = getVehicleTemplate(folderName, vehicleName)

	if not template then
		return nil
	end

	return tonumber(template:GetAttribute("VPrice")) or 0
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
		print("[VehicleTerminal] Open requested by", player.Name, "Terminal:", object.Name)

		if not VehicleAccess.CanUseTeamObject(player, object) then
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

	local objectType = terminal:GetAttribute("ObjectType")
	local config = VehicleCatalog.GetTerminalConfig(objectType)

	if not config then
		warn("[VehicleTerminalManager] Unknown terminal ObjectType:", tostring(objectType))
		return
	end

	if not VehicleAccess.CanUseTeamObject(player, terminal) then
		return
	end

	if not VehicleCatalog.IsAllowed(objectType, vehicleName) then
		warn(
			"[VehicleTerminalManager] Vehicle not allowed:",
			vehicleName,
			"TerminalType:",
			tostring(objectType)
		)
		return
	end

	local spawnPart = getSpawnPart(terminal, config.SpawnPartName)

	if not spawnPart then
		warn(
			"[VehicleTerminalManager] Spawn part not found:",
			config.SpawnPartName,
			"Terminal:",
			terminal:GetFullName()
		)
		return
	end

	local price = getVehiclePrice(config.FolderName, vehicleName)

	if price == nil then
		warn(
			"[VehicleTerminalManager] Vehicle template not found:",
			config.FolderName,
			vehicleName
		)
		return
	end

	if not WarehouseManager.CanPayCargo(terminal, price) then
		warn("[VehicleTerminalManager] Not enough cargo for vehicle:", vehicleName, "Price:", price)
		return
	end

	if not WarehouseManager.PayCargo(terminal, price) then
		warn("[VehicleTerminalManager] Failed to pay cargo for vehicle:", vehicleName, "Price:", price)
		return
	end

	local teamOwner = terminal:GetAttribute("TeamOwner") or 0

	VehicleSpawner.SpawnVehicle(
		player,
		config.FolderName,
		vehicleName,
		spawnPart.CFrame,
		teamOwner
	)
end

function VehicleTerminalManager.SetupAll()
	local folder = getBaseObjectsFolder()

	if not folder then
		warn("[VehicleTerminalManager] Workspace.Base_objects not found")
		return
	end

	for _, object in ipairs(folder:GetChildren()) do
		if isKnownTerminal(object) then
			setupPrompt(object)
		end
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

		if isKnownTerminal(child) then
			setupPrompt(child)
		end
	end)
end

function VehicleTerminalManager.StartRemoteListener()
	getSpawnRemote().OnServerEvent:Connect(function(player, terminal, vehicleName)
		spawnRequested(player, terminal, vehicleName)
	end)
end

return VehicleTerminalManager