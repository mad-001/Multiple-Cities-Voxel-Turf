# Double Tap Cities — Voxel Turf Map Generation Mod

A server-side map-generation mod for **Voxel Turf** that turns the standard single-city
map into a connected multi-city region: one main city in the center, four satellite
cities to the north/south/east/west, and a full elevated **highway network** with ramps,
traffic-light junctions, AI traffic, and bridges linking them all together — plus a metro
system and guaranteed mission-critical buildings.

## Features

- **Four satellite cities** generated at the N/S/E/W cardinal directions, ~1800 blocks
  out from the main city (auto-fits the map; directions that don't fit are skipped).
- **Elevated highways** connecting the center city to each satellite:
  - Built directionally with `highroad_n/_e` pieces (alternating lit-lamp variants).
  - **4-lot highway ramps** (`hramp`) at each city edge that step the highway down to road
    level.
  - **Traffic-light T-junctions** where every ramp meets the city — always a proper
    signaled junction, even when the edge road turns.
  - **AI traffic**: cars actually drive on the highway and ramps (road data is applied).
  - **Canal bridges** carry the highway flush across water.
  - Flat, height-aligned decks (the highway doesn't follow the terrain bumps).
- **Metro system**: an underground hub station at the main city center plus one station per
  satellite at its inward-facing edge.
- **Guaranteed mission-critical buildings** seeded into the main city (Hospital, Mechanic
  Garage, Caryard, Helifield, S-Mart Department Store, Big Office) so missions always have
  the venues they need.

## Installation

1. Download the latest `MissionBuildings-vX.Y.Z.zip` from the
   [Releases page](../../releases).
2. Extract it so the `MissionBuildings` folder lands in your Voxel Turf **mods** directory:
   ```
   .../Voxel Turf/mods/MissionBuildings/
   ```
3. Enable **MissionBuildings** in the in-game mod list.
4. **Generate a new map** — the mod hooks map generation, so it only takes effect on a
   freshly generated world.

> Note: this is a map-generation mod. It changes what gets built when a world is first
> created; it does not retroactively modify an already-generated map.

## How it works

The mod hooks two map-generation entry points in
`scripts/server/map_generation/mission_buildings_footprints.lua`:

- `get_footprints(...)` — prepends the guaranteed mission buildings to the city footprint
  pool.
- `customFunc.OnMapGen_extra(...)` — after the vanilla city is built, it generates the
  satellites, conforms roads to terrain, then lays the highways and metro **last** (so the
  terrain-conform pass can't flatten the ramps).

Highways are built one direction at a time: each run independently scans the road column
between two cities, finds the wilderness gap between them, and lays a flat highway with a
ramp + traffic-light junction at each end.

## Compatibility

- Uses only **vanilla** Voxel Turf lot pieces (no extra lot packs required).
- Server-side / map-generation only.

## License

Provided as-is for the Voxel Turf community. Use and modify freely.
