local Shared = require(script.Parent.HUDShared)

local HelicopterHUD = {}
local gui
local title
local hp
local fuel
local speed
local altitude
local vs
local lastY
local lastT
local smoothVS = 0

local function altitudeAGL(vehicle)
	local pos = vehicle:GetPivot().Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {vehicle}
	local hit = workspace:Raycast(pos, Vector3.new(0, -20000, 0), params)
	return hit and math.max(0, pos.Y - hit.Position.Y) or math.max(0, pos.Y)
end

function HelicopterHUD.Create(playerGui)
	gui = Shared.makeGui(playerGui, "HelicopterHUD", 10)
	local panel = Shared.makePanel(gui, "Panel", UDim2.new(0, 18, 1, -18), UDim2.new(0, 360, 0, 220))
	title = Shared.makeText(panel, "Title", UDim2.new(0, 12, 0, 8), UDim2.new(1, -24, 0, 26), 20)
	hp = Shared.makeText(panel, "HP", UDim2.new(0, 12, 0, 40), UDim2.new(1, -24, 0, 24), 18)
	fuel = Shared.makeText(panel, "Fuel", UDim2.new(0, 12, 0, 66), UDim2.new(1, -24, 0, 24), 18)
	speed = Shared.makeText(panel, "Speed", UDim2.new(0, 12, 0, 92), UDim2.new(1, -24, 0, 24), 18)
	altitude = Shared.makeText(panel, "Altitude", UDim2.new(0, 12, 0, 118), UDim2.new(1, -24, 0, 24), 18)
	vs = Shared.makeText(panel, "VS", UDim2.new(0, 12, 0, 144), UDim2.new(1, -24, 0, 24), 18)
	Shared.makeText(panel, "Hints", UDim2.new(0, 12, 1, -38), UDim2.new(1, -24, 0, 26), 15).Text =
		"WASD — Move   |   Q/Z — Lift"
	return gui
end

function HelicopterHUD.SetEnabled(value)
	if gui then gui.Enabled = value end
	if not value then lastY, lastT, smoothVS = nil, nil, 0 end
end

function HelicopterHUD.Update(vehicle)
	if not vehicle then return end
	title.Text = tostring(vehicle:GetAttribute("DisplayName") or vehicle.Name)

	local ch, mh = Shared.getHP(vehicle)
	hp.Text = string.format("HP      %d / %d", ch, mh)

	local cf, mf = Shared.getFuel(vehicle)
	fuel.Text = string.format("FUEL    %d / %d", cf, mf)

	local spd = Shared.getNumber(vehicle, {"Current_speed", "Speed"}, 0)
	speed.Text = string.format("SPEED   %d km/h", math.floor(spd * 3.6 + 0.5))

	local alt = altitudeAGL(vehicle)
	altitude.Text = string.format("ALT AGL %d m", math.floor(alt + 0.5))

	local now = os.clock()
	local y = vehicle:GetPivot().Position.Y
	if lastY and lastT then
		local dt = math.max(0.001, now - lastT)
		local raw = (y - lastY) / dt
		local a = 1 - math.exp(-6 * dt)
		smoothVS += (raw - smoothVS) * a
	end
	lastY, lastT = y, now
	vs.Text = string.format("V/S     %+.1f m/s", smoothVS)
end

return HelicopterHUD
