local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ProjectileManager = {}

local PROJECTILES_FOLDER_NAME = "Projectiles"
local HARD_CLEANUP_TIME = 15
local MIN_Y = -500

local activeProjectiles = {}

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
		if current:GetAttribute("Current_health") ~= nil or current:GetAttribute("Health") ~= nil then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function applyDamage(target, damage)
	if not target or damage <= 0 then
		return
	end

	local currentHealth = target:GetAttribute("Current_health")
	if currentHealth ~= nil then
		target:SetAttribute("Current_health", math.max(0, tonumber(currentHealth) - damage))
		return
	end

	local health = target:GetAttribute("Health")
	if health ~= nil then
		target:SetAttribute("Health", math.max(0, tonumber(health) - damage))
	end
end

function ProjectileManager.FireBullet(config)
	local origin = config.Origin
	local direction = config.Direction
	local owner = config.Owner
	local weapon = config.Weapon

	if typeof(origin) ~= "Vector3" then
		return nil
	end

	if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.01 then
		return nil
	end

	local speed = tonumber(config.Speed) or 180
	local gravity = tonumber(config.Gravity) or 60
	local damage = tonumber(config.Damage) or 10
	local size = tonumber(config.Size) or 0.15

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
		Gravity = gravity,
		Damage = damage,
		RaycastParams = params,
		Age = 0,
	}

	return projectilePart
end

RunService.Heartbeat:Connect(function(dt)
	for projectilePart, data in pairs(activeProjectiles) do
		if not projectilePart.Parent then
			activeProjectiles[projectilePart] = nil
			continue
		end

		data.Age += dt
		if data.Age >= HARD_CLEANUP_TIME or data.Position.Y <= MIN_Y then
			activeProjectiles[projectilePart] = nil
			projectilePart:Destroy()
			continue
		end

		local oldPosition = data.Position
		data.Velocity += Vector3.new(0, -data.Gravity, 0) * dt
		local newPosition = oldPosition + data.Velocity * dt
		local delta = newPosition - oldPosition

		local result = Workspace:Raycast(oldPosition, delta, data.RaycastParams)
		if result then
			local target = findDamageTarget(result.Instance)
			if target then
				applyDamage(target, data.Damage)
			end

			activeProjectiles[projectilePart] = nil
			projectilePart:Destroy()
			continue
		end

		data.Position = newPosition
		projectilePart.CFrame = CFrame.new(newPosition)
	end
end)

return ProjectileManager
