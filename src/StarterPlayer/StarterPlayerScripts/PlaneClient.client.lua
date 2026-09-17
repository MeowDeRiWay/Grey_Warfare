local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local mouse = player:GetMouse()

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local planeControlRemote = remotes:WaitForChild("PlaneControl")

local SEND_RATE = 0.05
print("[PlaneClient] V11 MODULE-SAFE GROUND FIX loaded")
local CAMERA_PRIORITY = Enum.RenderPriority.Camera.Value + 100

local activePlane = nil
local freeLook = false
local throttle = 0
local throttleUpHeld = false
local throttleDownHeld = false
local lastAimDirection = Vector3.new(-1, 0, 0)

local sendAccumulator = 0
local freeYaw = 0
local freePitch = math.rad(-10)

local visualPlanePosition = nil
local visualPlaneRotation = nil
local groundPivotOffset = 2
local flightYaw = 0
local flightPitch = 0
local visualRoll = 0
local fallSpeed = 0

local savedCameraType = nil
local savedCameraSubject = nil
local savedFov = nil
local savedMouseBehavior = nil
local savedMouseIconEnabled = nil

local function getMain(vehicle)
	local main = vehicle and vehicle:FindFirstChild("Main", true)
	if main and main:IsA("BasePart") then
		return main
	end
	return nil
end


local function getAirframeBottomY(vehicle)
	-- Ground reference must come from the aircraft itself, never from mounted modules.
	-- Modules/rockets can hang below the fuselage and must not raise the plane.
	local mountedModules = vehicle:FindFirstChild("MountedModules")
	local lowestY = math.huge

	for _, item in ipairs(vehicle:GetDescendants()) do
		if item:IsA("BasePart") then
			local insideMountedModules =
				mountedModules ~= nil
				and item:IsDescendantOf(mountedModules)

			if not insideMountedModules then
				local half = item.Size * 0.5
				for sx = -1, 1, 2 do
					for sy = -1, 1, 2 do
						for sz = -1, 1, 2 do
							local corner = item.CFrame:PointToWorldSpace(Vector3.new(
								half.X * sx,
								half.Y * sy,
								half.Z * sz
							))
							lowestY = math.min(lowestY, corner.Y)
						end
					end
				end
			end
		end
	end

	if lowestY == math.huge then
		return vehicle:GetPivot().Position.Y - 0.5
	end

	return lowestY
end

local function getControlledPlane()
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local seat = humanoid.SeatPart
	if not seat then
		return nil
	end

	local current = seat
	while current and current ~= workspace do
		if current:IsA("Model") and current:GetAttribute("Plane") == true then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function planeForward(vehicle)
	-- Ніс МОДЕЛІ дивиться по локальній -X.
	-- Не беремо вісь Main: імпортований Main може мати власну орієнтацію.
	return -vehicle:GetPivot().RightVector
end

local ACTION_THROTTLE_UP = "PlaneThrottleUp"
local ACTION_THROTTLE_DOWN = "PlaneThrottleDown"

