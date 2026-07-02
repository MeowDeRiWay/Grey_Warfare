local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local labRemote = remotes:WaitForChild("LabTerminalRemote")

local data = {
	Vehicles = {},
	Modules = {},
	Configs = {},
}

local selectedVehicleName = nil
local selectedSocketPath = nil

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LabTerminalGui"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
root.Size = UDim2.fromScale(0.78, 0.72)
root.BackgroundTransparency = 0.08
root.BorderSizePixel = 1
root.Parent = screenGui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(12, 8)
title.Size = UDim2.new(1, -24, 0, 34)
title.Font = Enum.Font.SourceSansBold
title.TextSize = 26
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Lab Terminal"
title.Parent = root

local vehiclesFrame = Instance.new("ScrollingFrame")
vehiclesFrame.Name = "Vehicles"
vehiclesFrame.Position = UDim2.fromOffset(12, 52)
vehiclesFrame.Size = UDim2.new(0.27, -18, 1, -112)
vehiclesFrame.CanvasSize = UDim2.fromOffset(0, 0)
vehiclesFrame.ScrollBarThickness = 8
vehiclesFrame.BackgroundTransparency = 0.15
vehiclesFrame.Parent = root

local socketsFrame = Instance.new("ScrollingFrame")
socketsFrame.Name = "Sockets"
socketsFrame.Position = UDim2.new(0.27, 6, 0, 52)
socketsFrame.Size = UDim2.new(0.37, -18, 1, -112)
socketsFrame.CanvasSize = UDim2.fromOffset(0, 0)
socketsFrame.ScrollBarThickness = 8
socketsFrame.BackgroundTransparency = 0.15
socketsFrame.Parent = root

local modulesFrame = Instance.new("ScrollingFrame")
modulesFrame.Name = "Modules"
modulesFrame.Position = UDim2.new(0.64, 6, 0, 52)
modulesFrame.Size = UDim2.new(0.36, -18, 1, -112)
modulesFrame.CanvasSize = UDim2.fromOffset(0, 0)
modulesFrame.ScrollBarThickness = 8
modulesFrame.BackgroundTransparency = 0.15
modulesFrame.Parent = root

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(0.5, 1)
closeButton.Position = UDim2.new(0.5, 0, 1, -12)
closeButton.Size = UDim2.fromOffset(260, 42)
closeButton.Font = Enum.Font.SourceSansBold
closeButton.TextSize = 24
closeButton.Text = "Close"
closeButton.Parent = root

local function clearFrame(frame)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function makeButton(parent, text, y, height)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, -12, 0, height or 34)
	button.Position = UDim2.fromOffset(6, y)
	button.Font = Enum.Font.SourceSans
	button.TextSize = 18
	button.TextXAlignment = Enum.TextXAlignment.Left
	button.Text = "  " .. text
	button.Parent = parent
	return button
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

local function getVehicleByName(vehicleName)
	for _, vehicle in ipairs(data.Vehicles or {}) do
		if vehicle.Name == vehicleName then
			return vehicle
		end
	end
	return nil
end

local function getModuleByName(moduleName)
	for _, module in ipairs(data.Modules or {}) do
		if module.Name == moduleName then
			return module
		end
	end
	return nil
end

local function isModuleAllowed(socketInfo, moduleInfo)
	local allowed = splitCsv(socketInfo.AllowedModuleTypes or "")
	if next(allowed) == nil then
		return true
	end
	return allowed[tostring(moduleInfo.ModuleType)] == true
end

local function getVehicleConfig(vehicleName)
	data.Configs = data.Configs or {}
	data.Configs[vehicleName] = data.Configs[vehicleName] or {}
	return data.Configs[vehicleName]
end

local function pathJoin(parentPath, socketName)
	if parentPath == nil or parentPath == "" then
		return socketName
	end
	return parentPath .. "/" .. socketName
end

local function addSocketRows(rows, hostName, sockets, parentPath, level, config)
	for _, socket in ipairs(sockets or {}) do
		local socketPath = pathJoin(parentPath, socket.Name)
		local currentModule = config[socketPath]

		table.insert(rows, {
			Socket = socket,
			Path = socketPath,
			Level = level,
			CurrentModule = currentModule,
			HostName = hostName,
		})

		if currentModule then
			local moduleInfo = getModuleByName(currentModule)
			if moduleInfo and moduleInfo.Sockets and #moduleInfo.Sockets > 0 then
				addSocketRows(rows, currentModule, moduleInfo.Sockets, socketPath, level + 1, config)
			end
		end
	end
