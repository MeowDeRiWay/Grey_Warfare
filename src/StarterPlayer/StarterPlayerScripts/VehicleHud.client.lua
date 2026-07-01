local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "VehicleHudClient"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Name = "VehicleInfo"
frame.AnchorPoint = Vector2.new(0, 1)
frame.Position = UDim2.new(0, 14, 1, -110)
frame.Size = UDim2.new(0, 230, 0, 108)
frame.BackgroundTransparency = 0.25
frame.BorderSizePixel = 1
frame.Visible = false
frame.Parent = gui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 8, 0, 6)
title.Size = UDim2.new(1, -16, 0, 22)
title.Font = Enum.Font.SourceSansBold
title.TextSize = 18
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Техніка"
title.Parent = frame

local fuel = Instance.new("TextLabel")
fuel.Name = "Fuel"
fuel.BackgroundTransparency = 1
fuel.Position = UDim2.new(0, 8, 0, 32)
fuel.Size = UDim2.new(1, -16, 0, 20)
fuel.Font = Enum.Font.SourceSans
fuel.TextSize = 18
fuel.TextXAlignment = Enum.TextXAlignment.Left
fuel.Text = "Паливо: 0 / 0"
fuel.Parent = frame

local cargo = Instance.new("TextLabel")
cargo.Name = "Cargo"
cargo.BackgroundTransparency = 1
cargo.Position = UDim2.new(0, 8, 0, 56)
cargo.Size = UDim2.new(1, -16, 0, 20)
cargo.Font = Enum.Font.SourceSans
cargo.TextSize = 18
cargo.TextXAlignment = Enum.TextXAlignment.Left
cargo.Text = "Вантаж: 0 / 0"
cargo.Parent = frame

local speed = Instance.new("TextLabel")
speed.Name = "Speed"
speed.BackgroundTransparency = 1
speed.Position = UDim2.new(0, 8, 0, 80)
speed.Size = UDim2.new(1, -16, 0, 20)
speed.Font = Enum.Font.SourceSans
speed.TextSize = 18
speed.TextXAlignment = Enum.TextXAlignment.Left
speed.Text = "Швидкість: 0"
speed.Parent = frame

local currentVehicle = nil

local function getNumberAttr(object, names, default)
	for _, name in ipairs(names) do
		local value = object:GetAttribute(name)
		if value ~= nil then
			return tonumber(value) or default
		end
	end
	return default
end

local function getVehicleFromSeat(seat)
	if not seat then
		return nil
	end

	local current = seat
	while current and current ~= workspace do
		if current:IsA("Model") and current:GetAttribute("OwnerUserId") ~= nil then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function hookCharacter(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	humanoid.Seated:Connect(function(active, seat)
		if active and seat then
			currentVehicle = getVehicleFromSeat(seat)
		else
			currentVehicle = nil
		end
	end)
end

if player.Character then
	hookCharacter(player.Character)
end
player.CharacterAdded:Connect(hookCharacter)

local accumulator = 0
RunService.RenderStepped:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.12 then
		return
	end
	accumulator = 0

	local vehicle = currentVehicle
	if not vehicle or not vehicle.Parent then
		frame.Visible = false
		return
	end

	frame.Visible = true
	title.Text = vehicle.Name

	local currentFuel = getNumberAttr(vehicle, { "Current_fuel", "Fuel_current" }, 0)
	local maxFuel = getNumberAttr(vehicle, { "Max_fuel", "Fuel_max" }, 0)
	fuel.Text = string.format("Паливо: %d / %d", math.floor(currentFuel + 0.5), math.floor(maxFuel + 0.5))

	local currentCargo = getNumberAttr(vehicle, {
		"Current_cargo",
		"Cargo_current",
		"Loaded_cargo",
		"Current_load",
		"Cargo",
		"CurrentCargo",
	}, 0)

	local maxCargo = getNumberAttr(vehicle, {
		"Max_cargo",
		"Cargo_max",
		"Cargo_capacity",
		"Max_load",
		"CargoCapacity",
	}, 0)

	cargo.Text = string.format("Вантаж: %d / %d", math.floor(currentCargo + 0.5), math.floor(maxCargo + 0.5))

	local currentSpeed = getNumberAttr(vehicle, { "Current_speed", "Display_speed" }, 0)
	speed.Text = string.format("Швидкість: %d", math.floor(currentSpeed + 0.5))
end)
