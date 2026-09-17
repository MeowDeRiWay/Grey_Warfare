local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local REGION_FOLDER_NAME = "Region_owners"
local GUI_NAME = "FlagCaptureGui"
local UPDATE_INTERVAL = 0.05
local TOAST_TIME = 4

local accumulator = 0
local toastSerial = 0

local function getPlayerTeamOwner()
	local attr = player:GetAttribute("TeamOwner")
	if attr ~= nil then
		return tonumber(attr)
	end

	local teamValue = player:GetAttribute("Team")
	if teamValue ~= nil then
		return tonumber(teamValue)
	end

	if player.Team then
		local teamAttr = player.Team:GetAttribute("TeamOwner")
		if teamAttr ~= nil then
			return tonumber(teamAttr)
		end

		local teamNumber = tonumber(player.Team.Name)
		if teamNumber then
			return teamNumber
		end

		local lowerName = string.lower(player.Team.Name)

		if lowerName == "red" or lowerName == "червоні" or lowerName == "червона" then
			return 1
		end

		if lowerName == "blue" or lowerName == "сині" or lowerName == "синя" then
			return 2
		end
	end

	return nil
end

local function getRoot()
	local character = player.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
		or character.PrimaryPart
end

local function getFlagMain(flag)
	local main = flag:FindFirstChild("Main")
	if main and main:IsA("BasePart") then
		return main
	end

	return flag.PrimaryPart or flag:FindFirstChildWhichIsA("BasePart")
end

local function isBaseFlag(flag)
	return string.sub(flag.Name, 1, 5) == "BASE_"
end

local function getShowName(flag)
	local showName = flag:GetAttribute("Show_name")
	if typeof(showName) == "string" and showName ~= "" then
		return showName
	end

	return flag.Name
end

local function getRadius(flag)
	return math.max(1, tonumber(flag:GetAttribute("OwnershipRadius")) or 150)
end

local function getNearestFlagInRange()
	local folder = Workspace:FindFirstChild(REGION_FOLDER_NAME)
	local root = getRoot()

	if not folder or not root then
		return nil
	end

	local bestFlag = nil
	local bestDistance = math.huge

	for _, flag in ipairs(folder:GetChildren()) do
		if flag:IsA("Model") and not isBaseFlag(flag) then
			local main = getFlagMain(flag)

			if main then
				local distance = (root.Position - main.Position).Magnitude
				if distance <= getRadius(flag) and distance < bestDistance then
					bestDistance = distance
					bestFlag = flag
				end
			end
		end
	end

	return bestFlag
end

local oldGui = playerGui:FindFirstChild(GUI_NAME)
if oldGui then
	oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = playerGui

local captureFrame = Instance.new("Frame")
captureFrame.Name = "Capture"
captureFrame.AnchorPoint = Vector2.new(0.5, 0)
captureFrame.Position = UDim2.new(0.5, 0, 0, 24)
captureFrame.Size = UDim2.fromOffset(440, 90)
captureFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
captureFrame.BackgroundTransparency = 0.15
captureFrame.BorderSizePixel = 0
captureFrame.Visible = false
captureFrame.Parent = gui

local captureCorner = Instance.new("UICorner")
captureCorner.CornerRadius = UDim.new(0, 8)
captureCorner.Parent = captureFrame

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(12, 6)
title.Size = UDim2.new(1, -24, 0, 28)
title.Font = Enum.Font.GothamBold
title.TextColor3 = Color3.new(1, 1, 1)
title.TextScaled = true
title.Text = "Region"
title.Parent = captureFrame

local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Position = UDim2.fromOffset(12, 34)
status.Size = UDim2.new(1, -24, 0, 20)
status.Font = Enum.Font.Gotham
status.TextColor3 = Color3.fromRGB(220, 220, 220)
status.TextScaled = true
status.Text = ""
status.Parent = captureFrame

local barBack = Instance.new("Frame")
barBack.Position = UDim2.fromOffset(12, 61)
barBack.Size = UDim2.new(1, -24, 0, 17)
barBack.BackgroundColor3 = Color3.fromRGB(55, 55, 62)
barBack.BorderSizePixel = 0
barBack.Parent = captureFrame

