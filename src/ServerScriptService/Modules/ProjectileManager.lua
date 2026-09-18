local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ProjectileManager = {}

local PROJECTILES_FOLDER_NAME = "Projectiles"

-- Єдина гравітація для всіх балістичних об'єктів.
-- При масштабі 1 stud ~= 1 метр це приблизно 9.8 м/с^2.
local WORLD_GRAVITY = 9.8

-- Якщо снаряд провалився нижче карти — більше його не рахуємо.
local MIN_Y = -100

-- У Studio зручніше задавати Projectile_drag як 0.004,
-- а не 0.0004, тому переводимо атрибут у робочий коефіцієнт тут.
-- 0.004 * 0.1 = 0.0004
local DRAG_SCALE = 0.1

local dispersionRandom = Random.new()

local function rotateDirection(direction, yawDeg, pitchDeg)
	direction = direction.Unit

	local worldUp = Vector3.yAxis
	local right = direction:Cross(worldUp)

	if right.Magnitude < 0.001 then
		right = Vector3.xAxis
	else
		right = right.Unit
	end

	local up = right:Cross(direction).Unit

	local yaw = math.rad(yawDeg)
	local pitch = math.rad(pitchDeg)

	local yawed =
		direction * math.cos(yaw)
		+ right * math.sin(yaw)

	local yawedRight = yawed:Cross(up)
	if yawedRight.Magnitude < 0.001 then
		yawedRight = right
	else
		yawedRight = yawedRight.Unit
	end

	local yawedUp = yawedRight:Cross(yawed).Unit

	return (
		yawed * math.cos(pitch)
		+ yawedUp * math.sin(pitch)
	).Unit
end

local activeProjectiles = {}
local activeRockets = {}

local ROCKET_HARD_CLEANUP_TIME = 120

local function getProjectilesFolder()
	local folder = Workspace:FindFirstChild(PROJECTILES_FOLDER_NAME)

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = PROJECTILES_FOLDER_NAME
		folder.Parent = Workspace
	end

	return folder
end

local function findDamageTarget(instance)
	local current = instance

	while current and current ~= Workspace do
		if current:GetAttribute("HP_cur") ~= nil then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function findTrainingTarget(instance)
	local current = instance

	while current and current ~= Workspace do
		if current:GetAttribute("TTarget") == true then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function getTrainingTargetAdornee(target, hitPart)
	if hitPart and hitPart:IsA("BasePart") and hitPart:IsDescendantOf(target) then
		return hitPart
	end

	if target:IsA("BasePart") then
		return target
	end

	if target:IsA("Model") then
		if target.PrimaryPart and target.PrimaryPart:IsA("BasePart") then
			return target.PrimaryPart
		end

		local main = target:FindFirstChild("Main", true)
		if main and main:IsA("BasePart") then
			return main
		end

		return target:FindFirstChildWhichIsA("BasePart", true)
	end

	return nil
end

local function showTrainingDamage(target, hitPart, damage)
	damage = tonumber(damage) or 0
	if not target or damage <= 0 then
		return
	end

	local adornee = getTrainingTargetAdornee(target, hitPart)
	if not adornee then
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "TrainingDamagePopup"
	gui.Adornee = adornee
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 5000
	gui.Size = UDim2.fromOffset(160, 60)
	gui.StudsOffsetWorldSpace = Vector3.new(
		math.random(-15, 15) / 10,
		math.max(2.5, adornee.Size.Y * 0.5 + 1.5),
		0
	)
	gui.Parent = adornee

	local label = Instance.new("TextLabel")
	label.Name = "Damage"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = string.format("-%g", damage)
	label.TextScaled = true
	label.TextStrokeTransparency = 0.25
	label.TextColor3 = Color3.fromRGB(255, 90, 90)
	label.Parent = gui

	local startOffset = gui.StudsOffsetWorldSpace
	local tween = TweenService:Create(
		gui,
		TweenInfo.new(
			0.9,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		),
		{
			StudsOffsetWorldSpace = startOffset + Vector3.new(0, 2.5, 0),
		}
	)

	local fade = TweenService:Create(
		label,
		TweenInfo.new(
			0.9,
			Enum.EasingStyle.Linear,
			Enum.EasingDirection.Out
		),
		{
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	)

	tween:Play()
	fade:Play()

	task.delay(1, function()
		if gui.Parent then
			gui:Destroy()
		end
	end)
end

local function applyDamage(target, damage)
	if not target or damage <= 0 then
		return
	end

	local currentHealth = target:GetAttribute("HP_cur")

	if currentHealth ~= nil then
		target:SetAttribute(
			"HP_cur",
			math.max(0, tonumber(currentHealth) - damage)
		)

		return
	end

end

local function getProjectileDrag(config, weapon)
	-- Пріоритет:
	-- 1) Drag, явно переданий зброєю;
	-- 2) Projectile_drag на Weapon;
	-- 3) 0 = без опору.
	local rawDrag = tonumber(config.Drag)

	if rawDrag == nil
		and weapon
		and weapon.GetAttribute
	then
		rawDrag = tonumber(
			weapon:GetAttribute("Projectile_drag")
		)
	end

	rawDrag = rawDrag or 0

	return math.max(0, rawDrag) * DRAG_SCALE
