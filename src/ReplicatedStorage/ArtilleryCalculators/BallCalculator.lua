-- BallCalculator.lua
-- Place as a ModuleScript:
-- ReplicatedStorage/ArtilleryCalculators/BallCalculator
--
-- Approximate trajectory calculator for conventional artillery:
-- initial muzzle velocity -> gravity -> quadratic drag -> position.
-- No booster phase.

local BallCalculator = {}

local DRAG_SCALE = 0.1
local DEFAULT_GRAVITY = 9.8
local DEFAULT_DT = 1 / 60
local DEFAULT_MAX_TIME = 120

local function numberAttr(instance, names, default)
	if not instance then
		return default
	end

	for _, name in ipairs(names) do
		local value = tonumber(
			instance:GetAttribute(name)
		)

		if value ~= nil then
			return value
		end
	end

	return default
end

function BallCalculator.Calculate(ammo, launchDirection, options)
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

	local muzzleSpeed = math.max(
		0,
		numberAttr(
			ammo,
			{
				"Muzzle_speed",
				"Initial_speed",
				"Speed",
			},
			0
		)
	)

	local gravity = math.max(
		0,
		numberAttr(
			ammo,
			{"Gravity"},
			DEFAULT_GRAVITY
		)
	)

	local rawDrag = math.max(
		0,
		numberAttr(
			ammo,
			{"Projectile_drag"},
			0
		)
	)

	local drag = rawDrag * DRAG_SCALE

	local position = Vector3.zero
	local velocity = direction * muzzleSpeed
	local age = 0

	local apex = 0
	local previousPosition = position

	if muzzleSpeed <= 0 then
		return nil
	end

	while age < maxTime do
		age += dt
		previousPosition = position

		-- Gravity.
		velocity += Vector3.new(
			0,
			-gravity,
			0
		) * dt

		-- Same quadratic drag convention as ProjectileManager.
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

		if age > 0.05
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

return BallCalculator

