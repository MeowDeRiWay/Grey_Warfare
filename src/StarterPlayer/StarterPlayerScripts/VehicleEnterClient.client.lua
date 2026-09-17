local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local enterRemote = remotes:WaitForChild("VehicleEnterRequest")

local ENTER_DISTANCE = 6
local UPDATE_RATE = 0.08

local currentVehicle = nil
local accumulator = 0

-- =========================================================
-- GUI
-- =========================================================

local gui = Instance.new("ScreenGui")
gui.Name = "VehicleEnterGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local hint = Instance.new("TextLabel")
hint.Name = "Hint"
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -110)
hint.Size = UDim2.new(0, 320, 0, 42)
hint.BackgroundTransparency = 0.3
hint.BorderSizePixel = 0
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 20
hint.TextColor3 = Color3.new(1, 1, 1)
hint.TextStrokeTransparency = 0.6
hint.Text = "E — Enter vehicle"
hint.Visible = false
hint.Parent = gui

-- =========================================================
-- HELPERS
-- =========================================================

local function getCharacter()
	return player.Character
end

local function getHumanoid()
	local character = getCharacter()
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function getRootPart()
	local character = getCharacter()
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

local function getDriverSeat(vehicle)
	if not vehicle then
		return nil
	end

	local seat = vehicle:FindFirstChild("Driver_seat", true)
	if seat and (seat:IsA("VehicleSeat") or seat:IsA("Seat")) then
		return seat
	end

	return nil
end

local function pointToModelDistance(vehicle, worldPoint)
	local boxCFrame, boxSize = vehicle:GetBoundingBox()
	local localPoint = boxCFrame:PointToObjectSpace(worldPoint)
	local half = boxSize * 0.5

	local closest = Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	)

	return (localPoint - closest).Magnitude
end

local function canUseVehicleLocally(vehicle)
	if not vehicle or not vehicle.Parent then
		return false
	end

	local seat = getDriverSeat(vehicle)
	if not seat then
		return false
	end

	if seat.Occupant ~= nil then
		return false
	end

	local ownerUserId = vehicle:GetAttribute("OwnerUserId")
	if ownerUserId ~= nil and tonumber(ownerUserId) ~= player.UserId then
		return false
	end

	return true
end

local function findNearestVehicle()
	local humanoid = getHumanoid()
	local root = getRootPart()

	if not humanoid or not root then
		return nil
	end

	-- Уже сидимо — підказка входу не потрібна.
	if humanoid.SeatPart then
		return nil
	end

	local folder = workspace:FindFirstChild("ActiveVehicles")
	if not folder then
		return nil
	end

	local bestVehicle = nil
	local bestDistance = ENTER_DISTANCE

	for _, vehicle in ipairs(folder:GetChildren()) do
		if vehicle:IsA("Model") and canUseVehicleLocally(vehicle) then
			local distance = pointToModelDistance(vehicle, root.Position)

			if distance <= bestDistance then
				bestDistance = distance
				bestVehicle = vehicle
			end
		end
	end

	return bestVehicle
end

local function updateHint()
	currentVehicle = findNearestVehicle()

	if currentVehicle then
		hint.Visible = true
		hint.Text = "E — Enter " .. currentVehicle.Name
	else
		hint.Visible = false
	end
end

-- =========================================================
-- INPUT
-- =========================================================

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode ~= Enum.KeyCode.E then
		return
	end

	local humanoid = getHumanoid()
	if not humanoid then
		return
	end

	-- E enters when standing nearby and exits when already seated.
	if humanoid.SeatPart then
		humanoid.Sit = false
		return
	end

	if currentVehicle and currentVehicle.Parent then
		enterRemote:FireServer(currentVehicle)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	accumulator += dt
	if accumulator < UPDATE_RATE then
		return
	end

	accumulator = 0
	updateHint()
end)

player.CharacterAdded:Connect(function()
	currentVehicle = nil
	hint.Visible = false
end)
