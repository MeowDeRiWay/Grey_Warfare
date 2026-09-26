local Players = game:GetService("Players")

local player = Players.LocalPlayer

local DEFAULT_MIN_ZOOM = 0.5
local DEFAULT_MAX_ZOOM = 12

local savedMinZoom = nil
local savedMaxZoom = nil
local firstPersonActive = false

local function isDriverSeat(seatPart)
	if not seatPart then
		return false
	end

	if not (seatPart:IsA("VehicleSeat") or seatPart:IsA("Seat")) then
		return false
	end

	return seatPart.Name == "Driver_seat"
end

local function enableFirstPerson()
	if firstPersonActive then
		return
	end

	firstPersonActive = true
	savedMinZoom = player.CameraMinZoomDistance
	savedMaxZoom = player.CameraMaxZoomDistance

	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5
end

local function disableFirstPerson()
	if not firstPersonActive then
		return
	end

	firstPersonActive = false
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMinZoomDistance = savedMinZoom or DEFAULT_MIN_ZOOM
	player.CameraMaxZoomDistance = savedMaxZoom or DEFAULT_MAX_ZOOM

	savedMinZoom = nil
	savedMaxZoom = nil
end

local function bindCharacter(character)
	disableFirstPerson()

	local humanoid = character:WaitForChild("Humanoid")

	local function refreshCamera()
		if isDriverSeat(humanoid.SeatPart) then
			enableFirstPerson()
		else
			disableFirstPerson()
		end
	end

	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(refreshCamera)
	refreshCamera()
end

if player.Character then
	task.spawn(bindCharacter, player.Character)
end

player.CharacterAdded:Connect(bindCharacter)
