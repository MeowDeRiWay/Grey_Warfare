local HUDShared = {}

function HUDShared.getCharacter(player)
	return player.Character
end

function HUDShared.getHumanoid(player)
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

function HUDShared.getControlledVehicle(player)
	local humanoid = HUDShared.getHumanoid(player)
	if not humanoid or not humanoid.SeatPart then
		return nil
	end

	local activeVehicles = workspace:FindFirstChild("ActiveVehicles")
	local current = humanoid.SeatPart

	while current and current ~= workspace do
		if current:IsA("Model") then
			if activeVehicles and current.Parent == activeVehicles then
				return current
			end
			if current:GetAttribute("OwnerUserId") ~= nil then
				return current
			end
		end
		current = current.Parent
	end

	return nil
end

function HUDShared.getNumber(object, names, default)
	if not object then
		return default
	end

	for _, name in ipairs(names) do
		local value = object:GetAttribute(name)
		if value ~= nil then
			local number = tonumber(value)
			if number ~= nil then
				return number
			end
		end
	end

	return default
end

function HUDShared.makeGui(playerGui, name, order)
	local old = playerGui:FindFirstChild(name)
	if old then
		old:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = order or 10
	gui.Enabled = false
	gui.Parent = playerGui
	return gui
end

function HUDShared.makePanel(parent, name, position, size, anchor)
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.AnchorPoint = anchor or Vector2.new(0, 1)
	panel.Position = position
	panel.Size = size
	panel.BackgroundColor3 = Color3.fromRGB(12, 15, 18)
	panel.BackgroundTransparency = 0.28
	panel.BorderSizePixel = 0
	panel.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Transparency = 0.62
	stroke.Parent = panel

	return panel
end

function HUDShared.makeText(parent, name, position, size, textSize, align)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = Enum.Font.RobotoMono
	label.TextSize = textSize or 18
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.48
	label.TextXAlignment = align or Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = ""
	label.Parent = parent
	return label
end

function HUDShared.getFuel(vehicle)
	local current = HUDShared.getNumber(
		vehicle,
		{"Current_fuel", "Fuel_current", "CurrentFuel", "Fuel"},
		0
	)
	local max = HUDShared.getNumber(
		vehicle,
		{"Max_fuel", "Fuel_max", "MaxFuel", "Fuel_capacity", "FuelCapacity"},
		0
	)
	return current, max
end

function HUDShared.getCargo(vehicle)
	local current = HUDShared.getNumber(
		vehicle,
		{"Current_cargo", "Cargo_current", "Loaded_cargo", "Cargo", "CurrentCargo"},
		nil
	)
	local max = HUDShared.getNumber(
		vehicle,
		{"Max_cargo", "Cargo_max", "Cargo_capacity", "MaxCargo"},
		nil
	)

	if current ~= nil or max ~= nil then
		return current or 0, max or 0
	end

	current, max = 0, 0
	local mounted = vehicle and vehicle:FindFirstChild("MountedModules")
	if mounted then
		for _, item in ipairs(mounted:GetDescendants()) do
			if item:IsA("Model") and item:GetAttribute("ModuleRole") == "Cargo" then
				current += HUDShared.getNumber(item, {"Current_cargo", "CurrentCargo"}, 0)
				max += HUDShared.getNumber(item, {"Max_cargo", "MaxCargo"}, 0)
			end
		end
	end
	return current, max
end

function HUDShared.getAmmoModules(vehicle)
	local result = {}
	local mounted = vehicle and vehicle:FindFirstChild("MountedModules")
	if not mounted then
		return result
	end

	for _, item in ipairs(mounted:GetDescendants()) do
		if item:IsA("Model")
			and (
				item:GetAttribute("Current_ammo") ~= nil
				or item:GetAttribute("Current_magazines") ~= nil
			)
		then
			table.insert(result, item)
		end
	end

	table.sort(result, function(a, b)
		return a.Name < b.Name
	end)

	return result
end

function HUDShared.moduleDisplayName(module)
	return tostring(
		module:GetAttribute("DisplayName")
		or module:GetAttribute("ModuleName")
		or module.Name
	)
end

return HUDShared
