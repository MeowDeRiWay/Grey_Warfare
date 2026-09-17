local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TeamColors = require(script.Parent.TeamColors)

local VehicleModuleManager = {}

local VEHICLE_FOLDER_NAMES = {
	"Vehicles",
	"Heli",
	"Planes",
}

local MODULE_FOLDER_BY_FAMILY = {
	Vehicles = "VModules",
	Heli = "HModules",
	Planes = "PModules",
}
local DEFAULT_MODULE_NAME = "Cargo_low"


-- Module alignment helpers
local function getNumberAttr(primary, secondary, name, default)
	local value = primary and primary:GetAttribute(name)
	if value == nil and secondary then
		value = secondary:GetAttribute(name)
	end
	if value == nil then
		return default
	end
	return tonumber(value) or default
end

local function getModuleFolders()
	local result = {}
	local seen = {}

	local function addFolder(folder)
		if folder
			and folder:IsA("Folder")
			and not seen[folder]
		then
			seen[folder] = true
			table.insert(result, folder)
		end
	end

	for _, folderName in ipairs(VEHICLE_FOLDER_NAMES) do
		local familyFolder = ReplicatedStorage:FindFirstChild(folderName)
		if familyFolder and familyFolder:IsA("Folder") then
			local moduleFolderName = MODULE_FOLDER_BY_FAMILY[folderName]
			if moduleFolderName then
				addFolder(familyFolder:FindFirstChild(moduleFolderName))
			end
		end
	end

	return result
end


local function getMain(model)
	local main = model:FindFirstChild("Main", true)
	if main and main:IsA("BasePart") then
		return main
	end
	return nil
end

local function getHostMainForSocket(socket, vehicle)
	local current = socket.Parent

	while current and current ~= game do
		if current:IsA("Model") then
			-- Prefer a DIRECT Main. This avoids accidentally taking Main
			-- from some already-mounted child module.
			local directMain = current:FindFirstChild("Main")
			if directMain and directMain:IsA("BasePart") then
				return directMain
			end

			if current == vehicle then
				break
			end
		end

		current = current.Parent
	end

	-- Final fallback: vehicle Main.
	return getMain(vehicle)
end

local function buildTargetMainCFrame(vehicle, socket, module)
	local hostMain = getHostMainForSocket(socket, vehicle)

	if not hostMain then
		warn(
			"[VehicleModuleManager] Host Main not found for socket:",
			socket:GetFullName()
		)
		return socket.CFrame
	end

	-- FINAL STANDARD:
	-- Socket gives POSITION only.
	-- Host Main gives ORIENTATION.
	--
	-- This means a neutral Main on every module will always inherit the
	-- same upright/forward orientation as the vehicle (or parent module),
	-- regardless of a socket Part's own accidental rotation.
	local target =
		CFrame.new(socket.Position)
		* hostMain.CFrame.Rotation

	-- Optional per-socket/module fine tuning, normally leave all at 0.
	local x = getNumberAttr(socket, module, "Mount_offset_x", 0)
	local y = getNumberAttr(socket, module, "Mount_offset_y", 0)
	local z = getNumberAttr(socket, module, "Mount_offset_z", 0)

	local pitch = math.rad(getNumberAttr(socket, module, "Mount_pitch", 0))
	local yaw = math.rad(getNumberAttr(socket, module, "Mount_yaw", 0))
	local roll = math.rad(getNumberAttr(socket, module, "Mount_roll", 0))

	return target
		* CFrame.new(x, y, z)
		* CFrame.Angles(pitch, yaw, roll)
end

local function pivotModuleByMain(module, main, targetMainCFrame)
	-- Move the WHOLE module by the delta from its actual Main CFrame.
	-- This intentionally ignores Model.WorldPivot / imported pivot quirks.
	local currentPivot = module:GetPivot()
	local delta = targetMainCFrame * main.CFrame:Inverse()
	module:PivotTo(delta * currentPivot)
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

local function getSocketName(socket)
	return tostring(socket:GetAttribute("SocketName") or socket.Name)
end

