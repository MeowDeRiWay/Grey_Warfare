# Architecture

Grey Warfare uses Rojo for code synchronization.

## Studio owns

- Workspace map
- Terrain
- Spawn locations
- Static world geometry

## Rojo owns

- ReplicatedStorage
- ServerScriptService
- StarterPlayerScripts
- StarterGui

## Main rule

Do not map the whole Workspace through Rojo unless we intentionally want Rojo to control it.

## Planned systems

- Commander
- Economy
- Capture
- Logistics
- Vehicles
- Infantry
- Weapons
- Radar
- EW
- Air Defense
- Aviation
- FPV
- Artillery