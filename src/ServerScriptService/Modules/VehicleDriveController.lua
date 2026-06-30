local RunService = game:GetService("RunService")

local VehicleDriveController = {}

local activeVehicles = {}

local DEFAULT_MAX_SPEED = 40
local DEFAULT_TURN_SPEED = 2.5

local function getDriverSeat(vehicle)
	local seat = vehicle:FindFirstChild("Driver_seat", true)

	if seat and seat:IsA("VehicleSeat") then
		return seat
	end

	return nil
end

local function getMain(vehicle)
	local main = vehicle:FindFirstChild("Main", true)

	if main and main:IsA("BasePart") then
		return main
	end

	return nil
end

local function getMaxSpeed(vehicle)
	return vehicle:GetAttribute("MaxSpeed")
		or vehicle:GetAttribute("Max_speed")
		or DEFAULT_MAX_SPEED
end

function VehicleDriveController.RegisterVehicle(vehicle, ownerPlayer)
	local main = getMain(vehicle)
	local seat = getDriverSeat(vehicle)

	if not main then
		warn("[VehicleDriveController] Main not found:", vehicle.Name)
		return
	end

	if not seat then
		warn("[VehicleDriveController] Driver_seat VehicleSeat not found:", vehicle.Name)
		return
	end

	main:SetNetworkOwner(ownerPlayer)

	activeVehicles[vehicle] = {
		Main = main,
		Seat = seat,
		Owner = ownerPlayer,
	}

	print("[VehicleDriveController] Vehicle registered:", vehicle.Name)
end

RunService.Heartbeat:Connect(function(dt)
	for vehicle, data in pairs(activeVehicles) do
		if not vehicle.Parent then
			activeVehicles[vehicle] = nil
			continue
		end

		local main = data.Main
		local seat = data.Seat

		if not main or not main.Parent or not seat or not seat.Parent then
			activeVehicles[vehicle] = nil
			continue
		end

		local throttle = seat.Throttle
		local steer = seat.Steer

		local maxSpeed = getMaxSpeed(vehicle)
		local forward = main.CFrame.LookVector

		main.AssemblyLinearVelocity = Vector3.new(
			forward.X * throttle * maxSpeed,
			main.AssemblyLinearVelocity.Y,
			forward.Z * throttle * maxSpeed
		)

		main.AssemblyAngularVelocity = Vector3.new(
			0,
			-steer * DEFAULT_TURN_SPEED,
			0
		)
	end
end)

return VehicleDriveController