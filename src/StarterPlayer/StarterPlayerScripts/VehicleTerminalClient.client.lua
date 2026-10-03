local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local vehicleSpawnRemote = remotes:WaitForChild("VehicleSpawnRequest")

local currentTerminal = nil
local vehicleCount = 0
local PANEL_WIDTH = 340
local HEADER_HEIGHT = 55
local FOOTER_HEIGHT = 65
local BUTTON_HEIGHT = 48
local BUTTON_GAP = 10
local SCREEN_MARGIN = 20

local VEHICLE_BUTTONS = {
	VehicleTerminal = {
		Title = "Vehicle Terminal",
		Vehicles = {
			{ Name = "Car", Text = "Spawn Car" },
			{ Name = "Truck", Text = "Spawn Truck" },
			{ Name = "ACV", Text = "Spawn ACV" },
			{ Name = "IFV", Text = "Spawn IFV" },
			{ Name = "MBT", Text = "Spawn MBT" },
		},
	},

	HeliTerminal = {
		Title = "Helicopter Terminal",
		Vehicles = {
			{ Name = "Cargo_Heli", Text = "Spawn Cargo Helicopter" },
		},
	},

	PlanePlatform = {
		Title = "Plane Terminal",
		Vehicles = {
			{ Name = "Interceptor_plane", Text = "Spawn Interceptor" },
		},
	},
}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "VehicleTerminalGui"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(340, 250)
frame.Position = UDim2.fromScale(0.5, 0.5)
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.BackgroundTransparency = 0.1
frame.Parent = screenGui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 40)
title.BackgroundTransparency = 1
title.TextScaled = false
title.TextSize = 24
title.Parent = frame

local buttonHolder = Instance.new("ScrollingFrame")
buttonHolder.Name = "ButtonHolder"
buttonHolder.Position = UDim2.fromOffset(15, 55)
buttonHolder.Size = UDim2.new(1, -30, 1, -110)
buttonHolder.BackgroundTransparency = 1
buttonHolder.BorderSizePixel = 0
buttonHolder.CanvasSize = UDim2.fromOffset(0, 0)
buttonHolder.AutomaticCanvasSize = Enum.AutomaticSize.Y
buttonHolder.ScrollingDirection = Enum.ScrollingDirection.Y
buttonHolder.ScrollBarThickness = 6
buttonHolder.ClipsDescendants = true
buttonHolder.Parent = frame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 10)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = buttonHolder

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(1, -30, 0, 40)
closeButton.Position = UDim2.new(0, 15, 1, -50)
closeButton.Text = "Close"
closeButton.TextScaled = false
closeButton.TextSize = 20
closeButton.Parent = frame

-- Fit all rows when possible; reserve a separate footer for Close.
-- On small screens or large catalogs the list scrolls inside the panel.
local function resizeMenu()
 local camera = workspace.CurrentCamera
 local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
 local rowsHeight = vehicleCount * BUTTON_HEIGHT + math.max(0, vehicleCount - 1) * BUTTON_GAP
 local desiredHeight = HEADER_HEIGHT + rowsHeight + FOOTER_HEIGHT
 local availableHeight = math.max(1, viewport.Y - SCREEN_MARGIN * 2)
 local height = math.min(desiredHeight, availableHeight)
 local width = math.min(PANEL_WIDTH, math.max(1, viewport.X - SCREEN_MARGIN * 2))
 frame.Size = UDim2.fromOffset(width, height)
 buttonHolder.Size = UDim2.new(1, -30, 0, math.max(0, height - HEADER_HEIGHT - FOOTER_HEIGHT))
end

local viewportConnection
local function watchCamera()
 if viewportConnection then viewportConnection:Disconnect() end
 local camera = workspace.CurrentCamera
 if camera then
  viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(resizeMenu)
 end
 resizeMenu()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
watchCamera()

local function clearVehicleButtons()
	for _, child in ipairs(buttonHolder:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function makeVehicleButton(vehicleName, buttonText, order)
	local button = Instance.new("TextButton")
	button.Name = vehicleName .. "Button"
	button.Size = UDim2.new(1, -10, 0, BUTTON_HEIGHT)
	button.LayoutOrder = order
	button.Text = buttonText
	button.TextScaled = false
	button.TextSize = 20
	button.TextWrapped = true
	button.Parent = buttonHolder

	button.MouseButton1Click:Connect(function()
		if not currentTerminal then
			return
		end

		vehicleSpawnRemote:FireServer(currentTerminal, vehicleName)
		screenGui.Enabled = false
	end)
end

vehicleSpawnRemote.OnClientEvent:Connect(function(action, terminal)
	if action ~= "OpenMenu" then
		return
	end

	if not terminal or not terminal:IsA("Model") then
		return
	end

	local objectType = terminal:GetAttribute("ObjectType")
	local config = VEHICLE_BUTTONS[objectType]
	if not config then
		return
	end

	currentTerminal = terminal
	vehicleCount = #config.Vehicles
	resizeMenu()
	buttonHolder.CanvasPosition = Vector2.new(0, 0)
	title.Text = config.Title
	clearVehicleButtons()

	for index, vehicleData in ipairs(config.Vehicles) do
		makeVehicleButton(vehicleData.Name, vehicleData.Text, index)
	end

	screenGui.Enabled = true
end)

closeButton.MouseButton1Click:Connect(function()
	screenGui.Enabled = false
	currentTerminal = nil
end)