end

local function axisToLocalVector(axis)
	axis = tostring(axis or "-Z")

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

	return -Vector3.zAxis
end

local function getAxisCorrection(axis)
	-- CFrame.lookAt maps local -Z to the requested vector.
	-- Its inverse therefore maps the requested local launch axis to -Z,
	-- allowing the rocket model to visually follow its velocity.
	local localAxis = axisToLocalVector(axis)
	return CFrame.lookAt(Vector3.zero, localAxis):Inverse()
end


local function createRocketSmoke(rocket, main, launchAxis, boosterTime)
	if rocket:GetAttribute("Smoke_enabled") == false then
		return nil
	end

	local localAxis = axisToLocalVector(launchAxis)
	local halfExtent =
		math.abs(localAxis.X) * main.Size.X * 0.5
		+ math.abs(localAxis.Y) * main.Size.Y * 0.5
		+ math.abs(localAxis.Z) * main.Size.Z * 0.5

	local attachment = Instance.new("Attachment")
	attachment.Name = "RocketSmokeAttachment"
	attachment.Position = -localAxis * halfExtent
	attachment.Parent = main

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "RocketSmoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Enabled = true

	smoke.Rate =
		math.max(
			1,
			tonumber(rocket:GetAttribute("Smoke_rate")) or 70
		)

	local lifetime =
		math.max(
			0.1,
			tonumber(rocket:GetAttribute("Smoke_lifetime")) or 2.5
		)

	smoke.Lifetime = NumberRange.new(
		lifetime * 0.75,
		lifetime * 1.25
	)

	smoke.Speed = NumberRange.new(2, 7)
	smoke.Drag = 1.5
	smoke.Acceleration = Vector3.new(0, 3, 0)
	smoke.SpreadAngle = Vector2.new(18, 18)
	smoke.RotSpeed = NumberRange.new(-30, 30)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.LightInfluence = 0.8
	smoke.LockedToPart = false

	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.25, 1.7),
		NumberSequenceKeypoint.new(1, 3.4),
	})

	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.65, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})

	smoke.Parent = attachment

	local launchBurst =
		math.max(
			0,
			math.floor(
				tonumber(rocket:GetAttribute("Smoke_launch_burst")) or 28
			)
		)

	if launchBurst > 0 then
		smoke:Emit(launchBurst)
	end

	-- If the rocket has no booster, keep only the initial launch puff.
	if boosterTime <= 0 then
		smoke.Enabled = false
	end

	return smoke
end

