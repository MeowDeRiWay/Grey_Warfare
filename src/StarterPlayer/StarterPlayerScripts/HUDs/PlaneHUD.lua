local Shared = require(script.Parent.HUDShared)

local PlaneHUD = {}
local gui
local left
local modulePanel
local title
local hp
local fuel
local endurance
local throttle
local speed
local altitude
local vs
local cannon
local warning
local moduleFrame
local moduleLabels = {}
local lastY
local lastT
local smoothVS = 0
local airborneLatched = false

local function altitudeAGL(vehicle)
	local pos = vehicle:GetPivot().Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {vehicle}
	local hit = workspace:Raycast(pos, Vector3.new(0, -20000, 0), params)
	return hit and math.max(0, pos.Y - hit.Position.Y) or math.max(0, pos.Y)
end

local function formatTime(seconds)
	if not seconds or seconds == math.huge then
		return "--:--"
	end
	seconds = math.max(0, math.floor(seconds + 0.5))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%02d:%02d", m, s)
end

local function builtInGun(vehicle)
	local current = Shared.getNumber(vehicle, {"Gun_current_ammo", "Cannon_current_ammo"}, nil)
	local max = Shared.getNumber(vehicle, {"Gun_max_ammo", "Cannon_max_ammo"}, nil)
	if current ~= nil or max ~= nil then
		return current or 0, max or current or 0
	end

	local mounted = vehicle:FindFirstChild("MountedModules")
	for _, item in ipairs(vehicle:GetDescendants()) do
		if item:IsA("Model")
			and item ~= vehicle
			and item:GetAttribute("Current_ammo") ~= nil
			and not (mounted and item:IsDescendantOf(mounted))
		then
			return Shared.getNumber(item, {"Current_ammo"}, 0),
				Shared.getNumber(item, {"Magazine_size", "Max_ammo"}, 0)
		end
	end
	return nil, nil
end

function PlaneHUD.Create(playerGui)
	gui = Shared.makeGui(playerGui, "PlaneHUD", 20)

	left = Shared.makePanel(gui, "PlaneInfo", UDim2.new(0, 18, 1, -18), UDim2.new(0, 330, 0, 286))
	title = Shared.makeText(left, "Title", UDim2.new(0, 12, 0, 8), UDim2.new(1, -24, 0, 28), 20)
	hp = Shared.makeText(left, "HP", UDim2.new(0, 12, 0, 42), UDim2.new(1, -24, 0, 24), 18)
	fuel = Shared.makeText(left, "Fuel", UDim2.new(0, 12, 0, 68), UDim2.new(1, -24, 0, 24), 18)
	endurance = Shared.makeText(left, "Endurance", UDim2.new(0, 12, 0, 94), UDim2.new(1, -24, 0, 24), 18)
	throttle = Shared.makeText(left, "Throttle", UDim2.new(0, 12, 0, 132), UDim2.new(1, -24, 0, 24), 18)
	speed = Shared.makeText(left, "Speed", UDim2.new(0, 12, 0, 158), UDim2.new(1, -24, 0, 24), 18)
	altitude = Shared.makeText(left, "Altitude", UDim2.new(0, 12, 0, 184), UDim2.new(1, -24, 0, 24), 18)
	vs = Shared.makeText(left, "VS", UDim2.new(0, 12, 0, 210), UDim2.new(1, -24, 0, 24), 18)
	cannon = Shared.makeText(left, "Cannon", UDim2.new(0, 12, 0, 242), UDim2.new(1, -24, 0, 24), 18)

	modulePanel = Shared.makePanel(gui, "WeaponModules", UDim2.new(1, -18, 1, -18), UDim2.new(0, 390, 0, 210), Vector2.new(1, 1))
	Shared.makeText(modulePanel, "Title", UDim2.new(0, 12, 0, 8), UDim2.new(1, -24, 0, 28), 19).Text = "WEAPON MODULES"
	moduleFrame = Instance.new("Frame")
	moduleFrame.BackgroundTransparency = 1
	moduleFrame.Position = UDim2.new(0, 12, 0, 42)
	moduleFrame.Size = UDim2.new(1, -24, 1, -52)
	moduleFrame.Parent = modulePanel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = moduleFrame

	warning = Instance.new("TextLabel")
	warning.AnchorPoint = Vector2.new(0.5, 0.5)
	warning.Position = UDim2.new(0.5, 0, 0.34, 0)
	warning.Size = UDim2.new(0, 430, 0, 86)
	warning.BackgroundTransparency = 1
	warning.Font = Enum.Font.GothamBlack
	warning.TextSize = 56
	warning.Text = "PULL UP"
	warning.TextColor3 = Color3.fromRGB(255, 60, 60)
	warning.TextStrokeColor3 = Color3.fromRGB(60, 0, 0)
	warning.TextStrokeTransparency = 0
	warning.Visible = false
	warning.Parent = gui

	return gui
