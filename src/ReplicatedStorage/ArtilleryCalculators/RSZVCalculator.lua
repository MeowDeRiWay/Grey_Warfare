-- RSZVCalculator.lua
-- Place as a ModuleScript:
-- ReplicatedStorage/ArtilleryCalculators/RSZVCalculator
--
-- Approximate trajectory calculator for rockets with a booster.
-- Physics order mirrors ProjectileManager:
-- booster -> gravity -> quadratic drag -> position.

local RSZVCalculator = {}

local DRAG_SCALE = 0.1
local DEFAULT_GRAVITY = 9.8
local DEFAULT_DT = 1 / 60
local DEFAULT_MAX_TIME = 120

local function numberAttr(instance, name, default)
	if not instance then
		return default
	end

	local value = tonumber(instance:GetAttribute(name))
	if value == nil then
		return default
	end

	return value
end

function RSZVCalculator.Calculate(ammo, launchDirection, options)
	if not ammo or not ammo:IsA("Instance") then
		return nil
	end

	if typeof(launchDirection) ~= "Vector3"
		or launchDirection.Magnitude < 0.001
	then
		return nil
	end

	options = options or {}

	local dt = tonumber(options.dt) or DEFAULT_DT
	local maxTime = tonumber(options.maxTime) or DEFAULT_MAX_TIME

	dt = math.clamp(dt, 1 / 240, 0.1)
	maxTime = math.max(1, maxTime)

	local direction = launchDirection.Unit

	local maxSpeed = math.max(
		0,
		numberAttr(ammo, "Max_speed", 0)
	)

	local boosterTime = math.max(
		0,
		numberAttr(ammo, "Booster_timer", 0)
	)

	local gravity = math.max(
		0,
		numberAttr(ammo, "Gravity", DEFAULT_GRAVITY)
	)

	local rawDrag = math.max(
		0,
		numberAttr(ammo, "Projectile_drag", 0)
	)

	local drag = rawDrag * DRAG_SCALE

	local initialSpeed = math.max(
		0,
		numberAttr(ammo, "Initial_speed", 0)
	)

	local position = Vector3.zero
	local velocity = direction * initialSpeed
	local age = 0

	local apex = 0
	local previousPosition = position

	while age < maxTime do
		age += dt
		previousPosition = position

		-- Same booster convention as ProjectileManager.
		if boosterTime > 0
			and age <= boosterTime
			and maxSpeed > 0
		then
			local boosterAcceleration =
				maxSpeed / boosterTime

			velocity +=
				direction
				* boosterAcceleration
				* dt

			if velocity.Magnitude > maxSpeed then
				velocity =
					velocity.Unit
					* maxSpeed
			end
		end

		-- Rocket-specific gravity.
		velocity += Vector3.new(
			0,
			-gravity,
			0
		) * dt

		-- Same quadratic drag convention.
		local speed = velocity.Magnitude

		if drag > 0 and speed > 0.001 then
			local dragFactor =
				drag
				* speed
				* dt

			dragFactor = math.clamp(
				dragFactor,
				0,
				0.95
			)

			velocity *= (1 - dragFactor)
		end

		position += velocity * dt
		apex = math.max(apex, position.Y)

		-- We calculate range to the launcher's own elevation.
		-- Ignore the first moment while the rocket is still leaving the tube.
		if age > math.max(boosterTime, 0.15)
			and previousPosition.Y > 0
			and position.Y <= 0
		then
			local dy =
				previousPosition.Y
				- position.Y

			local alpha = 0

			if math.abs(dy) > 0.000001 then
				alpha =
					previousPosition.Y
					/ dy
			end

			alpha = math.clamp(alpha, 0, 1)

			local impact =
				previousPosition:Lerp(
					position,
					alpha
				)

			local horizontalRange =
				Vector2.new(
					impact.X,
					impact.Z
				).Magnitude

			local impactTime =
				(age - dt)
				+ dt * alpha

			local pitch =
				math.deg(
					math.asin(
						math.clamp(
							direction.Y,
							-1,
							1
						)
					)
				)

			return {
				Range = horizontalRange,
				FlightTime = impactTime,
				Apex = apex,
				Pitch = pitch,
				Completed = true,
			}
		end
	end

	local horizontalRange =
		Vector2.new(
			position.X,
			position.Z
		).Magnitude

	local pitch =
		math.deg(
			math.asin(
				math.clamp(
					direction.Y,
					-1,
					1
				)
			)
		)

	return {
		Range = horizontalRange,
		FlightTime = age,
		Apex = apex,
		Pitch = pitch,
		Completed = false,
	}
end

return RSZVCalculator

