local TeamColors = {}

TeamColors.Neutral = 0
TeamColors.Red = 1
TeamColors.Blue = 2

TeamColors.Colors = {
	[0] = Color3.fromRGB(150, 150, 150), -- Neutral
	[1] = Color3.fromRGB(220, 40, 40),  -- Red
	[2] = Color3.fromRGB(40, 90, 220),  -- Blue
}

function TeamColors.GetColor(teamId)
	return TeamColors.Colors[teamId] or TeamColors.Colors[0]
end

return TeamColors