end

function PlaneHUD.SetEnabled(value)
	if gui then gui.Enabled = value end
	if not value then
		lastY, lastT, smoothVS = nil, nil, 0
		airborneLatched = false
		if warning then warning.Visible = false end
	end
end

function PlaneHUD.Update(vehicle)
	if not vehicle then return end

	title.Text = tostring(vehicle:GetAttribute("DisplayName") or vehicle.Name)

	local ch = Shared.getNumber(vehicle, {"HP_cur"}, 0)
	local mh = Shared.getNumber(vehicle, {"HP_max"}, ch)
	hp.Text = string.format("HP        %d / %d", ch, mh)

	local cf, mf = Shared.getFuel(vehicle)
	fuel.Text = string.format("FUEL      %d / %d", cf, mf)

	local thr = math.clamp(Shared.getNumber(vehicle, {"Throttle"}, 0), 0, 1)
	local consumption = Shared.getNumber(vehicle, {"Fuel_consumption"}, nil)
	if consumption and consumption > 0 and thr > 0.001 then
		endurance.Text = "ENDURANCE " .. formatTime(cf / (consumption * thr))
	else
		endurance.Text = "ENDURANCE --:--"
	end

	local spd = math.max(0, Shared.getNumber(vehicle, {"Current_speed"}, 0))
	local minSpeed = math.max(1, Shared.getNumber(vehicle, {"Min_speed"}, 50))
	local alt = altitudeAGL(vehicle)

	throttle.Text = string.format("THROTTLE  %3d%%", math.floor(thr * 100 + 0.5))
	speed.Text = string.format("SPEED     %4d km/h", math.floor(spd * 3.6 + 0.5))
	altitude.Text = string.format("ALT AGL   %4d m", math.floor(alt + 0.5))

	local now = os.clock()
	local y = vehicle:GetPivot().Position.Y
	if lastY and lastT then
		local dt = math.max(0.001, now - lastT)
		local raw = (y - lastY) / dt
		local a = 1 - math.exp(-6 * dt)
		smoothVS += (raw - smoothVS) * a
	end
	lastY, lastT = y, now
	vs.Text = string.format("V/S       %+.1f m/s", smoothVS)

	local gunCurrent, gunMax = builtInGun(vehicle)
	if gunCurrent ~= nil then
		cannon.Text = string.format("CANNON    %d / %d", gunCurrent, gunMax)
	else
		cannon.Text = "CANNON    —"
	end

	if alt > 12 or spd >= minSpeed then
		airborneLatched = true
	end

	local danger = airborneLatched and alt < 100 and spd < (minSpeed * 2)
	warning.Visible = danger
	if danger then
		local flash = (math.floor(now * 4) % 2) == 0
		warning.TextTransparency = flash and 0 or 0.35
		warning.TextStrokeTransparency = flash and 0 or 0.35
	end

	local modules = Shared.getAmmoModules(vehicle)
	for i, module in ipairs(modules) do
		local label = moduleLabels[i]
		if not label then
			label = Shared.makeText(moduleFrame, "Module_" .. i, UDim2.new(), UDim2.new(1, 0, 0, 28), 17)
			label.LayoutOrder = i
			moduleLabels[i] = label
		end
		label.Visible = true
		local ammo = Shared.getNumber(module, {"Current_ammo"}, nil)
		local magSize = Shared.getNumber(module, {"Magazine_size", "Max_ammo"}, nil)
		local mags = Shared.getNumber(module, {"Current_magazines"}, nil)
		local maxMags = Shared.getNumber(module, {"Max_magazines"}, nil)

		local parts = {Shared.moduleDisplayName(module)}
		if ammo ~= nil then
			table.insert(parts, magSize ~= nil and string.format("AMMO %d/%d", ammo, magSize) or string.format("AMMO %d", ammo))
		end
		if mags ~= nil then
			table.insert(parts, maxMags ~= nil and string.format("MAG %d/%d", mags, maxMags) or string.format("MAG %d", mags))
		end
		label.Text = table.concat(parts, "   |   ")
	end
	for i = #modules + 1, #moduleLabels do
		moduleLabels[i].Visible = false
	end
end

return PlaneHUD