local function throttleUpAction(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		throttleUpHeld = true
	elseif inputState == Enum.UserInputState.End
		or inputState == Enum.UserInputState.Cancel
	then
		throttleUpHeld = false
	end

	return Enum.ContextActionResult.Sink
end

local function throttleDownAction(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		throttleDownHeld = true
	elseif inputState == Enum.UserInputState.End
		or inputState == Enum.UserInputState.Cancel
	then
		throttleDownHeld = false
	end

	return Enum.ContextActionResult.Sink
end

local function bindPlaneControls()
	ContextActionService:BindActionAtPriority(
		ACTION_THROTTLE_UP,
		throttleUpAction,
		false,
		Enum.ContextActionPriority.High.Value + 100,
		Enum.KeyCode.W
	)

	ContextActionService:BindActionAtPriority(
		ACTION_THROTTLE_DOWN,
		throttleDownAction,
		false,
		Enum.ContextActionPriority.High.Value + 100,
		Enum.KeyCode.S
	)
end

local function unbindPlaneControls()
	ContextActionService:UnbindAction(ACTION_THROTTLE_UP)
	ContextActionService:UnbindAction(ACTION_THROTTLE_DOWN)
	throttleUpHeld = false
	throttleDownHeld = false
end

local function enterPlane(vehicle)
	if activePlane == vehicle then
		return
	end

	activePlane = vehicle
	freeLook = false
	sendAccumulator = 0
	throttle = math.clamp(tonumber(vehicle:GetAttribute("Throttle")) or 0, 0, 1)

	local main = getMain(vehicle)
	if main then
		lastAimDirection = planeForward(vehicle)
		local pivot = vehicle:GetPivot()
		visualPlanePosition = pivot.Position
		visualPlaneRotation = pivot.Rotation
		flightForward = -(pivot.Rotation.RightVector)
		visualRoll = 0
	end

	savedCameraType = camera.CameraType
	savedCameraSubject = camera.CameraSubject
	savedFov = camera.FieldOfView
	savedMouseBehavior = UserInputService.MouseBehavior
	savedMouseIconEnabled = UserInputService.MouseIconEnabled

	camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	bindPlaneControls()
end

local function exitPlane()
	if not activePlane then
		return
	end

	activePlane = nil
	freeLook = false
	throttle = 0
	visualPlanePosition = nil
	visualPlaneRotation = nil
	flightYaw = 0
	flightPitch = 0
	visualRoll = 0
	fallSpeed = 0
	unbindPlaneControls()

	camera.CameraType = savedCameraType or Enum.CameraType.Custom
	if savedCameraSubject then
		camera.CameraSubject = savedCameraSubject
	end
	if savedFov then
		camera.FieldOfView = savedFov
	end

	UserInputService.MouseBehavior = savedMouseBehavior or Enum.MouseBehavior.Default
	if savedMouseIconEnabled ~= nil then
		UserInputService.MouseIconEnabled = savedMouseIconEnabled
	else
		UserInputService.MouseIconEnabled = true
	end

	savedCameraType = nil
	savedCameraSubject = nil
	savedFov = nil
	savedMouseBehavior = nil
	savedMouseIconEnabled = nil
end

local function updateFreeLookFromCurrentCamera(focus)
	local offset = camera.CFrame.Position - focus
	local flat = Vector3.new(offset.X, 0, offset.Z)

	if flat.Magnitude > 0.001 then
		freeYaw = math.atan2(offset.X, offset.Z)
	end

	if offset.Magnitude > 0.001 then
		freePitch = math.asin(math.clamp(offset.Y / offset.Magnitude, -1, 1))
	end
end

local function toggleFreeLook()
	if not activePlane then
		return
	end

	freeLook = not freeLook
	local main = getMain(activePlane)
	if not main then
		return
	end

	if freeLook then
		updateFreeLookFromCurrentCamera(main.Position)
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not activePlane then
		return
	end

	if input.KeyCode == Enum.KeyCode.Q then
		toggleFreeLook()
	end
end)

local function updateThrottle(dt, vehicle)
	local rate =
		math.max(
			0.05,
			tonumber(vehicle:GetAttribute("Throttle_change_rate")) or 0.55
		)

	if throttleUpHeld then
		throttle += rate * dt
	end

	if throttleDownHeld then
		throttle -= rate * dt
	end

	throttle = math.clamp(throttle, 0, 1)
end
local function updateFlightCamera(vehicle, main, dt)
	local forward = planeForward(vehicle)
	local up = main.CFrame.UpVector
	local cameraDistance = tonumber(vehicle:GetAttribute("Camera_distance")) or 24
	local cameraHeight = tonumber(vehicle:GetAttribute("Camera_height")) or 7
	local lookAhead = tonumber(vehicle:GetAttribute("Camera_look_ahead")) or 18

	local focus = main.Position + forward * lookAhead
	local desiredPosition = main.Position - forward * cameraDistance + up * cameraHeight
	local desired = CFrame.lookAt(desiredPosition, focus, up)

	local smooth = math.max(1, tonumber(vehicle:GetAttribute("Camera_smooth")) or 10)
	local alpha = 1 - math.exp(-smooth * dt)

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = camera.CFrame:Lerp(desired, alpha)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	-- Mouse-flight:
	-- центр екрана = прямо по поточному курсу літака.
	-- Курсор задає кутове відхилення, а не сирий Camera Ray.
	local viewport = camera.ViewportSize
	if viewport.X > 1 and viewport.Y > 1 then
		local nx =
			math.clamp(
				(mouse.X - viewport.X * 0.5) / (viewport.X * 0.5),
				-1,
				1
			)

		local ny =
			math.clamp(
				(mouse.Y - viewport.Y * 0.5) / (viewport.Y * 0.5),
				-1,
				1
			)

		local maxYaw =
			math.rad(
				tonumber(vehicle:GetAttribute("Mouse_yaw_angle"))
				or 35
			)

		local maxPitch =
			math.rad(
				tonumber(vehicle:GetAttribute("Mouse_pitch_angle"))
				or 28
			)

		local currentForward = planeForward(vehicle)
		local flatForward =
			Vector3.new(
				currentForward.X,
				0,
				currentForward.Z
			)

		if flatForward.Magnitude < 0.001 then
			flatForward = Vector3.xAxis
		else
			flatForward = flatForward.Unit
		end

		local currentYaw =
			math.atan2(
				flatForward.Z,
				flatForward.X
			)

		local currentPitch =
			math.asin(
				math.clamp(
					currentForward.Y,
					-1,
					1
				)
			)

		local targetYaw =
			currentYaw + nx * maxYaw

		-- Екранний Y росте вниз, тому верх екрана = позитивний pitch.
		local targetPitch =
			math.clamp(
				currentPitch - ny * maxPitch,
				math.rad(-80),
				math.rad(80)
			)

		local cp = math.cos(targetPitch)

		lastAimDirection =
			Vector3.new(
				cp * math.cos(targetYaw),
				math.sin(targetPitch),
				cp * math.sin(targetYaw)
			).Unit
	end
end

local function updateFreeLookCamera(vehicle, main)
	local delta = UserInputService:GetMouseDelta()
	local sensitivity = tonumber(vehicle:GetAttribute("Camera_sensitivity")) or 0.0035

	freeYaw -= delta.X * sensitivity
	freePitch -= delta.Y * sensitivity
	freePitch = math.clamp(freePitch, math.rad(-80), math.rad(80))

	local cameraDistance = tonumber(vehicle:GetAttribute("Camera_distance")) or 24
	local cameraHeight = tonumber(vehicle:GetAttribute("Camera_height")) or 4
	local focus = main.Position + Vector3.new(0, cameraHeight, 0)

	local rotation = CFrame.fromEulerAnglesYXZ(freePitch, freeYaw, 0)
	local offset = rotation:VectorToWorldSpace(Vector3.new(0, 0, cameraDistance))
	local desiredPosition = focus + offset

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { vehicle }
	if player.Character then
		table.insert(exclude, player.Character)
	end
	rayParams.FilterDescendantsInstances = exclude
	rayParams.IgnoreWater = true

	local result = workspace:Raycast(focus, desiredPosition - focus, rayParams)
	local finalPosition = desiredPosition

	if result then
		local direction = desiredPosition - focus
		if direction.Magnitude > 0.001 then
			finalPosition = result.Position - direction.Unit * 0.35
		end
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(finalPosition, focus)
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
end

RunService:BindToRenderStep("PlaneClientCamera", CAMERA_PRIORITY, function(dt)
	local controlledPlane = getControlledPlane()

	if controlledPlane ~= activePlane then
		if controlledPlane then
			enterPlane(controlledPlane)
		else
			exitPlane()
		end
	end

	local vehicle = activePlane
	if not vehicle then
		return
	end

	local main = getMain(vehicle)
	if not main then
		exitPlane()
		return
	end

	updateThrottle(dt, vehicle)

	-- Smooth local visual movement.
	-- Server supplies Current_speed; the client advances the model every rendered frame.
	-- No mouse steering/pitch/roll is applied in this diagnostic stage.
	if not visualPlanePosition or not visualPlaneRotation then
		local pivot = vehicle:GetPivot()
		visualPlanePosition = pivot.Position
		visualPlaneRotation = pivot.Rotation

		local spawnForward = -(pivot.RightVector)
		flightYaw = math.atan2(spawnForward.Z, spawnForward.X)
		flightPitch = math.asin(math.clamp(spawnForward.Y, -1, 1))
		visualRoll = 0

		-- Fixed arcade ground clearance, measured only once from the spawn pose.
		-- It does NOT change when the aircraft pitches/rolls, so a wing touching
		-- the ground cannot jack the whole aircraft upward.
		local bottomY = getAirframeBottomY(vehicle)
		groundPivotOffset = math.max(
			0.5,
			pivot.Position.Y - bottomY
		)
	end

	local currentSpeed = math.max(
		0,
		tonumber(vehicle:GetAttribute("Current_speed")) or 0
	)

	-- Absolute attitude controller.
	-- Yaw and pitch are stored as world-referenced scalars, while roll is a
	-- separate visual bank. This removes cumulative Up/Right basis errors.
	local minSpeedForControls =
		math.max(
			1,
			tonumber(vehicle:GetAttribute("Min_speed")) or 50
		)

	local flightControlsUnlocked =
		currentSpeed >= minSpeedForControls

	if not freeLook then
		local viewport = camera.ViewportSize
		local nx, ny = 0, 0

		if viewport.X > 1 and viewport.Y > 1 then
			nx = math.clamp(
				(mouse.X - viewport.X * 0.5) / (viewport.X * 0.5),
				-1,
				1
			)
			ny = math.clamp(
				(mouse.Y - viewport.Y * 0.5) / (viewport.Y * 0.5),
				-1,
				1
			)
		end

		local yawInput = math.sign(nx) * (math.abs(nx) ^ 2)
		local pitchInput = 0

		if flightControlsUnlocked then
			pitchInput = -math.sign(ny) * (math.abs(ny) ^ 2)
		end

		local yawRate = math.rad(
			math.max(1, tonumber(vehicle:GetAttribute("Yaw_speed")) or 25)
		)
		local pitchRate = math.rad(
			math.max(1, tonumber(vehicle:GetAttribute("Pitch_speed")) or 35)
		)

		flightYaw += yawInput * yawRate * dt

		if flightControlsUnlocked then
			flightPitch += pitchInput * pitchRate * dt
			flightPitch = math.clamp(
				flightPitch,
				math.rad(-80),
				math.rad(80)
			)
		else
			-- Below Min_speed: keep the aircraft level on the runway.
			-- This prevents nose/wing penetration while taxiing or stopped.
			local levelPitchSpeed =
				math.rad(
					math.max(
						1,
						tonumber(vehicle:GetAttribute("Level_pitch_speed")) or 90
					)
				)

			flightPitch += math.clamp(
				-flightPitch,
				-levelPitchSpeed * dt,
				levelPitchSpeed * dt
			)
		end

		local maxRoll = math.rad(
			math.max(0, tonumber(vehicle:GetAttribute("Max_roll")) or 65)
		)
		local targetRoll = 0

		if flightControlsUnlocked then
			targetRoll = yawInput * maxRoll

			-- Cursor around screen centre means "level the wings".
			if math.abs(nx) < 0.08 then
				targetRoll = 0
			end
		end

		local rollSpeed = math.rad(
			math.max(1, tonumber(vehicle:GetAttribute("Roll_speed")) or 70)
		)
		local levelSpeed = math.rad(
			math.max(1, tonumber(vehicle:GetAttribute("Level_roll_speed")) or 120)
		)

		local activeRollSpeed =
			math.abs(targetRoll) < math.rad(1)
			and levelSpeed
			or rollSpeed

		visualRoll += math.clamp(
			targetRoll - visualRoll,
			-activeRollSpeed * dt,
			activeRollSpeed * dt
		)
	end

	-- Deterministic forward vector from absolute yaw/pitch.
	local cp = math.cos(flightPitch)
	local flightForward = Vector3.new(
		cp * math.cos(flightYaw),
		math.sin(flightPitch),
		cp * math.sin(flightYaw)
	).Unit

	-- World-up always defines level flight.
	-- Since pitch is clamped to +/-80 degrees, this basis cannot flip at a pole.
	local worldUp = Vector3.yAxis
	local localRight = flightForward:Cross(worldUp).Unit
	local levelUp = localRight:Cross(flightForward).Unit

	local levelRotation = CFrame.fromMatrix(
		Vector3.zero,
		-flightForward,
		levelUp,
		-localRight
	)

	-- Bank is independent from navigation attitude and always returns to zero.
	local finalRotation =
		CFrame.fromAxisAngle(flightForward, visualRoll)
		* levelRotation

	-- Arcade lift/stall:
	-- at/above Min_speed the aircraft holds altitude normally;
	-- below Min_speed it progressively loses lift and accelerates downward.
	local minSpeed = math.max(1, tonumber(vehicle:GetAttribute("Min_speed")) or 50)
	local liftRatio = math.clamp(currentSpeed / minSpeed, 0, 1)
	local stallFactor = 1 - liftRatio

	local fallAcceleration = tonumber(vehicle:GetAttribute("Fall_acceleration")) or 70
	local maxFallSpeed = tonumber(vehicle:GetAttribute("Max_fall_speed")) or 180
	local recovery = tonumber(vehicle:GetAttribute("Fall_recovery")) or 120

	if stallFactor > 0.001 then
		fallSpeed = math.min(
			maxFallSpeed,
			fallSpeed + fallAcceleration * stallFactor * dt
		)
	else
		fallSpeed = math.max(0, fallSpeed - recovery * dt)
	end

	local displacement =
		flightForward * currentSpeed * dt
		+ Vector3.new(0, -fallSpeed * dt, 0)

	-- Client-side anti-clipping. Sweep from current position to the next position.
	-- Ignore the aircraft itself and the seated player's character.
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { vehicle }
	if player.Character then
		table.insert(exclude, player.Character)
	end
	rayParams.FilterDescendantsInstances = exclude
	rayParams.IgnoreWater = false

	-- Ground anti-sink: use the FIXED base-airframe clearance captured on entry.
	-- MountedModules, pylons and rockets are intentionally ignored here, so adding
	-- equipment below the aircraft can never jack the whole plane upward.
	local desiredPosition = visualPlanePosition + displacement
	local pivotToBottom = groundPivotOffset

	local groundGap = math.max(
		0.05,
		tonumber(vehicle:GetAttribute("Ground_clearance")) or 0.15
	)

	local probeExtra = tonumber(vehicle:GetAttribute("Ground_probe_extra")) or 2
	local probeDistance = math.max(
		pivotToBottom + groundGap + probeExtra,
		pivotToBottom + math.max(0, fallSpeed * dt) + probeExtra
	)

	local groundHit = workspace:Raycast(
		visualPlanePosition,
		Vector3.new(0, -probeDistance, 0),
		rayParams
	)

	local grounded = false
	if groundHit and groundHit.Normal.Y > 0.45 then
		local groundPivotY =
			groundHit.Position.Y
			+ pivotToBottom
			+ groundGap

		local currentBottomY =
			visualPlanePosition.Y
			- pivotToBottom

		grounded =
			currentBottomY
			<= groundHit.Position.Y + groundGap + 0.6

		-- Hard floor for the whole aircraft model.
		-- If ANY current part of the bounding box is below the terrain plane,
		-- move only the aircraft position upward. Never touch yaw/pitch/roll.
		if desiredPosition.Y < groundPivotY then
			desiredPosition = Vector3.new(
				desiredPosition.X,
				groundPivotY,
				desiredPosition.Z
			)
			grounded = true
		end
	end

	if grounded and fallSpeed > 0 then
		fallSpeed = 0
	end

	visualPlanePosition = desiredPosition

	vehicle:PivotTo(CFrame.new(visualPlanePosition) * finalRotation)

	if freeLook then
		updateFreeLookCamera(vehicle, main)
	else
		updateFlightCamera(vehicle, main, dt)
	end

	sendAccumulator += dt
	if sendAccumulator >= SEND_RATE then
		sendAccumulator = 0
		planeControlRemote:FireServer({
			Throttle = throttle,
			AimDirection = lastAimDirection,
			FreeLook = freeLook,
		})
	end
end)

player.CharacterAdded:Connect(function()
	exitPlane()
end)