local barBackCorner = Instance.new("UICorner")
barBackCorner.CornerRadius = UDim.new(0, 6)
barBackCorner.Parent = barBack

local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
barFill.BorderSizePixel = 0
barFill.Parent = barBack

local barFillCorner = Instance.new("UICorner")
barFillCorner.CornerRadius = UDim.new(0, 6)
barFillCorner.Parent = barFill

local toast = Instance.new("TextLabel")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 125)
toast.Size = UDim2.fromOffset(520, 54)
toast.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
toast.BackgroundTransparency = 1
toast.TextTransparency = 1
toast.TextStrokeTransparency = 1
toast.BorderSizePixel = 0
toast.Font = Enum.Font.GothamBold
toast.TextColor3 = Color3.new(1, 1, 1)
toast.TextScaled = true
toast.Visible = false
toast.Parent = gui

local toastCorner = Instance.new("UICorner")
toastCorner.CornerRadius = UDim.new(0, 8)
toastCorner.Parent = toast

local function showToast(text)
	toastSerial += 1
	local serial = toastSerial

	toast.Text = text
	toast.Visible = true
	toast.BackgroundTransparency = 0.15
	toast.TextTransparency = 0
	toast.TextStrokeTransparency = 0.5

	task.delay(TOAST_TIME, function()
		if serial ~= toastSerial or not toast.Parent then
			return
		end

		local tween = TweenService:Create(
			toast,
			TweenInfo.new(0.4),
			{
				BackgroundTransparency = 1,
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}
		)

		tween:Play()
		tween.Completed:Wait()

		if serial == toastSerial then
			toast.Visible = false
		end
	end)
end

local function updateCaptureUi()
	local flag = getNearestFlagInRange()

	if not flag then
		captureFrame.Visible = false
		return
	end

	captureFrame.Visible = true
	title.Text = getShowName(flag)

	local team = getPlayerTeamOwner()
	local owner = tonumber(flag:GetAttribute("TeamOwner")) or 0
	local captureTeam = tonumber(flag:GetAttribute("CaptureTeam")) or 0
	local progress = math.max(0, tonumber(flag:GetAttribute("CaptureProgress")) or 0)
	local captureTime = math.max(0.1, tonumber(flag:GetAttribute("Capture_time")) or 10)
	local contested = flag:GetAttribute("Contested") == true
	local destroyed = flag:GetAttribute("Destroyed") == true
	local fraction = math.clamp(progress / captureTime, 0, 1)

	if destroyed then
		status.Text = "ПРАПОР ЗБИТО"
		barFill.Size = UDim2.fromScale(0, 1)
		return
	end

	if contested then
		status.Text = string.format(
			"СПІРНА ТОЧКА  •  %.1f с",
			math.max(0, captureTime - progress)
		)
		barFill.Size = UDim2.fromScale(fraction, 1)
		return
	end

	if team and owner == team then
		status.Text = "РЕГІОН ПІД КОНТРОЛЕМ"
		barFill.Size = UDim2.fromScale(1, 1)
		return
	end

	if captureTeam ~= 0 and team and captureTeam ~= team then
		status.Text = string.format(
			"ВОРОГ ЗАХОПЛЮЄ  •  %.1f с",
			math.max(0, captureTime - progress)
		)
		barFill.Size = UDim2.fromScale(fraction, 1)
		return
	end

	local phaseText = owner == 0 and "ЗАХОПЛЕННЯ" or "НЕЙТРАЛІЗАЦІЯ"
	status.Text = string.format(
		"%s  •  %.1f с",
		phaseText,
		math.max(0, captureTime - progress)
	)
	barFill.Size = UDim2.fromScale(fraction, 1)
end

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local notificationRemote = remotes:WaitForChild("FlagCaptureNotification")

notificationRemote.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then
		return
	end

	local regionName = tostring(data.RegionName or "Регіон")

	if data.Kind == "Captured" then
		showToast("Регіон захоплено: " .. regionName)
	elseif data.Kind == "Lost" then
		showToast("Регіон втрачено: " .. regionName)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	accumulator += dt

	if accumulator < UPDATE_INTERVAL then
		return
	end

	accumulator = 0
	updateCaptureUi()
end)
