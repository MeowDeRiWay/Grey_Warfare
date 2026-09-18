local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlaneDriveController = {}

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local planeControlRemote = remotes:FindFirstChild("PlaneControl")
if not planeControlRemote then
	planeControlRemote = Instance.new("RemoteEvent")
	planeControlRemote.Name = "PlaneControl"
	planeControlRemote.Parent = remotes
end

local activePlanes = {}
local playerInput = {}

local function getMain(vehicle)
	local main = vehicle:FindFirstChild("Main", true)
	if main and main:IsA("BasePart") then
		return main
	end
	return nil
end

local function getDriverSeat(vehicle)
	local seat = vehicle:FindFirstChild("Driver_seat", true)
	if seat and (seat:IsA("Seat") or seat:IsA("VehicleSeat")) then
		return seat
	end
	return nil
end

local function getBodyGroundOffset(vehicle)
	local pivotY = vehicle:GetPivot().Position.Y
	local mounted = vehicle:FindFirstChild("MountedModules")
	local lowestY = math.huge

	for _, item in ipairs(vehicle:GetDescendants()) do
		if item:IsA("BasePart")
			and (not mounted or not item:IsDescendantOf(mounted))
		then
			local cf = item.CFrame
			local halfX = item.Size.X * 0.5
			local halfY = item.Size.Y * 0.5
			local halfZ = item.Size.Z * 0.5

			local verticalExtent =
				math.abs(cf.RightVector.Y) * halfX
				+ math.abs(cf.UpVector.Y) * halfY
				+ math.abs(cf.LookVector.Y) * halfZ

			lowestY = math.min(lowestY, item.Position.Y - verticalExtent)
		end
	end

	if lowestY == math.huge then
		return 1
	end

	return math.max(0.1, pivotY - lowestY)
end

local function getAbandonedGroundHit(vehicle, pivotPosition, bodyGroundOffset, extraDistance)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { vehicle }
	rayParams.IgnoreWater = false

	local rayDistance =
		math.max(
			2,
			bodyGroundOffset + (extraDistance or 0) + 4
		)

	return workspace:Raycast(
		pivotPosition,
		Vector3.new(0, -rayDistance, 0),
		rayParams
	)
end

local function prepareVehicle(vehicle, main)
	for _, item in ipairs(vehicle:GetDescendants()) do
		if item:IsA("BasePart") then
			item.CanCollide = false
			item.CanTouch = false
			item.Massless = true
			item.AssemblyLinearVelocity = Vector3.zero
			item.AssemblyAngularVelocity = Vector3.zero

			-- Main is the only anchored/root part.
			-- Welded parts, especially Driver_seat, must stay unanchored
			-- so the weld can carry them together with Main.
			item.Anchored = (item == main)
		end
	end
end

local function moveTowards(current, target, maxDelta)
	if current < target then
		return math.min(current + maxDelta, target)
	elseif current > target then
		return math.max(current - maxDelta, target)
	end
	return target
end

planeControlRemote.OnServerEvent:Connect(function(player, packet)
	if typeof(packet) ~= "table" then
		return
	end

	local throttle = tonumber(packet.Throttle)
	if throttle ~= nil then
		throttle = math.clamp(throttle, 0, 1)
	end

	playerInput[player] = {
		Throttle = throttle,
	}
end)

Players.PlayerRemoving:Connect(function(player)
	playerInput[player] = nil
end)

function PlaneDriveController.RegisterVehicle(vehicle, ownerPlayer)
	if activePlanes[vehicle] then
		return
	end

	local main = getMain(vehicle)
	local seat = getDriverSeat(vehicle)

	if not main then
		warn("[PlaneDriveController] Main not found:", vehicle.Name)
		return
	end

	if not seat then
		warn("[PlaneDriveController] Driver_seat not found:", vehicle.Name)
		return
	end

	vehicle.PrimaryPart = main
	prepareVehicle(vehicle, main)

	-- CRITICAL:
	-- Keep the exact model orientation that exists at spawn.
	-- No guessed -X/+Z forward axis and no CFrame.fromMatrix rebuild.
	local spawnPivot = vehicle:GetPivot()

	activePlanes[vehicle] = {
		Owner = ownerPlayer,
		Seat = seat,
		Main = main,

		Throttle = 0,
		CurrentSpeed = 0,
		WasOccupied = false,
		AbandonedFallSpeed = 0,
		GroundPivotOffset = getBodyGroundOffset(vehicle),

		-- Exact orientation at registration.
		Rotation = spawnPivot.Rotation,
	}

	vehicle:SetAttribute("Current_speed", 0)
	vehicle:SetAttribute("Throttle", 0)
	vehicle:SetAttribute("Plane_stage", "CLIENT_VISUAL_STRAIGHT")
	vehicle:SetAttribute("Plane_seat_occupied", false)
	vehicle:SetAttribute("Plane_input_ok", false)

	print("[PlaneDriveController] CLIENT VISUAL + fuel + abandoned ground-safe flight registered:", vehicle.Name)
end

function PlaneDriveController.UnregisterVehicle(vehicle)
	activePlanes[vehicle] = nil
end

