local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(script.Parent.HUDShared)

local GroundHUD = {}
local gui
local title
local hp
local fuel
local cargo
local speed
local artilleryInfo
local ammoHeader
local moduleFrame
local moduleLabels = {}

local calculatorsFolder = ReplicatedStorage:FindFirstChild("ArtilleryCalculators")
local RSZVCalculator = nil
local BallCalculator = nil

if calculatorsFolder then
	local rszv = calculatorsFolder:FindFirstChild("RSZVCalculator")
	local ball = calculatorsFolder:FindFirstChild("BallCalculator")

	if rszv and rszv:IsA("ModuleScript") then
		local ok, result = pcall(require, rszv)
		if ok then
			RSZVCalculator = result
		else
			warn("[GroundHUD] RSZVCalculator require failed:", result)
		end
	end

	if ball and ball:IsA("ModuleScript") then
		local ok, result = pcall(require, ball)
		if ok then
			BallCalculator = result
		else
			warn("[GroundHUD] BallCalculator require failed:", result)
		end
	end
end

local function axisToLocalVector(axis, defaultAxis)
	axis = tostring(axis or defaultAxis or "-X")

	if axis == "X" then
		return Vector3.xAxis
	elseif axis == "-X" then
		return -Vector3.xAxis
	elseif axis == "Y" then
		return Vector3.yAxis
	elseif axis == "-Y" then
		return -Vector3.yAxis
	elseif axis == "Z" then
		return Vector3.zAxis
	elseif axis == "-Z" then
		return -Vector3.zAxis
	end

	return axisToLocalVector(defaultAxis or "-X", "-X")
end

local function getMountedModules(vehicle)
	local mounted = vehicle and vehicle:FindFirstChild("MountedModules")
	if not mounted then
		return {}
	end

	local result = {}
	for _, item in ipairs(mounted:GetDescendants()) do
		if item:IsA("Model") then
			table.insert(result, item)
		end
	end

	table.sort(result, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)

	return result
end

local function isRocketLauncher(module)
	if module:GetAttribute("Rocket_current") ~= nil
		or module:GetAttribute("Rocket_max") ~= nil
	then
		return true
	end

	for _, item in ipairs(module:GetDescendants()) do
		if item:IsA("BasePart")
			and (
				item:GetAttribute("Ammo_module") == true
				or item.Name:match("^Ammo_module")
			)
			and tostring(item:GetAttribute("Allowed_ammo")) == "Rocket"
		then
			return true
		end
	end

	return false
end

local function getRocketAmmoType(module)
	local direct =
		module:GetAttribute("Ammo_type")
		or module:GetAttribute("Allowed_ammo_type")

	if direct ~= nil and tostring(direct) ~= "" then
		return tostring(direct)
	end

	for _, item in ipairs(module:GetDescendants()) do
		if item:IsA("BasePart")
			and (
				item:GetAttribute("Ammo_module") == true
				or item.Name:match("^Ammo_module")
			)
		then
			local ammoType = item:GetAttribute("Allowed_ammo_type")
			if ammoType ~= nil and tostring(ammoType) ~= "" then
				return tostring(ammoType)
			end
		end
	end

	return "Rocket"
end

local function countLoadedRockets(module)
	local loaded = 0
	local max = 0

	for _, item in ipairs(module:GetDescendants()) do
		if item:IsA("BasePart")
			and (
				item:GetAttribute("Ammo_module") == true
				or item.Name:match("^Ammo_module")
			)
			and tostring(item:GetAttribute("Allowed_ammo")) == "Rocket"
		then
			max += 1

			for _, child in ipairs(item:GetChildren()) do
				if child:IsA("Model")
					and child:GetAttribute("LoadedAmmo") == true
				then
					loaded += 1
					break
				end
			end
		end
	end

	local attrCurrent = tonumber(module:GetAttribute("Rocket_current"))
	local attrMax = tonumber(module:GetAttribute("Rocket_max"))

	if attrCurrent ~= nil then
		loaded = attrCurrent
	end
	if attrMax ~= nil and attrMax > 0 then
		max = attrMax
	end

	return loaded, max
end

local function getDisplayAmmoEntries(vehicle)
	local entries = {}
	local seen = {}

	for _, module in ipairs(Shared.getAmmoModules(vehicle)) do
		seen[module] = true

		local ammo = Shared.getNumber(module, {"Current_ammo"}, 0)
		local magSize = Shared.getNumber(module, {"Magazine_size"}, 0)
		local mags = Shared.getNumber(module, {"Current_magazines"}, 0)
		local maxMags = Shared.getNumber(module, {"Max_magazines"}, 0)

		table.insert(entries, {
			module = module,
			text = string.format(
				"%s   %d/%d   |   MAG %d/%d",
				Shared.moduleDisplayName(module),
				ammo,
				magSize,
				mags,
				maxMags
			),
		})
	end

	for _, module in ipairs(getMountedModules(vehicle)) do
		if not seen[module] and isRocketLauncher(module) then
			seen[module] = true

			local loaded, max = countLoadedRockets(module)
			local ammoType = getRocketAmmoType(module)

			table.insert(entries, {
				module = module,
				text = string.format(
					"%s   %s   %d/%d",
					Shared.moduleDisplayName(module),
					ammoType,
					loaded,
					max
				),
			})
		end
	end

	table.sort(entries, function(a, b)
		return a.text < b.text
	end)

	return entries