end

local renderAll

local function renderVehicles()
	clearFrame(vehiclesFrame)

	local y = 6
	for _, vehicle in ipairs(data.Vehicles or {}) do
		local prefix = ""
		if vehicle.Name == selectedVehicleName then
			prefix = "> "
		end

		local button = makeButton(vehiclesFrame, prefix .. vehicle.DisplayName, y, 36)
		button.MouseButton1Click:Connect(function()
			selectedVehicleName = vehicle.Name
			selectedSocketPath = nil
			renderAll()
		end)
		y += 40
	end

	vehiclesFrame.CanvasSize = UDim2.fromOffset(0, y + 6)
end

local socketRows = {}

local function renderSockets()
	clearFrame(socketsFrame)
	socketRows = {}

	if not selectedVehicleName then
		local b = makeButton(socketsFrame, "Select vehicle", 6, 36)
		b.AutoButtonColor = false
		socketsFrame.CanvasSize = UDim2.fromOffset(0, 50)
		return
	end

	local vehicle = getVehicleByName(selectedVehicleName)
	if not vehicle then
		return
	end

	local config = getVehicleConfig(selectedVehicleName)
	addSocketRows(socketRows, selectedVehicleName, vehicle.Sockets, "", 0, config)

	local y = 6
	for _, row in ipairs(socketRows) do
		local indent = string.rep("    ", row.Level)
		local current = row.CurrentModule or "empty"
		local prefix = ""
		if row.Path == selectedSocketPath then
			prefix = "> "
		end

		local text = string.format("%s%s%s  [%s]", indent, prefix, row.Socket.Name, current)
		local button = makeButton(socketsFrame, text, y, 36)
		button.MouseButton1Click:Connect(function()
			selectedSocketPath = row.Path
			renderAll()
		end)
		y += 40
	end

	socketsFrame.CanvasSize = UDim2.fromOffset(0, y + 6)
end

local function getSelectedSocketRow()
	for _, row in ipairs(socketRows) do
		if row.Path == selectedSocketPath then
			return row
		end
	end
	return nil
end

local function renderModules()
	clearFrame(modulesFrame)

	if not selectedVehicleName then
		local b = makeButton(modulesFrame, "Select vehicle first", 6, 36)
		b.AutoButtonColor = false
		modulesFrame.CanvasSize = UDim2.fromOffset(0, 50)
		return
	end

	local row = getSelectedSocketRow()
	if not row then
		local b = makeButton(modulesFrame, "Select socket", 6, 36)
		b.AutoButtonColor = false
		modulesFrame.CanvasSize = UDim2.fromOffset(0, 50)
		return
	end

	local y = 6
	for _, moduleInfo in ipairs(data.Modules or {}) do
		if isModuleAllowed(row.Socket, moduleInfo) then
			local currentMark = ""
			if row.CurrentModule == moduleInfo.Name then
				currentMark = "✓ "
			end

			local text = string.format("%s%s  (%s)", currentMark, moduleInfo.DisplayName, moduleInfo.ModuleType)
			local button = makeButton(modulesFrame, text, y, 38)
			button.MouseButton1Click:Connect(function()
				local config = getVehicleConfig(selectedVehicleName)
				config[selectedSocketPath] = moduleInfo.Name
				labRemote:FireServer("SetModule", selectedVehicleName, selectedSocketPath, moduleInfo.Name)
				renderAll()
			end)
			y += 42
		end
	end

	if y == 6 then
		local b = makeButton(modulesFrame, "No compatible modules", y, 36)
		b.AutoButtonColor = false
		y += 40
	end

	modulesFrame.CanvasSize = UDim2.fromOffset(0, y + 6)
end

function renderAll()
	local vehicleTitle = selectedVehicleName or "no vehicle"
	title.Text = "Lab Terminal — " .. vehicleTitle
	renderVehicles()
	renderSockets()
	renderModules()
end

labRemote.OnClientEvent:Connect(function(action, payload)
	if action == "Open" then
		screenGui.Enabled = true
		labRemote:FireServer("RequestData")
		return
	end

	if action == "Data" then
		data = payload or data
		if not selectedVehicleName and data.Vehicles and data.Vehicles[1] then
			selectedVehicleName = data.Vehicles[1].Name
		end
		renderAll()
		return
	end
end)

closeButton.MouseButton1Click:Connect(function()
	screenGui.Enabled = false
	selectedSocketPath = nil
end)