local function getSocketParts(model)
	local sockets = {}

	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") and item:GetAttribute("Socket") == true then
			table.insert(sockets, item)
		end
	end

	table.sort(sockets, function(a, b)
		return getSocketName(a) < getSocketName(b)
	end)

	return sockets
end

local function findSocketByName(model, socketName)
	for _, socket in ipairs(getSocketParts(model)) do
		if socket.Name == socketName or getSocketName(socket) == socketName then
			return socket
		end
	end
	return nil
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

local function getTemplate(moduleName)
	for _, modulesFolder in ipairs(getModuleFolders()) do
		local template = modulesFolder:FindFirstChild(moduleName)

		if template and template:IsA("Model") then
			return template
		end
	end

	warn(
		"[VehicleModuleManager] Module template not found in any VModules folder:",
		tostring(moduleName)
	)
	return nil
end

function VehicleModuleManager.GetSocketParts(model)
	return getSocketParts(model)
end

function VehicleModuleManager.FindSocketByName(model, socketName)
	return findSocketByName(model, socketName)
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

	local template = getTemplate(moduleName)
	if not template then
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

	-- Final standardized mount:
	-- place the module by its actual Main, not by Model pivot,
	-- using socket position and the host Main orientation.
	local moduleMain = module.PrimaryPart
	local targetMainCFrame = buildTargetMainCFrame(vehicle, socket, module)
	pivotModuleByMain(module, moduleMain, targetMainCFrame)

	local finalTeamOwner = teamOwner or vehicle:GetAttribute("TeamOwner") or 0
	module:SetAttribute("TeamOwner", finalTeamOwner)
	paintModule(module, finalTeamOwner)

	local weld = Instance.new("WeldConstraint")
	weld.Name = "ModuleWeld"
	weld.Part0 = socket
	weld.Part1 = module.PrimaryPart
	weld.Parent = socket

	socket:SetAttribute("Occupied", true)
	socket:SetAttribute("CurrentModule", moduleName)
	module:SetAttribute("SocketName", getSocketName(socket))
	module:SetAttribute("SocketPartName", socket.Name)

	local hostMain = getHostMainForSocket(socket, vehicle)
	print(
		"[VehicleModuleManager] Module attached:",
		moduleName,
		"to",
		vehicle.Name,
		"socket",
		socket.Name,
		"| orientation source:",
		hostMain and hostMain:GetFullName() or "NONE",
		"| socket rotation ignored"
	)

	return module
end

local function getDirectChildrenForPath(config, parentPath)
	local result = {}
	local prefix = ""

	if parentPath and parentPath ~= "" then
		prefix = parentPath .. "/"
	end

	for path, moduleName in pairs(config or {}) do
		if typeof(path) == "string" and string.sub(path, 1, #prefix) == prefix then
			local rest = string.sub(path, #prefix + 1)
			if rest ~= "" and not string.find(rest, "/", 1, true) then
				result[rest] = moduleName
			end
		end
	end

	return result
end

local function attachConfiguredRecursive(vehicle, hostModel, config, parentPath, teamOwner)
	local childConfig = getDirectChildrenForPath(config, parentPath)

	for socketName, moduleName in pairs(childConfig) do
		local socket = findSocketByName(hostModel, socketName)
		if socket and socket:GetAttribute("Occupied") ~= true then
			local module = VehicleModuleManager.AttachModule(vehicle, socket, moduleName, teamOwner)
			if module then
				local nextPath = socketName
				if parentPath and parentPath ~= "" then
					nextPath = parentPath .. "/" .. socketName
				end
				attachConfiguredRecursive(vehicle, module, config, nextPath, teamOwner)
			end
		end
	end
end

function VehicleModuleManager.AttachConfiguredModules(vehicle, config, teamOwner)
	if not vehicle or not vehicle:IsA("Model") then
		return
	end

	-- Ground, helicopter and plane all use the same socket/config pipeline.
	attachConfiguredRecursive(vehicle, vehicle, config or {}, "", teamOwner)
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

print("[VehicleModuleManager] Unified module sources enabled: Vehicles/VModules + Heli/HModules + Planes/PModules")

return VehicleModuleManager