end

local function findArtilleryModule(vehicle)
	for _, module in ipairs(getMountedModules(vehicle)) do
		if module:GetAttribute("rszv_calc") == true then
			return module, "rszv"
		end

		if module:GetAttribute("ball_calc") == true then
			return module, "ball"
		end
	end

	return nil, nil
end

local function getLoadedAmmo(module)
	for _, item in ipairs(module:GetDescendants()) do
		if item:IsA("Model")
			and item:GetAttribute("LoadedAmmo") == true
		then
			return item
		end
	end

	return nil
end

local function getAmmoTypeHint(module)
	local direct =
		module:GetAttribute("Ammo_type")
		or module:GetAttribute("Allowed_ammo_type")

	if direct ~= nil and tostring(direct) ~= "" then
		return tostring(direct)
	end

	for _, item in ipairs(module:GetDescendants()) do
		if item:IsA("BasePart") then
			local allowed = item:GetAttribute("Allowed_ammo_type")
			if allowed ~= nil and tostring(allowed) ~= "" then
				return tostring(allowed)
			end
		end
	end

	return nil
end

local function findAmmoTemplate(ammoType)
	if not ammoType then
		return nil
	end

	local vehicles = ReplicatedStorage:FindFirstChild("Vehicles")
	if not vehicles then
		return nil
	end

	local vAmmo = vehicles:FindFirstChild("VAmmo")
	if not vAmmo then
		return nil
	end

	local exact = vAmmo:FindFirstChild(ammoType, true)
	if exact and exact:IsA("Model") then
		return exact
	end

	for _, item in ipairs(vAmmo:GetDescendants()) do
		if item:IsA("Model")
			and tostring(item:GetAttribute("Ammo_type")) == ammoType
		then
			return item
		end
	end

	return nil
end

local function getCalculatorAmmo(module)
	return getLoadedAmmo(module)
		or findAmmoTemplate(getAmmoTypeHint(module))
end

local function getRSZVLaunchDirection(module)
	local loadedAmmo = getLoadedAmmo(module)

	if loadedAmmo then
		local socket = loadedAmmo.Parent
		if socket and socket:IsA("BasePart") then
			local axis =
				socket:GetAttribute("Launch_axis")
				or module:GetAttribute("Launch_axis")
				or "-X"

			return socket.CFrame
				:VectorToWorldSpace(axisToLocalVector(axis, "-X"))
				.Unit
		end
	end

	for _, item in ipairs(module:GetDescendants()) do
		if item:IsA("BasePart")
			and (
				item:GetAttribute("Ammo_module") == true
				or item.Name:match("^Ammo_module")
			)
		then
			local axis =
				item:GetAttribute("Launch_axis")
				or module:GetAttribute("Launch_axis")
				or "-X"

			return item.CFrame
				:VectorToWorldSpace(axisToLocalVector(axis, "-X"))
				.Unit
		end
	end

	return nil
end

local function getBallLaunchDirection(module)
	local barrel = module:FindFirstChild("Barrel", true)
	if barrel and barrel:IsA("BasePart") then
		local axis =
			barrel:GetAttribute("Barrel_axis")
			or module:GetAttribute("Barrel_axis")
			or "-X"

		return barrel.CFrame
			:VectorToWorldSpace(axisToLocalVector(axis, "-X"))
			.Unit
	end

	local muzzle = module:FindFirstChild("Muzzle", true)
	if muzzle and muzzle:IsA("BasePart") then
		local axis =
			muzzle:GetAttribute("Launch_axis")
			or module:GetAttribute("Launch_axis")
			or "-X"

		return muzzle.CFrame
			:VectorToWorldSpace(axisToLocalVector(axis, "-X"))
			.Unit
	end

	return nil
end