local function prepareFlyingRocket(rocket)
	local main = rocket.PrimaryPart or rocket:FindFirstChild("Main", true)
	if not main or not main:IsA("BasePart") then
		return nil
	end

	rocket.PrimaryPart = main

	for _, item in ipairs(rocket:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
			item.Massless = true
		end
	end

	return main
end

local function showTrainingDamageForTarget(target, damage)
	if not target then
		return
	end

	local hitPart = nil
	if target:IsA("BasePart") then
		hitPart = target
	elseif target:IsA("Model") then
		hitPart = target.PrimaryPart
			or target:FindFirstChild("Main", true)
			or target:FindFirstChildWhichIsA("BasePart", true)
	end

	showTrainingDamage(target, hitPart, damage)
end

local function explodeRocket(data, position)
	local rocket = data.Rocket
	if not rocket or data.Exploded then
		return
	end

	data.Exploded = true

	local damage = math.max(0, data.Damage)
	local radius = math.max(0, data.BlastRadius)

	-- Visual only. Actual damage is handled below.
	local visual = Instance.new("Explosion")
	visual.Position = position
	visual.BlastRadius = radius
	visual.BlastPressure = 0
	visual.DestroyJointRadiusPercent = 0
	visual.Parent = Workspace

	if radius > 0 and damage > 0 then
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude

		local exclude = {}
		if data.Weapon then
			table.insert(exclude, data.Weapon)
		end
		if data.Owner and data.Owner.Character then
			table.insert(exclude, data.Owner.Character)
		end
		params.FilterDescendantsInstances = exclude

		local parts =
			Workspace:GetPartBoundsInRadius(
				position,
				radius,
				params
			)

		local damagedTargets = {}
		local trainingTargets = {}

		for _, part in ipairs(parts) do
			local target = findDamageTarget(part)
			if target and not damagedTargets[target] then
				damagedTargets[target] = true
				applyDamage(target, damage)
			end

			local trainingTarget = findTrainingTarget(part)
			if trainingTarget and not trainingTargets[trainingTarget] then
				trainingTargets[trainingTarget] = true
				showTrainingDamageForTarget(trainingTarget, damage)
			end
		end
	elseif damage > 0 and data.LastHitInstance then
		local target = findDamageTarget(data.LastHitInstance)
		if target then
			applyDamage(target, damage)
		end

		local trainingTarget =
			findTrainingTarget(data.LastHitInstance)

		if trainingTarget then
			showTrainingDamage(
				trainingTarget,
				data.LastHitInstance,
				damage
			)
		end
	end

	activeRockets[rocket] = nil

	if rocket.Parent then
		rocket:Destroy()
	end
end

function ProjectileManager.FireRocketModel(config)
	local rocket = config.Rocket
	if not rocket or not rocket:IsA("Model") then
		return nil
	end

	local direction = config.Direction
	if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.01 then
		return nil
	end

	local main = prepareFlyingRocket(rocket)
	if not main then
		return nil
	end

	-- TEST CAMERA metadata.
	-- Set before parenting so the client can identify this projectile on ChildAdded.
	rocket:SetAttribute("TestProjectile", true)
	rocket:SetAttribute(
		"ProjectileOwnerUserId",
		config.Owner and config.Owner.UserId or 0
	)

	local projectilesFolder = getProjectilesFolder()
	rocket.Parent = projectilesFolder

	local originCFrame =
		typeof(config.OriginCFrame) == "CFrame"
		and config.OriginCFrame
		or rocket:GetPivot()

	rocket:PivotTo(originCFrame)
	rocket:SetAttribute("ProjectileLaunchOrigin", originCFrame.Position)

	local maxSpeed =
		math.max(0, tonumber(rocket:GetAttribute("Max_speed")) or 0)

	local boosterTime =
		math.max(0, tonumber(rocket:GetAttribute("Booster_timer")) or 0)

	local gravity =
		math.max(0, tonumber(rocket:GetAttribute("Gravity")) or WORLD_GRAVITY)

	local rawDrag =
		tonumber(rocket:GetAttribute("Projectile_drag")) or 0

	local drag = math.max(0, rawDrag) * DRAG_SCALE

	local damage =
		math.max(0, tonumber(rocket:GetAttribute("Damage")) or 0)

	local blastRadius =
		math.max(0, tonumber(rocket:GetAttribute("Blast_radius")) or 0)

	local initialSpeed =
		math.max(0, tonumber(rocket:GetAttribute("Initial_speed")) or 0)

	local horizontalDispersion =
		math.max(
			0,
			tonumber(
				rocket:GetAttribute("Dispersion_horizontal")
			) or 0
		)

	local verticalDispersion =
		math.max(
			0,
			tonumber(
				rocket:GetAttribute("Dispersion_vertical")
			) or 0
		)

	local horizontalError =
		dispersionRandom:NextNumber(
			-horizontalDispersion,
			horizontalDispersion
		)

	local verticalError =
		dispersionRandom:NextNumber(
			-verticalDispersion,
			verticalDispersion
		)

	local launchDirection =
		rotateDirection(
			direction.Unit,
			horizontalError,
			verticalError
		)

	local carrierVelocity =
		typeof(config.CarrierVelocity) == "Vector3"
		and config.CarrierVelocity
		or Vector3.zero

	local ignore = {}
	if config.Owner and config.Owner.Character then
		table.insert(ignore, config.Owner.Character)
	end
	if config.Weapon then
		table.insert(ignore, config.Weapon)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore

	activeRockets[rocket] = {
		Rocket = rocket,
		Main = main,

		Owner = config.Owner,
		Weapon = config.Weapon,
		Launcher = config.Launcher,

		Position = originCFrame.Position,

		-- World velocity = inherited carrier velocity + rocket's own launch velocity.
		-- This prevents a fast aircraft from outrunning its own rockets.
		Velocity =
			carrierVelocity
			+ launchDirection * initialSpeed,

		CarrierVelocity = carrierVelocity,
		RocketRelativeSpeed = initialSpeed,
		LaunchDirection = launchDirection,
		LaunchAxis = config.LaunchAxis or "-Z",
		AxisCorrection = getAxisCorrection(config.LaunchAxis or "-Z"),

		MaxSpeed = maxSpeed,
		BoosterTime = boosterTime,
		Gravity = gravity,
		Drag = drag,

		Damage = damage,
		BlastRadius = blastRadius,

		RaycastParams = params,
		Age = 0,
		Exploded = false,
	}

	local rocketData = activeRockets[rocket]
	rocketData.SmokeEmitter =
		createRocketSmoke(
			rocket,
			main,
			rocketData.LaunchAxis,
			rocketData.BoosterTime
		)


	return rocket
end

function ProjectileManager.FireBullet(config)
	local origin = config.Origin
	local direction = config.Direction
	local owner = config.Owner
	local weapon = config.Weapon

	if typeof(origin) ~= "Vector3" then
		return nil
	end

	if typeof(direction) ~= "Vector3"
		or direction.Magnitude < 0.01
	then
		return nil
	end

	local speed = tonumber(config.Speed) or 180
	local damage = tonumber(config.Damage) or 10
	local size = tonumber(config.Size) or 0.15
	local drag = getProjectileDrag(config, weapon)

	local projectilePart = Instance.new("Part")
	projectilePart.Name = "Bullet"
	projectilePart.Shape = Enum.PartType.Ball
	projectilePart.Size = Vector3.new(size, size, size)
	projectilePart.Anchored = true
	projectilePart.CanCollide = false
	projectilePart.CanTouch = false
	projectilePart.CanQuery = false
	projectilePart.Material = Enum.Material.Neon
	projectilePart.CFrame = CFrame.new(origin)

	-- TEST CAMERA metadata for ordinary ballistic projectiles too.
	projectilePart:SetAttribute("TestProjectile", true)
	projectilePart:SetAttribute(
		"ProjectileOwnerUserId",
		owner and owner.UserId or 0
	)
	projectilePart:SetAttribute("ProjectileLaunchOrigin", origin)

	projectilePart.Parent = getProjectilesFolder()

	local ignore = {}

	if owner and owner.Character then
		table.insert(ignore, owner.Character)
	end

	if weapon then
		table.insert(ignore, weapon)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore

	activeProjectiles[projectilePart] = {
		Part = projectilePart,
		Position = origin,
		Velocity = direction.Unit * speed,
		Drag = drag,
		Damage = damage,
		RaycastParams = params,
	}

	return projectilePart
end

RunService.Heartbeat:Connect(function(dt)
	for projectilePart, data in pairs(activeProjectiles) do
		if not projectilePart.Parent then
			activeProjectiles[projectilePart] = nil
			continue
		end

		if data.Position.Y <= MIN_Y then
			activeProjectiles[projectilePart] = nil
			projectilePart:Destroy()
			continue
		end

		local oldPosition = data.Position

		-- 1. Гравітація.
		data.Velocity += Vector3.new(
			0,
			-WORLD_GRAVITY,
			0
		) * dt

		-- 2. Квадратичний drag.
		-- Чим більша швидкість, тим сильніше гальмування.
		local speed = data.Velocity.Magnitude

		if data.Drag > 0 and speed > 0.001 then
			local dragFactor =
				data.Drag
				* speed
				* dt

			-- Захист від перевертання вектора швидкості
			-- при випадково завеликому drag або лаг-кадрі.
			dragFactor = math.clamp(
				dragFactor,
				0,
				0.95
			)

			data.Velocity *= (1 - dragFactor)
		end

		-- 3. Переміщення.
		local newPosition =
			oldPosition
			+ data.Velocity * dt

		local delta =
			newPosition
			- oldPosition

		-- 4. Перевірка зіткнення по всьому відрізку за кадр.
		local result = Workspace:Raycast(
			oldPosition,
			delta,
			data.RaycastParams
		)

		if result then
			-- Training target feedback is independent from health.
			-- Any BasePart/Model in the hit ancestry with TTarget=true counts.
			local trainingTarget =
				findTrainingTarget(result.Instance)

			if trainingTarget then
				showTrainingDamage(
					trainingTarget,
					result.Instance,
					data.Damage
				)
			end

			local target =
				findDamageTarget(result.Instance)

			if target then
				applyDamage(
					target,
					data.Damage
				)
			end

			activeProjectiles[projectilePart] = nil
			projectilePart:Destroy()
			continue
		end

		data.Position = newPosition
		projectilePart.CFrame =
			CFrame.new(newPosition)
	end

	-- Physical rocket models.
	for rocket, data in pairs(activeRockets) do
		if not rocket.Parent or not data.Main.Parent then
			activeRockets[rocket] = nil
			continue
		end

		data.Age += dt

		if data.SmokeEmitter
			and data.SmokeEmitter.Parent
			and data.Age > data.BoosterTime
		then
			data.SmokeEmitter.Enabled = false
		end

		if data.Age >= ROCKET_HARD_CLEANUP_TIME
			or data.Position.Y <= MIN_Y
		then
			activeRockets[rocket] = nil
			rocket:Destroy()
			continue
		end

		local oldPosition = data.Position

		-- Booster accelerates the ROCKET RELATIVE TO THE CARRIER.
		-- Max_speed is the rocket's own propulsion speed, not a cap on total
		-- world speed. The inherited aircraft velocity is therefore preserved.
		if data.BoosterTime > 0
			and data.Age <= data.BoosterTime
			and data.MaxSpeed > 0
		then
			local boosterAcceleration =
				data.MaxSpeed / data.BoosterTime

			local oldRelativeSpeed =
				data.RocketRelativeSpeed or 0

			local newRelativeSpeed =
				math.min(
					data.MaxSpeed,
					oldRelativeSpeed + boosterAcceleration * dt
				)

			local addedRelativeSpeed =
				newRelativeSpeed - oldRelativeSpeed

			if addedRelativeSpeed > 0 then
				data.Velocity +=
					data.LaunchDirection
					* addedRelativeSpeed
			end

			data.RocketRelativeSpeed = newRelativeSpeed
		end

		-- Rocket-specific gravity.
		data.Velocity +=
			Vector3.new(0, -data.Gravity, 0)
			* dt

		-- Same quadratic drag convention as bullets.
		local speed = data.Velocity.Magnitude
		if data.Drag > 0 and speed > 0.001 then
			local dragFactor =
				data.Drag
				* speed
				* dt

			dragFactor =
				math.clamp(
					dragFactor,
					0,
					0.95
				)

			data.Velocity *= (1 - dragFactor)
		end

		local newPosition =
			oldPosition
			+ data.Velocity * dt

		local delta =
			newPosition
			- oldPosition

		local result =
			Workspace:Raycast(
				oldPosition,
				delta,
				data.RaycastParams
			)

		if result then
			data.LastHitInstance = result.Instance
			explodeRocket(data, result.Position)
			continue
		end

		data.Position = newPosition

		local visualDirection =
			data.Velocity.Magnitude > 0.01
			and data.Velocity.Unit
			or data.LaunchDirection

		local look =
			CFrame.lookAt(
				newPosition,
				newPosition + visualDirection
			)

		rocket:PivotTo(
			look
			* data.AxisCorrection
		)
	end

end)

return ProjectileManager
