local VehicleCatalog = {}

VehicleCatalog.Terminals = {
	VehicleTerminal = {
		FolderName = "Vehicles",
		SpawnPartName = "WSpawn",
		PromptText = "Vehicle Terminal",
		AllowedVehicles = {
			Baggy = true,
			Truck = true,
		},
	},

	HeliTerminal = {
		FolderName = "Heli",
		SpawnPartName = "HSpawn",
		PromptText = "Heli Terminal",
		AllowedVehicles = {
			Cargo_Heli = true,
		},
	},

	PlanePlatform = {
		FolderName = "Planes",
		SpawnPartName = "PSpawn",
		PromptText = "Plane Terminal",
		AllowedVehicles = {
			Interceptor_plane = true,
		},
	},
}

function VehicleCatalog.GetTerminalConfig(objectType)
	return VehicleCatalog.Terminals[objectType]
end

function VehicleCatalog.IsAllowed(objectType, vehicleName)
	local config = VehicleCatalog.GetTerminalConfig(objectType)
	if not config then
		return false
	end

	return config.AllowedVehicles[vehicleName] == true
end

return VehicleCatalog
