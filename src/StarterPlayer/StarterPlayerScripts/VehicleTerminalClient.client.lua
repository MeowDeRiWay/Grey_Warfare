local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local vehicleSpawnRemote = remotes:WaitForChild("VehicleSpawnRequest")

local currentTerminal = nil

local VEHICLE_BUTTONS = {
	VehicleTerminal = {
		Title = "Vehicle Terminal",
		Vehicles = {
			{ Name = "Cargo", Text = "Spawn Cargo" },
			{ Name = "Unicar", Text = "Spawn Unicar" },
		},
	},

	HeliTerminal = {
		Title = "Helicopter Terminal",
		Vehicles = {
			{ Name = "Cargo_Heli", Text = "Spawn Cargo Helicopter" },
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
title.TextScaled = true
title.Parent = frame

local buttonHolder = Instance.new("Frame")
buttonHolder.Name = "ButtonHolder"
buttonHolder.Position = UDim2.fromOffset(15, 55)
buttonHolder.Size = UDim2.new(1, -30, 1, -110)
buttonHolder.BackgroundTransparency = 1
buttonHolder.Parent = frame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 10)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = buttonHolder

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(1, -30, 0, 40)
closeButton.Position = UDim2.new(0, 15, 1, -50)
closeButton.Text = "Close"
closeButton.TextScaled = true
closeButton.Parent = frame

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
	button.Size = UDim2.new(1, 0, 0, 48)
	button.LayoutOrder = order
	button.Text = buttonText
	button.TextScaled = true
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

	currentTerminal = terminal

	local objectType = terminal:GetAttribute("ObjectType")
	local config = VEHICLE_BUTTONS[objectType] or VEHICLE_BUTTONS.VehicleTerminal

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
