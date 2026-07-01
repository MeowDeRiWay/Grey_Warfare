local VehicleAccess = {}

function VehicleAccess.GetPlayerTeamOwner(player)
	local attr = player:GetAttribute("TeamOwner")
	if attr ~= nil then
		return attr
	end

	local teamValue = player:GetAttribute("Team")
	if teamValue ~= nil then
		return teamValue
	end

	if player.Team then
		local teamAttr = player.Team:GetAttribute("TeamOwner")
		if teamAttr ~= nil then
			return teamAttr
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

		if lowerName == "seal" then
			return 3
		end
	end

	return nil
end

function VehicleAccess.CanUseTeamObject(player, object)
	local playerTeamOwner = VehicleAccess.GetPlayerTeamOwner(player)
	local objectTeamOwner = object:GetAttribute("TeamOwner")

	if objectTeamOwner == nil then
		warn("[VehicleAccess] Object has no TeamOwner:", object:GetFullName())
		return false
	end

	if playerTeamOwner == nil then
		warn("[VehicleAccess] Player has no TeamOwner:", player.Name)
		return false
	end

	return tonumber(playerTeamOwner) == tonumber(objectTeamOwner)
end

return VehicleAccess