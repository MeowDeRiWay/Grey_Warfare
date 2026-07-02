local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleAccess = require(script.Parent.VehicleAccess)
local VehicleConfigManager = require(script.Parent.VehicleConfigManager)

local LabTerminalManager = {}

local BASE_OBJECTS_FOLDER_NAME = "Base_objects"
local VEHICLES_FOLDER_NAME = "Vehicles"
local VMODULES_FOLDER_NAME = "VModules"
local REMOTE_NAME = "LabTerminalRemote"

local PROMPT_ACTION_TEXT = "Open"
local PROMPT_KEY = Enum.KeyCode.E

local function getBaseObjectsFolder()
	return Workspace:FindFirstChild(BASE_OBJECTS_FOLDER_NAME)
end

local function getRemotesFolder()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	return folder
end

local function getRemote()
	local remotes = getRemotesFolder()
	local remote = remotes:FindFirstChild(REMOTE_NAME)

	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = REMOTE_NAME
		remote.Parent = remotes
	end

	return remote
end

local function getVehiclesFolder()
	return ReplicatedStorage:FindFirstChild(VEHICLES_FOLDER_NAME)
end

local function getModulesFolder()
	local vehiclesFolder = getVehiclesFolder()
	if not vehiclesFolder then
		return nil
	end
	return vehiclesFolder:FindFirstChild(VMODULES_FOLDER_NAME)
end

local function getScreen(object)
	local screen = object:FindFirstChild("Screen", true)
	if screen and screen:IsA("BasePart") then
		return screen
	end
	return nil
end

local function isLabTerminal(object)
	return object:IsA("Model") and object:GetAttribute("ObjectType") == "LabTerminal"
end

local function canUseLab(player, lab)
	local teamOwner = lab:GetAttribute("TeamOwner")
	if teamOwner == nil or tonumber(teamOwner) == 0 then
		return true
	end
	return VehicleAccess.CanUseTeamObject(player, lab)
end

local function splitCsvToList(text)
	local result = {}
	if typeof(text) ~= "string" then
		return result
	end

	for value in string.gmatch(text, "[^,]+") do
		local clean = string.gsub(value, "^%s+", "")
		clean = string.gsub(clean, "%s+$", "")
		if clean ~= "" then
			table.insert(result, clean)
		end
	end

	return result
end

local function getSocketName(socket)
	return tostring(socket:GetAttribute("SocketName") or socket.Name)
end

local function collectSockets(model)
	local sockets = {}

	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") and item:GetAttribute("Socket") == true then
			table.insert(sockets, {
				Name = getSocketName(item),
				PartName = item.Name,
				AllowedModuleTypes = item:GetAttribute("AllowedModuleTypes") or "",
				AllowedTypes = splitCsvToList(item:GetAttribute("AllowedModuleTypes") or ""),
			})
		end
	end

	table.sort(sockets, function(a, b)
		return a.Name < b.Name
	end)

	return sockets
end

local function buildVehicleList()
	local result = {}
	local vehiclesFolder = getVehiclesFolder()
	if not vehiclesFolder then
		return result
	end

	for _, item in ipairs(vehiclesFolder:GetChildren()) do
		if item:IsA("Model") then
			table.insert(result, {
				Name = item.Name,
				DisplayName = item:GetAttribute("DisplayName") or item.Name,
				Sockets = collectSockets(item),
			})
		end
	end

	table.sort(result, function(a, b)
		return a.Name < b.Name
	end)

	return result
end

local function buildModuleList()
	local result = {}
	local modulesFolder = getModulesFolder()
	if not modulesFolder then
		return result
	end

	for _, item in ipairs(modulesFolder:GetChildren()) do
		if item:IsA("Model") and item:GetAttribute("Module") == true then
			table.insert(result, {
				Name = item.Name,
				DisplayName = item:GetAttribute("DisplayName") or item.Name,
				ModuleRole = item:GetAttribute("ModuleRole") or "",
				ModuleType = item:GetAttribute("ModuleType") or item.Name,
				Sockets = collectSockets(item),
			})
		end
	end

	table.sort(result, function(a, b)
		return a.Name < b.Name
	end)

	return result
end

local function sendData(player)
	getRemote():FireClient(player, "Data", {
		Vehicles = buildVehicleList(),
		Modules = buildModuleList(),
		Configs = VehicleConfigManager.GetAllConfigs(player),
	})
end

local function setupPrompt(object)
	local screen = getScreen(object)
	if not screen then
		warn("[LabTerminalManager] Screen not found:", object:GetFullName())
		return
	end

	local oldPrompt = screen:FindFirstChild("LabTerminalPrompt")
	if oldPrompt then
		oldPrompt:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LabTerminalPrompt"
	prompt.ActionText = PROMPT_ACTION_TEXT
	prompt.ObjectText = "Lab Terminal"
	prompt.KeyboardKeyCode = PROMPT_KEY
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = screen

	prompt.Triggered:Connect(function(player)
		if not canUseLab(player, object) then
			return
		end

		getRemote():FireClient(player, "Open")
		sendData(player)
	end)
end

local function registerObject(object)
	if isLabTerminal(object) then
		setupPrompt(object)
	end
end

function LabTerminalManager.SetupAll()
	local folder = getBaseObjectsFolder()
	if not folder then
		warn("[LabTerminalManager] Workspace.Base_objects not found")
		return
	end

	for _, object in ipairs(folder:GetChildren()) do
		registerObject(object)
	end
end

function LabTerminalManager.StartAutoSetup()
	local folder = getBaseObjectsFolder()
	if not folder then
		warn("[LabTerminalManager] Workspace.Base_objects not found")
		return
	end

	folder.ChildAdded:Connect(function(child)
		task.wait(0.1)
		registerObject(child)
	end)
end

function LabTerminalManager.StartRemoteListener()
	getRemote().OnServerEvent:Connect(function(player, action, vehicleName, socketPath, moduleName)
		if action == "RequestData" then
			sendData(player)
			return
		end

		if action == "SetModule" then
			local ok = VehicleConfigManager.SetModule(player, vehicleName, socketPath, moduleName)
			if ok then
				sendData(player)
			end
			return
		end
	end)
end

return LabTerminalManager
