local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TeamColors = require(script.Parent.TeamColors)

local VehicleModuleManager = {}

local VEHICLES_FOLDER_NAME = "Vehicles"
local VMODULES_FOLDER_NAME = "VModules"
local DEFAULT_MODULE_NAME = "Cargo_low"

local function getVehiclesFolder()
	return ReplicatedStorage:FindFirstChild(VEHICLES_FOLDER_NAME)
end

local function getModulesFolder()
	local vehiclesFolder = getVehiclesFolder()
	if not vehiclesFolder then
		warn("[VehicleModuleManager] ReplicatedStorage.Vehicles not found")
		return nil
	end

	local modulesFolder = vehiclesFolder:FindFirstChild(VMODULES_FOLDER_NAME)
	if not modulesFolder then
		warn("[VehicleModuleManager] ReplicatedStorage.Vehicles.VModules not found")
		return nil
	end

	return modulesFolder
end

local function getMain(model)
	local main = model:FindFirstChild("Main", true)
	if main and main:IsA("BasePart") then
		return main
	end
	return nil
end

local function getTeamColorPart(model)
	local part = model:FindFirstChild("Team_color", true)
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function getMountedModulesFolder(vehicle)
	local folder = vehicle:FindFirstChild("MountedModules")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "MountedModules"
		folder.Parent = vehicle
	end
	return folder
end

local function splitCsv(text)
	local result = {}

	if typeof(text) ~= "string" then
		return result
	end

	for value in string.gmatch(text, "[^,]+") do
		local clean = string.gsub(value, "^%s+", "")
		clean = string.gsub(clean, "%s+$", "")

		if clean ~= "" then
			result[clean] = true
		end
	end

	return result
end

local function getSocketParts(vehicle)
	local sockets = {}

	for _, item in ipairs(vehicle:GetDescendants()) do
		if item:IsA("BasePart") and item:GetAttribute("Socket") == true then
			table.insert(sockets, item)
		end
	end

	table.sort(sockets, function(a, b)
		return a.Name < b.Name
	end)

	return sockets
end

local function isModuleAllowed(socket, moduleTemplate)
	local allowedTypes = splitCsv(socket:GetAttribute("AllowedModuleTypes"))
	local moduleType = moduleTemplate:GetAttribute("ModuleType")

	if moduleType == nil then
		warn("[VehicleModuleManager] Module has no ModuleType:", moduleTemplate.Name)
		return false
	end

	if next(allowedTypes) == nil then
		return true
	end

	return allowedTypes[tostring(moduleType)] == true
end

local function prepareModule(module)
	local main = getMain(module)
	if main then
		module.PrimaryPart = main
	end

	for _, item in ipairs(module:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.Massless = true
			item.AssemblyLinearVelocity = Vector3.zero
			item.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function paintModule(module, teamOwner)
	local colorPart = getTeamColorPart(module)
	if colorPart then
		colorPart.Color = TeamColors.GetColor(teamOwner or 0)
	end
end

local function copyCargoStatsToVehicle(vehicle, module)
	local moduleRole = module:GetAttribute("ModuleRole")
	if moduleRole ~= "Cargo" then
		return
	end

	local maxCargo = module:GetAttribute("Max_cargo")
	local currentCargo = module:GetAttribute("Current_cargo")

	if maxCargo ~= nil then
		vehicle:SetAttribute("Max_cargo", maxCargo)
	end

	if currentCargo ~= nil then
		vehicle:SetAttribute("Current_cargo", currentCargo)
	end
end

function VehicleModuleManager.AttachModule(vehicle, socket, moduleName, teamOwner)
	if not vehicle or not vehicle:IsA("Model") then
		warn("[VehicleModuleManager] AttachModule failed: vehicle is not a Model")
		return nil
	end

	if not socket or not socket:IsA("BasePart") then
		warn("[VehicleModuleManager] AttachModule failed: socket is not a BasePart")
		return nil
	end

	if socket:GetAttribute("Socket") ~= true then
		warn("[VehicleModuleManager] AttachModule failed: part is not a socket:", socket:GetFullName())
		return nil
	end

	if socket:GetAttribute("Occupied") == true then
		warn("[VehicleModuleManager] Socket already occupied:", socket.Name)
		return nil
	end

	local modulesFolder = getModulesFolder()
	if not modulesFolder then
		return nil
	end

	local template = modulesFolder:FindFirstChild(moduleName)
	if not template or not template:IsA("Model") then
		warn("[VehicleModuleManager] Module template not found:", tostring(moduleName))
		return nil
	end

	if template:GetAttribute("Module") ~= true then
		warn("[VehicleModuleManager] Template is not marked as Module:", template.Name)
		return nil
	end

	if not isModuleAllowed(socket, template) then
		warn("[VehicleModuleManager] Module not allowed:", template.Name, "Socket:", socket.Name)
		return nil
	end

	local module = template:Clone()
	module.Name = moduleName

	prepareModule(module)

	if not module.PrimaryPart then
		warn("[VehicleModuleManager] Module has no PrimaryPart/Main:", module.Name)
		module:Destroy()
		return nil
	end

	module.Parent = getMountedModulesFolder(vehicle)
	module:PivotTo(socket.CFrame)
	paintModule(module, teamOwner or vehicle:GetAttribute("TeamOwner") or 0)
	copyCargoStatsToVehicle(vehicle, module)

	local weld = Instance.new("WeldConstraint")
	weld.Name = "ModuleWeld"
	weld.Part0 = socket
	weld.Part1 = module.PrimaryPart
	weld.Parent = socket

	socket:SetAttribute("Occupied", true)
	socket:SetAttribute("CurrentModule", moduleName)
	module:SetAttribute("SocketName", socket:GetAttribute("SocketName") or socket.Name)
	module:SetAttribute("SocketPartName", socket.Name)

	print("[VehicleModuleManager] Module attached:", moduleName, "to", vehicle.Name, "socket", socket.Name)

	return module
end

function VehicleModuleManager.AttachDefaultModules(vehicle, teamOwner)
	if not vehicle or not vehicle:IsA("Model") then
		return
	end

	if vehicle:GetAttribute("VehicleType") == "Helicopter" then
		return
	end

	for _, socket in ipairs(getSocketParts(vehicle)) do
		if socket:GetAttribute("Occupied") ~= true then
			VehicleModuleManager.AttachModule(vehicle, socket, DEFAULT_MODULE_NAME, teamOwner)
		end
	end
end

return VehicleModuleManager