RunService.Heartbeat:Connect(function(dt)
	for vehicle, data in pairs(activePlanes) do
		if not vehicle.Parent then
			activePlanes[vehicle] = nil
			continue
		end

		local seat = data.Seat
		local main = data.Main

		if not seat or not seat.Parent or not main or not main.Parent then
			activePlanes[vehicle] = nil
			continue
		end

		-- Vehicle physics are prepared once during registration.
		-- Reapplying them every Heartbeat caused visible jitter.
		local humanoid = seat.Occupant
		local occupied = humanoid ~= nil
		local driverPlayer = nil

		if humanoid and humanoid.Parent then
			driverPlayer = Players:GetPlayerFromCharacter(humanoid.Parent)
		end

		local input = nil
		if driverPlayer then
			input = playerInput[driverPlayer]
		elseif data.Owner then
			input = playerInput[data.Owner]
		end

		if occupied then
			if not data.WasOccupied then
				data.AbandonedFallSpeed = 0
			end

			if input and input.Throttle ~= nil then
				data.Throttle = input.Throttle
			end

			-- VehicleSeat fallback.
			if seat:IsA("VehicleSeat") then
				if seat.Throttle > 0 then
					data.Throttle = 1
				elseif seat.Throttle < 0 then
					data.Throttle = 0
				end
			end
		else
			-- No pilot: client no longer owns visual movement.
			-- Keep the aircraft's inertia instead of freezing it in the sky.
			data.Throttle = 0
		end

		local maxSpeed =
			math.max(
				1,
				tonumber(vehicle:GetAttribute("Max_speed")) or 400
			)

		local acceleration =
			math.max(
				1,
				tonumber(vehicle:GetAttribute("Acceleration")) or 60
			)

		local currentFuel =
			tonumber(vehicle:GetAttribute("Fuel_cur")) or 0

		local maxFuel =
			tonumber(vehicle:GetAttribute("Fuel_max")) or 0

		local fuelPerSecond =
			math.max(
				0,
				tonumber(vehicle:GetAttribute("Fuel_consumption"))
					or tonumber(vehicle:GetAttribute("Fuel_per_second"))
					or 0.15
			)

		if maxFuel > 0 and currentFuel <= 0 then
			data.Throttle = 0
		end

		if occupied then
			local targetSpeed = data.Throttle * maxSpeed
			data.CurrentSpeed =
				moveTowards(
					data.CurrentSpeed,
					targetSpeed,
					acceleration * dt
				)
		else
			-- Abandoned aircraft keeps most of its forward inertia.
			local abandonedDrag = math.max(1, acceleration * 0.12)
			data.CurrentSpeed =
				moveTowards(
					data.CurrentSpeed,
					0,
					abandonedDrag * dt
				)

			local fallAcceleration =
				math.max(0, tonumber(vehicle:GetAttribute("Fall_acceleration")) or 70)
			local maxFallSpeed =
				math.max(0, tonumber(vehicle:GetAttribute("Max_fall_speed")) or 180)

			data.AbandonedFallSpeed =
				math.min(
					maxFallSpeed,
					(data.AbandonedFallSpeed or 0) + fallAcceleration * dt
				)

			-- V11 client uses the model's local -X as the aircraft nose.
			-- Server takes over only after the pilot leaves.
			local pivot = vehicle:GetPivot()
			local forward = -pivot.RightVector
			local downwardStep = data.AbandonedFallSpeed * dt

			local displacement =
				forward * data.CurrentSpeed * dt
				+ Vector3.new(0, -downwardStep, 0)

			local targetPosition = pivot.Position + displacement

			-- Ground clamp uses the BASE aircraft body only.
			-- MountedModules / rockets do not change this offset.
			local groundGap =
				math.max(
					0.05,
					tonumber(vehicle:GetAttribute("Ground_clearance")) or 0.5
				)

			local hit =
				getAbandonedGroundHit(
					vehicle,
					pivot.Position,
					data.GroundPivotOffset,
					downwardStep
				)

			if hit and hit.Normal.Y > 0.45 then
				local minPivotY =
					hit.Position.Y
					+ data.GroundPivotOffset
					+ groundGap

				if targetPosition.Y <= minPivotY then
					targetPosition =
						Vector3.new(
							targetPosition.X,
							minPivotY,
							targetPosition.Z
						)

					data.AbandonedFallSpeed = 0
					data.CurrentSpeed = 0
				end
			end

			vehicle:PivotTo(CFrame.new(targetPosition) * pivot.Rotation)
		end

		-- Stage 2:
		-- Server owns throttle/speed state, but DOES NOT PivotTo every Heartbeat.
		-- The controlling client renders the plane continuously each frame.
		-- This test isolates the replicated server-PivotTo jitter.

		if occupied
			and maxFuel > 0
			and currentFuel > 0
			and data.Throttle > 0
			and fuelPerSecond > 0
		then
			currentFuel =
				math.max(
					0,
					currentFuel - fuelPerSecond * data.Throttle * dt
				)
			vehicle:SetAttribute("Fuel_cur", currentFuel)
		end

		vehicle:SetAttribute("Current_speed", data.CurrentSpeed)
		vehicle:SetAttribute("Throttle", data.Throttle)
		vehicle:SetAttribute("Fuel_burn_per_second", fuelPerSecond * data.Throttle)
		vehicle:SetAttribute("Plane_seat_occupied", occupied)
		vehicle:SetAttribute("Plane_input_ok", input ~= nil)
		data.WasOccupied = occupied
	end
end)

return PlaneDriveController