local function updateArtillery(vehicle)
	local module, calcType = findArtilleryModule(vehicle)

	if not module then
		artilleryInfo.Visible = false
		artilleryInfo.Text = ""
		return
	end

	artilleryInfo.Visible = true

	local ammo = getCalculatorAmmo(module)
	if not ammo then
		artilleryInfo.Text = "ART: NO AMMO DATA"
		return
	end

	local direction
	local result

	if calcType == "rszv" then
		direction = getRSZVLaunchDirection(module)
		if direction and RSZVCalculator then
			result = RSZVCalculator.Calculate(ammo, direction)
		end
	elseif calcType == "ball" then
		direction = getBallLaunchDirection(module)
		if direction and BallCalculator then
			result = BallCalculator.Calculate(ammo, direction)
		end
	end

	if not direction then
		artilleryInfo.Text = "ART: NO LAUNCH AXIS"
		return
	end

	if not result then
		artilleryInfo.Text = "ART: NO BALLISTIC DATA"
		return
	end

	local rangeKm = (tonumber(result.Range) or 0) / 1000
	local tof = tonumber(result.FlightTime) or 0
	local pitch = tonumber(result.Pitch) or 0
	local suffix = result.Completed == false and "+" or ""

	artilleryInfo.Text = string.format(
		"RNG %.2f%s km   |   TOF %.1f s   |   ANG %.1f°",
		rangeKm,
		suffix,
		tof,
		pitch
	)
end

function GroundHUD.Create(playerGui)
	gui = Shared.makeGui(playerGui, "GroundHUD", 10)

	local panel =
		Shared.makePanel(
			gui,
			"Panel",
			UDim2.new(0, 18, 1, -18),
			UDim2.new(0, 500, 0, 390)
		)

	title = Shared.makeText(panel, "Title", UDim2.new(0, 12, 0, 8), UDim2.new(1, -24, 0, 26), 20)
	hp = Shared.makeText(panel, "HP", UDim2.new(0, 12, 0, 40), UDim2.new(1, -24, 0, 24), 18)
	fuel = Shared.makeText(panel, "Fuel", UDim2.new(0, 12, 0, 66), UDim2.new(1, -24, 0, 24), 18)
	cargo = Shared.makeText(panel, "Cargo", UDim2.new(0, 12, 0, 92), UDim2.new(1, -24, 0, 24), 18)
	speed = Shared.makeText(panel, "Speed", UDim2.new(0, 12, 0, 118), UDim2.new(1, -24, 0, 24), 18)

	artilleryInfo =
		Shared.makeText(
			panel,
			"ArtilleryInfo",
			UDim2.new(0, 12, 0, 148),
			UDim2.new(1, -24, 0, 24),
			16
		)
	artilleryInfo.Visible = false

	ammoHeader =
		Shared.makeText(
			panel,
			"Header",
			UDim2.new(0, 12, 0, 180),
			UDim2.new(1, -24, 0, 24),
			17
		)
	ammoHeader.Text = "MODULE AMMO"

	moduleFrame = Instance.new("Frame")
	moduleFrame.BackgroundTransparency = 1
	moduleFrame.Position = UDim2.new(0, 12, 0, 208)
	moduleFrame.Size = UDim2.new(1, -24, 0, 130)
	moduleFrame.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.Parent = moduleFrame

	Shared.makeText(
		panel,
		"Hints",
		UDim2.new(0, 12, 1, -34),
		UDim2.new(1, -24, 0, 24),
		15
	).Text = "LMB — Fire   |   RMB — Sight   |   WASD — Drive"

	return gui
end

function GroundHUD.SetEnabled(value)
	if gui then
		gui.Enabled = value
	end
end

function GroundHUD.Update(vehicle)
	if not vehicle then
		return
	end

	title.Text =
		tostring(
			vehicle:GetAttribute("DisplayName")
			or vehicle:GetAttribute("VehicleName")
			or vehicle.Name
		)

	local currentHealth = Shared.getNumber(vehicle, {"Current_health", "Health"}, 0)
	local maxHealth = Shared.getNumber(vehicle, {"Max_health", "MaxHealth"}, currentHealth)
	hp.Text = string.format("HP      %d / %d", currentHealth, maxHealth)

	local currentFuel, maxFuel = Shared.getFuel(vehicle)
	fuel.Text = string.format("FUEL    %d / %d", currentFuel, maxFuel)

	local currentCargo, maxCargo = Shared.getCargo(vehicle)
	cargo.Text = string.format("CARGO   %d / %d", currentCargo, maxCargo)

	local currentSpeed = Shared.getNumber(vehicle, {"Current_speed", "Display_speed"}, 0)
	speed.Text = string.format("SPEED   %d km/h", math.floor(currentSpeed * 3.6 + 0.5))

	updateArtillery(vehicle)

	local entries = getDisplayAmmoEntries(vehicle)

	for i, entry in ipairs(entries) do
		local label = moduleLabels[i]

		if not label then
			label =
				Shared.makeText(
					moduleFrame,
					"Ammo_" .. i,
					UDim2.new(),
					UDim2.new(1, 0, 0, 22),
					16
				)
			label.LayoutOrder = i
			moduleLabels[i] = label
		end

		label.Visible = true
		label.Text = entry.text
	end

	for i = #entries + 1, #moduleLabels do
		moduleLabels[i].Visible = false
	end

	ammoHeader.Text =
		#entries > 0
		and "MODULE AMMO"
		or "MODULE AMMO: NONE"
end

return GroundHUD
