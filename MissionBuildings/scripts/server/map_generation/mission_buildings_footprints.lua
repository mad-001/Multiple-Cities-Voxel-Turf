-- ─── Part 1: Guaranteed mission-critical buildings ───────────────────────────
local _orig_get_footprints = get_footprints

function get_footprints(W, LC, radius, startX, startZ, maxPlayerBases)
	local FP_POOL, nPoolWithMaxConuts = _orig_get_footprints(W, LC, radius, startX, startZ, maxPlayerBases)
	local LPC = turf.LotPackContainer:getInstance()
	local nLPI = LPC:getNLotPackItems()

	-- NOTE: buildings we never want to auto-spawn are handled in no_spawn_buildings.lua
	-- (loaded before this file), which flags their doNotSpawn. Edit the list there.

	local guaranteed = {
		{ name = "Hospital",                cat = turf.LotPackItem.LPI_CAT_COMMERCE },
		{ name = "Mechanic Garage",         cat = turf.LotPackItem.LPI_CAT_COMMERCE },
		{ name = "Caryard",                 cat = turf.LotPackItem.LPI_CAT_COMMERCE },
		{ name = "S-Mart Department Store", cat = turf.LotPackItem.LPI_CAT_COMMERCE },
	}
	for _, entry in ipairs(guaranteed) do
		local lpis = {}
		local xs, zs = 1, 1
		for i = 0, nLPI - 1 do
			local LPI = LPC:get(i)
			if LPI.name == entry.name and LPI.cat == entry.cat and not LPI.doNotSpawn then
				if #lpis == 0 then xs = LPI.footprintXsz; zs = LPI.footprintZsz end
				lpis[#lpis + 1] = i
			end
		end
		if #lpis > 0 then
			table.insert(FP_POOL, 1, {
				xs = xs, zs = zs, maxcount = 1, count = 0,
				lpis = lpis, lotTypes = { entry.cat }, doNotUseRndLocOffset = true,
			})
			nPoolWithMaxConuts = nPoolWithMaxConuts + 1
		end
	end
	return FP_POOL, nPoolWithMaxConuts
end


-- ─── Part 2: Terrain height sampler ──────────────────────────────────────────
local function getTerrainHeight(W, LC, wx, wz)
	local CC = W:getChunkContainer()
	if not CC then return 10 end
	local C = CC:getChunkAt(wx, wz)
	if not C then return 10 end
	local Biome = LC:getBiomeAt(wx, wz)
	if not Biome then return 10 end
	local g1 = Biome.baseBlock
	local g2 = Biome.hillsBaseBlock
	local lx = wx - C:getX()
	local lz = wz - C:getZ()
	for y = 40, 5, -1 do
		local b = C:getBlockIdentifierAt(lx, y, lz)
		if b == g1 or b == g2 then return y + 1 end
	end
	return 10
end


-- ─── Part 3: Road piece selection ────────────────────────────────────────────
local function roadPiece(n, s, e, w, lx, lz, LSZ)
	local cnt = (n and 1 or 0) + (s and 1 or 0) + (e and 1 or 0) + (w and 1 or 0)
	local altNS = (math.floor(lx / LSZ) % 4 == 0) and "neven" or "nodd"
	local altEW = (math.floor(lz / LSZ) % 4 == 0) and "eeven" or "eodd"
	if cnt >= 4 then return "cross", 'n' end
	if cnt == 3 then
		if not s then return "jnew", 'n' end
		if not n then return "jsew", 'n' end
		if not w then return "jnse", 'n' end
		return "jnsw", 'n'
	end
	if cnt == 2 then
		if n and s then return altNS, 'n' end
		if e and w then return altEW, 'n' end
		if n and e then return "cne", 'n' end
		if n and w then return "cnw", 'n' end
		if s and e then return "cse", 'n' end
		return "csw", 'n'
	end
	if e or w then return altEW, 'n' end
	return altNS, 'n'
end


-- ─── Part 4: Terrain-conforming road post-processor ──────────────────────────
-- Regular ramps: 4 lots long, 6 blocks tall. Direction in filename (rampup1='n').
local RAMP_LOTS   = 4
local RAMP_HEIGHT = 6

local function conformRoadsToTerrain(W, LC, Net, cx, cz, radius)
	local LSZ = turf.Lot.LOT_SIZE
	local x0 = cx - radius; x0 = x0 - (x0 % LSZ)
	local z0 = cz - radius; z0 = z0 - (z0 % LSZ)
	local x1 = cx + radius
	local z1 = cz + radius

	-- Pass 1: record terrain height for every road lot in the scan area.
	local th = {}
	local tick = 0
	local x = x0
	while x <= x1 do
		local z = z0
		while z <= z1 do
			local L = LC:getLotAt(x, z)
			if L and L.vtype == turf.Lot.LOT_ROAD then
				if not th[x] then th[x] = {} end
				th[x][z] = getTerrainHeight(W, LC,
					x + math.floor(LSZ / 2), z + math.floor(LSZ / 2))
			end
			z = z + LSZ
		end
		x = x + LSZ
		tick = tick + 1
		if tick % 32 == 0 then Net:doKeepAlive() end
	end

	-- Pass 2a: place ramps on straight segments where the terrain rises exactly
	-- RAMP_HEIGHT blocks across RAMP_LOTS lot-widths (from the LOW end only).
	local rampCovered = {}

	local function keyOf(rx, rz) return rx .. "," .. rz end

	local function clearRoadLot(rx, rz)
		local L = LC:getLotAt(rx, rz)
		if L and L.vtype == turf.Lot.LOT_ROAD then
			local old = L.vtype
			L:clearData(LC); L.vtype = turf.Lot.LOT_VACANT
			LC:markUpdate(rx, rz, old, L.vtype)
		end
	end

	local function placeRamp(rx, rz, ry, pieceName, dir, isNS)
		for i = 1, RAMP_LOTS - 1 do
			local mx = isNS and rx or (rx + i * LSZ)
			local mz = isNS and (rz + i * LSZ) or rz
			clearRoadLot(mx, mz)
		end
		clearRoadLot(rx, rz)
		LC:loadLot(rx, rz, ry, "road/rf/" .. pieceName, dir, turf.Lot.LOT_FILL_MODE_NORMAL)
		local newL = LC:getLotAt(rx, rz)
		if newL then
			local LRD = turf.LotRoadData.genNew()
			LRD:set(isNS, isNS, not isNS, not isNS)
			newL.vtype = turf.Lot.LOT_ROAD
			newL.lotData = LRD
		end
		for i = 0, RAMP_LOTS - 1 do
			local mx = isNS and rx or (rx + i * LSZ)
			local mz = isNS and (rz + i * LSZ) or rz
			rampCovered[keyOf(mx, mz)] = true
		end
	end

	for rx, col in pairs(th) do
		for rz, ry in pairs(col) do
			if rampCovered[keyOf(rx, rz)] then goto continue_ramp end

			local hasN = col[rz + LSZ] ~= nil
			local hasS = col[rz - LSZ] ~= nil
			local hasE = th[rx + LSZ] ~= nil and th[rx + LSZ][rz] ~= nil
			local hasW = th[rx - LSZ] ~= nil and th[rx - LSZ][rz] ~= nil

			-- Northward uphill: 4 lots north is exactly RAMP_HEIGHT higher.
			if hasN and hasS and not hasE and not hasW then
				local farY = col[rz + RAMP_LOTS * LSZ]
				if farY and farY - ry == RAMP_HEIGHT then
					local ok = true
					for i = 1, RAMP_LOTS - 1 do
						local mz = rz + i * LSZ
						if not col[mz] then ok = false; break end
						if rampCovered[keyOf(rx, mz)] then ok = false; break end
						if (th[rx + LSZ] and th[rx + LSZ][mz])
						or (th[rx - LSZ] and th[rx - LSZ][mz]) then
							ok = false; break
						end
					end
					if ok then placeRamp(rx, rz, ry, "rampup1", 'n', true) end
				end
			end

			-- Eastward uphill: 4 lots east is exactly RAMP_HEIGHT higher.
			if hasE and hasW and not hasN and not hasS then
				local farCol = th[rx + RAMP_LOTS * LSZ]
				local farY   = farCol and farCol[rz]
				if farY and farY - ry == RAMP_HEIGHT then
					local ok = true
					for i = 1, RAMP_LOTS - 1 do
						local mx = rx + i * LSZ
						local mc = th[mx]
						if not (mc and mc[rz]) then ok = false; break end
						if rampCovered[keyOf(mx, rz)] then ok = false; break end
						if mc[rz + LSZ] or mc[rz - LSZ] then ok = false; break end
					end
					if ok then placeRamp(rx, rz, ry, "rampup1", 'e', false) end
				end
			end

			::continue_ramp::
		end
		Net:doKeepAlive()
	end

	-- Pass 2b: move non-ramp road lots to terrain height.
	for rx, col in pairs(th) do
		for rz, ry in pairs(col) do
			if rampCovered[keyOf(rx, rz)] then goto continue_road end
			if ry == 10 then goto continue_road end

			local hasN = col[rz + LSZ] ~= nil
			local hasS = col[rz - LSZ] ~= nil
			local hasE = th[rx + LSZ] ~= nil and th[rx + LSZ][rz] ~= nil
			local hasW = th[rx - LSZ] ~= nil and th[rx - LSZ][rz] ~= nil
			local piece, dir = roadPiece(hasN, hasS, hasE, hasW, rx, rz, LSZ)

			local L = LC:getLotAt(rx, rz)
			if L then
				local old = L.vtype
				L:clearData(LC); L.vtype = turf.Lot.LOT_VACANT
				LC:markUpdate(rx, rz, old, L.vtype)
				LC:loadLot(rx, rz, ry, "road/rf/" .. piece, dir, turf.Lot.LOT_FILL_MODE_NORMAL)
				local newL = LC:getLotAt(rx, rz)
				if newL then
					local LRD = turf.LotRoadData.genNew()
					LRD:set(hasN, hasS, hasE, hasW)
					newL.vtype = turf.Lot.LOT_ROAD
					newL.lotData = LRD
				end
			end

			::continue_road::
		end
		Net:doKeepAlive()
	end
end


-- ─── Part 5: City configuration ──────────────────────────────────────────────
local MAIN_CITY_RADIUS = 500   -- vanilla default
local SAT_CITY_RADIUS  = 500

-- Capture generator before the game nulls it after vanilla map gen.
local _orig_generate_city = generate_city


-- ─── Part 6: Highway placement ───────────────────────────────────────────────
local function isHighwayPlaceable(vt)
	return vt == turf.Lot.LOT_VACANT
	    or vt == turf.Lot.LOT_HILLS
	    or vt == turf.Lot.LOT_SEA
	    or vt == turf.Lot.LOT_ROAD
end

local function inCityRadius(x, z, centers)
	for _, c in ipairs(centers) do
		local dx = x - c.x; local dz = z - c.z
		if dx * dx + dz * dz < c.r * c.r then return true end
	end
	return false
end

-- Returns true for any city development: roads (city grid edge) or buildings.
-- Excludes plain terrain (VACANT, HILLS, SEA) and already-placed HIGHWAY lots.
local function isCityLot(LC, x, z)
	local L = LC:getLotAt(x, z)
	if not L then return false end
	local vt = L.vtype
	return vt ~= turf.Lot.LOT_VACANT
		and vt ~= turf.Lot.LOT_HILLS
		and vt ~= turf.Lot.LOT_SEA
		and vt ~= turf.Lot.LOT_HIGHWAY
end

local function isRoadLot(LC, x, z)
	local L = LC:getLotAt(x, z)
	return L ~= nil and L.vtype == turf.Lot.LOT_ROAD
end

-- Cross-TL junction coordinates recorded by buildHighwayZ/buildHighwayX as they run, so the
-- ring-loop builder (Part 6c) can join the 4 junctions. .east/.west/.north/.south = {x,z};
-- .y = the shared elevated deck level (all 4 highways use lotHeight(0,0)).
local _mb_crosses = {}

-- Places a 4-lot highway ramp (hramp*) along x=fx, anchored at anchorZ. hramp is itself
-- a 4-lot piece, so the 3 following lots must be cleared first or the highway/terrain
-- would overwrite them and leave only 1 lot of ramp. Placed at the highway level baseY.
local function place4LotRampNS(LC, fx, anchorZ, piece, baseY)
	local LSZ = turf.Lot.LOT_SIZE
	for i = 0, 3 do
		local zz = anchorZ + i * LSZ
		local L = LC:getLotAt(fx, zz)
		if L then
			local old = L.vtype
			L:clearData(LC); L.vtype = turf.Lot.LOT_VACANT
			LC:markUpdate(fx, zz, old, L.vtype)
		end
	end
	LC:loadLot(fx, anchorZ, baseY, piece, 'n', turf.Lot.LOT_FILL_MODE_NORMAL)
	-- Road data so AI cars use the ramp: low connection on the city side, high on the
	-- highway side. hramp2 = road E / highway W, hramp4 = road W / highway E.
	local lE, lW, hE, hW = false, false, false, false
	if piece == "packs/vanilla/hramp2" then lE, hW = true, true
	elseif piece == "packs/vanilla/hramp4" then lW, hE = true, true end
	for i = 0, 3 do
		local L = LC:getLotAt(fx, anchorZ + i * LSZ)
		if L then
			local LRD = turf.LotRoadData.genNew()
			LRD:set2(false, false, lE, lW, false, false, hE, hW)
			L.vtype = turf.Lot.LOT_ROAD
			L.lotData = LRD
		end
	end
end

-- x-axis (north/south) mirror of place4LotRampNS: the 4 ramp lots lay out along x at
-- fixed z=fz. hramp1 = road S / highway N, hramp3 = road N / highway S.
local function place4LotRampX(LC, fz, anchorX, piece, baseY)
	local LSZ = turf.Lot.LOT_SIZE
	for i = 0, 3 do
		local xx = anchorX + i * LSZ
		local L = LC:getLotAt(xx, fz)
		if L then
			local old = L.vtype
			L:clearData(LC); L.vtype = turf.Lot.LOT_VACANT
			LC:markUpdate(xx, fz, old, L.vtype)
		end
	end
	LC:loadLot(anchorX, fz, baseY, piece, 'n', turf.Lot.LOT_FILL_MODE_NORMAL)
	local lN, lS, hN, hS = false, false, false, false
	if piece == "packs/vanilla/hramp1" then lS, hN = true, true
	elseif piece == "packs/vanilla/hramp3" then lN, hS = true, true end
	for i = 0, 3 do
		local L = LC:getLotAt(anchorX + i * LSZ, fz)
		if L then
			local LRD = turf.LotRoadData.genNew()
			LRD:set2(lN, lS, false, false, hN, hS, false, false)
			L.vtype = turf.Lot.LOT_ROAD
			L.lotData = LRD
		end
	end
end

local function lotHeight(W, LC, x, z)
	local LSZ = turf.Lot.LOT_SIZE
	return getTerrainHeight(W, LC, x + math.floor(LSZ / 2), z + math.floor(LSZ / 2))
end

-- Place a highway lot; skips if the position is already a highway (use forceHighwayLot to overwrite).
local function placeHighwayLot(LC, W, x, z, lotPath, dir)
	local L = LC:getLotAt(x, z)
	if not L then return end
	local vt = L.vtype
	if vt == turf.Lot.LOT_HIGHWAY then return end
	if not isHighwayPlaceable(vt) then return end
	local old = vt
	L:clearData(LC)
	L.vtype = turf.Lot.LOT_VACANT
	LC:markUpdate(x, z, old, L.vtype)
	LC:loadLot(x, z, lotHeight(W, LC, x, z), lotPath, dir, turf.Lot.LOT_FILL_MODE_NORMAL)
end

-- Overwrites any existing lot. fixedY forces a flat elevation (optional; defaults to terrain height).
local function forceHighwayLot(LC, W, x, z, lotPath, dir, fixedY)
	local L = LC:getLotAt(x, z)
	if not L then return end
	local old = L.vtype
	L:clearData(LC)
	L.vtype = turf.Lot.LOT_VACANT
	LC:markUpdate(x, z, old, L.vtype)
	local y = fixedY ~= nil and fixedY or lotHeight(W, LC, x, z)
	LC:loadLot(x, z, y, lotPath, dir, turf.Lot.LOT_FILL_MODE_NORMAL)
end

-- Replaces the plain edge road a ramp lands on with the traffic-light junction that
-- matches the city road's ACTUAL connections, so it stays correct even when the edge
-- road turned (T, 4-way, or a corner). In VoxelTurf's frame z = east/west, x = north/
-- south, so N/S = +/-x and E/W = +/-z. rampFrom is the side the ramp joins from ('e'/'w').
local function placeRampJunction(LC, W, fx, z, rampFrom)
	local LSZ = turf.Lot.LOT_SIZE
	local n = (rampFrom == 'n') or isRoadLot(LC, fx + LSZ, z)  -- +x = north
	local s = (rampFrom == 's') or isRoadLot(LC, fx - LSZ, z)  -- -x = south
	local e = (rampFrom == 'e') or isRoadLot(LC, fx, z + LSZ)  -- +z = east
	local w = (rampFrom == 'w') or isRoadLot(LC, fx, z - LSZ)  -- -z = west
	local cnt = (n and 1 or 0) + (s and 1 or 0) + (e and 1 or 0) + (w and 1 or 0)
	-- The ramp base must ALWAYS be a traffic-light T. If the edge road is degenerate
	-- (a corner, or collinear with the ramp, giving <3 connections), force the through-
	-- road perpendicular to the ramp so a proper TL junction is chosen instead of a curve.
	if cnt < 3 then
		if rampFrom == 'n' or rampFrom == 's' then e = true; w = true
		else n = true; s = true end
		cnt = (n and 1 or 0) + (s and 1 or 0) + (e and 1 or 0) + (w and 1 or 0)
	end
	local piece, dir = nil, 'n'
	if cnt >= 4 then
		piece = "packs/vanilla/road_crosstl"        -- N,S,E,W + TL
	else                                            -- cnt == 3
		if not w then piece = "packs/vanilla/road_jnse_tl"      -- N,S,E
		elseif not e then piece = "packs/vanilla/road_jnsw_tl"  -- N,S,W
		elseif not s then piece = "packs/vanilla/road_jnew_tl"  -- N,E,W
		else piece = "packs/vanilla/road_jsew_tl" end           -- S,E,W
	end
	forceHighwayLot(LC, W, fx, z, piece, dir, lotHeight(W, LC, fx, z))
	local L = LC:getLotAt(fx, z)
	if L then
		local LRD = turf.LotRoadData.genNew()
		LRD:set(n, s, e, w)
		L.vtype = turf.Lot.LOT_ROAD
		L.lotData = LRD
	end
end

-- E/W backbone at z=fz. Uses isCityLot to stop exactly at actual city buildings.
-- baseY keeps it flat. Ramps sit directly adjacent to the city edge (no gap lot).
-- juncXSet positions skipped by caller.
local function buildHighwayEW(LC, Net, W, fz, juncXSet)
	local LSZ = turf.Lot.LOT_SIZE
	local x = LC:getXMin(); x = x - (x % LSZ)
	local baseY = lotHeight(W, LC, 0, fz)
	local prevSkip = false
	while x <= LC:getXMax() do
		local skip   = isCityLot(LC, x, fz)
		local isJunc = juncXSet[x]
		if not skip and not isJunc then
			local nextSkip = isCityLot(LC, x + LSZ, fz)
			local L  = LC:getLotAt(x, fz)
			local vt = L and L.vtype or turf.Lot.LOT_HILLS
			local path
			if nextSkip then
				-- Entering city: ramp sits on the last lot before the city road.
				if not prevSkip then path = "packs/vanilla/hramp1" end
			elseif prevSkip then
				-- Leaving city: ramp sits on the first lot after the city road.
				path = "packs/vanilla/hramp3"
			elseif vt == turf.Lot.LOT_SEA then
				path = "packs/vanilla/highroad_canal_n"
			else
				path = "packs/vanilla/highroad_n"
			end
			if path then forceHighwayLot(LC, W, x, fz, path, 'n', baseY) end
		end
		prevSkip = skip
		x = x + LSZ
		if x % (64 * LSZ) == 0 then Net:doKeepAlive() end
	end
end

-- N/S spur from z=0 toward satZ. Uses isCityLot to stop at actual city buildings.
-- Straight sections use highroad_e. Ramps sit directly adjacent to the city edge (no gap lot).
local function buildHighwayNS(LC, Net, W, fx, satZ)
	local LSZ = turf.Lot.LOT_SIZE
	local goingNorth = satZ > 0
	local zStep = goingNorth and LSZ or -LSZ
	local z = zStep
	local baseY = lotHeight(W, LC, fx, 0)
	local prevSkip = false
	local function pastEnd(cur) return goingNorth and (cur > satZ) or (cur < satZ) end
	while not pastEnd(z) do
		local skip = isCityLot(LC, fx, z)
		if not skip then
			local nextSkip = isCityLot(LC, fx, z + zStep)
			local L  = LC:getLotAt(fx, z)
			local vt = L and L.vtype or turf.Lot.LOT_HILLS
			local path
			if nextSkip then
				if not prevSkip then path = goingNorth and "packs/vanilla/hramp2" or "packs/vanilla/hramp4" end
			elseif prevSkip then
				path = goingNorth and "packs/vanilla/hramp4" or "packs/vanilla/hramp2"
			elseif vt == turf.Lot.LOT_SEA then
				path = "packs/vanilla/highroad_canal_e"
			else
				path = "packs/vanilla/highroad_e"
			end
			if path then forceHighwayLot(LC, W, fx, z, path, 'n', baseY) end
		end
		prevSkip = skip
		z = z + zStep
		if z % (64 * LSZ) == 0 then Net:doKeepAlive() end
	end
end

-- Single highway along the z-axis (east/west): center city (0,0) -> satellite at
-- (0,satZ). satZ > 0 = east (+z), satZ < 0 = west (-z). z = east/west, x = north/south.
-- Reads every road along the x=0 column from origin to the satellite, then splits at
-- the LARGEST gap between roads (the wilderness between the two cities). The roads on
-- either side are each city's facing edge. Lays a flat highway between them, leaving a
-- 4-lot gap at each end for the ramps.
local function buildHighwayZ(LC, Net, W, satZ)
	local LSZ = turf.Lot.LOT_SIZE
	local fx = 0
	local baseY = lotHeight(W, LC, fx, 0)
	local toward = satZ > 0            -- true = east (+z), false = west (-z)
	local step = toward and LSZ or -LSZ

	-- 1) Collect every road z along x=0 from just past origin out to the satellite.
	local roads = {}
	local z = 0
	while (toward and z < satZ) or (not toward and z > satZ) do
		z = z + step
		if isRoadLot(LC, fx, z) then roads[#roads + 1] = z end
		if z % (64 * LSZ) == 0 then Net:doKeepAlive() end
	end
	if #roads < 2 then return end

	-- 2) Largest gap between consecutive roads = wilderness between the two cities.
	local bestGap, splitIdx = -1, nil
	for i = 2, #roads do
		local d = math.abs(roads[i] - roads[i - 1])
		if d > bestGap then bestGap = d; splitIdx = i end
	end
	local centerEdge = roads[splitIdx - 1]   -- center city's facing road edge
	local satEdge    = roads[splitIdx]       -- satellite city's facing road edge

	-- 3) A 4-lot hramp ramp at each city edge, then flat highway between:
	--    city road -> hramp (4 lots) -> highway -> hramp (4 lots) -> city road.
	-- Highway and ramps share one flat level, baseY - 1, so they line up.
	-- The ramp/highway leaves each city toward the wilderness gap: the center city on
	-- the satZ side, the satellite city on the opposite side. Pieces/junction sides
	-- mirror between east and west.
	local hwY = baseY   -- highway+ramp deck level (was baseY-1, which sank it 1 block)
	if toward then
		place4LotRampNS(LC, fx, centerEdge + LSZ,  "packs/vanilla/hramp4", hwY)
		place4LotRampNS(LC, fx, satEdge - 4 * LSZ, "packs/vanilla/hramp2", hwY)
		placeRampJunction(LC, W, fx, centerEdge, 'e')  -- ramp joins center from east
		placeRampJunction(LC, W, fx, satEdge, 'w')     -- ramp joins satellite from west
	else
		place4LotRampNS(LC, fx, centerEdge - 4 * LSZ, "packs/vanilla/hramp2", hwY)
		place4LotRampNS(LC, fx, satEdge + LSZ,        "packs/vanilla/hramp4", hwY)
		placeRampJunction(LC, W, fx, centerEdge, 'w')  -- ramp joins center from west
		placeRampJunction(LC, W, fx, satEdge, 'e')     -- ramp joins satellite from east
	end

	local zStart = math.min(centerEdge, satEdge) + 5 * LSZ
	local zEnd   = math.max(centerEdge, satEdge) - 5 * LSZ
	local idx = 0
	z = zStart
	while z <= zEnd do
		local L  = LC:getLotAt(fx, z)
		local vt = L and L.vtype or turf.Lot.LOT_HILLS
		-- Alternate the lamp variant every other lot (all kept at dir 'n' so the road
		-- stays aligned). Sea spans use the canal bridge piece.
		local path
		local y = hwY
		local isPass = false
		if vt == turf.Lot.LOT_SEA then
			-- Canal bridge piece has a built-in -3 yoffset (roads.csv); loadLot doesn't
			-- auto-apply it, so drop it 3 or the bridge deck sits 3 too tall.
			path = "packs/vanilla/highroad_canal_e"
			y = hwY - 3
		elseif idx % 2 == 0 then
			path = "packs/vanilla/highroad_ew_pass"   -- E/W highway w/ N/S underpass (drive-through)
			isPass = true
		else
			path = "packs/vanilla/highroad_e_alt"     -- lit alt variant (alternating lights)
		end
		forceHighwayLot(LC, W, fx, z, path, 'n', y)
		-- Road data: underpass lots also carry the low N/S cross-road so you can drive under.
		local hL = LC:getLotAt(fx, z)
		if hL then
			local LRD = turf.LotRoadData.genNew()
			if isPass then
				LRD:set2(true, true, false, false, false, false, true, true)  -- low N/S under, high E/W
			else
				LRD:setHighPerservingLow(false, false, true, true)            -- high E/W only
			end
			hL.vtype = turf.Lot.LOT_ROAD
			hL.lotData = LRD
		end
		idx = idx + 1
		z = z + LSZ
		if z % (64 * LSZ) == 0 then Net:doKeepAlive() end
	end

	-- "Highway Cross TL" 5 lots past the center-end ramp top, into the deck (per request).
	local crossZ = toward and (centerEdge + 9 * LSZ) or (centerEdge - 9 * LSZ)
	if toward then _mb_crosses.east = { x = fx, z = crossZ } else _mb_crosses.west = { x = fx, z = crossZ } end
	_mb_crosses.y = hwY
	forceHighwayLot(LC, W, fx, crossZ, "packs/vanilla/highroad_crosstl", 'n', hwY)
	local cL = LC:getLotAt(fx, crossZ)
	if cL then
		local LRD = turf.LotRoadData.genNew()
		LRD:setHighPerservingLow(false, false, true, true)   -- E/W through, matches deck
		cL.vtype = turf.Lot.LOT_ROAD
		cL.lotData = LRD
	end
end

-- Single highway along the x-axis (north/south): center city (0,0) -> satellite at
-- (satX,0). satX > 0 = north (+x), satX < 0 = south (-x). x = north/south, z = east/west.
-- Exact mirror of buildHighwayZ: scans every road along the z=0 row from origin out to
-- the satellite, splits at the LARGEST gap (wilderness between the two cities), lays a
-- flat highway between the facing edges with a 4-lot hramp at each end.
local function buildHighwayX(LC, Net, W, satX)
	local LSZ = turf.Lot.LOT_SIZE
	local fz = 0
	local baseY = lotHeight(W, LC, 0, fz)
	local toward = satX > 0            -- true = north (+x), false = south (-x)
	local step = toward and LSZ or -LSZ

	-- 1) Collect every road x along z=0 from just past origin out to the satellite.
	local roads = {}
	local x = 0
	while (toward and x < satX) or (not toward and x > satX) do
		x = x + step
		if isRoadLot(LC, x, fz) then roads[#roads + 1] = x end
		if x % (64 * LSZ) == 0 then Net:doKeepAlive() end
	end
	if #roads < 2 then return end

	-- 2) Largest gap between consecutive roads = wilderness between the two cities.
	local bestGap, splitIdx = -1, nil
	for i = 2, #roads do
		local d = math.abs(roads[i] - roads[i - 1])
		if d > bestGap then bestGap = d; splitIdx = i end
	end
	local centerEdge = roads[splitIdx - 1]   -- center city's facing road edge
	local satEdge    = roads[splitIdx]       -- satellite city's facing road edge

	-- 3) A 4-lot hramp at each city edge, flat highway between. hramp1 = road S/highway N,
	--    hramp3 = road N/highway S. Pieces/junction sides mirror between north and south.
	local hwY = baseY   -- highway+ramp deck level (was baseY-1, which sank it 1 block)
	if toward then
		place4LotRampX(LC, fz, centerEdge + LSZ,  "packs/vanilla/hramp1", hwY)
		place4LotRampX(LC, fz, satEdge - 4 * LSZ, "packs/vanilla/hramp3", hwY)
		placeRampJunction(LC, W, centerEdge, fz, 'n')  -- ramp joins center from north
		placeRampJunction(LC, W, satEdge, fz, 's')     -- ramp joins satellite from south
	else
		place4LotRampX(LC, fz, centerEdge - 4 * LSZ, "packs/vanilla/hramp3", hwY)
		place4LotRampX(LC, fz, satEdge + LSZ,        "packs/vanilla/hramp1", hwY)
		placeRampJunction(LC, W, centerEdge, fz, 's')  -- ramp joins center from south
		placeRampJunction(LC, W, satEdge, fz, 'n')     -- ramp joins satellite from north
	end

	local xStart = math.min(centerEdge, satEdge) + 5 * LSZ
	local xEnd   = math.max(centerEdge, satEdge) - 5 * LSZ
	local idx = 0
	x = xStart
	while x <= xEnd do
		local L  = LC:getLotAt(x, fz)
		local vt = L and L.vtype or turf.Lot.LOT_HILLS
		local path
		local y = hwY
		local isPass = false
		if vt == turf.Lot.LOT_SEA then
			-- Canal bridge piece has a built-in -3 yoffset (roads.csv); loadLot doesn't
			-- auto-apply it, so drop it 3 or the bridge deck sits 3 too tall.
			path = "packs/vanilla/highroad_canal_n"
			y = hwY - 3
		elseif idx % 2 == 0 then
			path = "packs/vanilla/highroad_ns_pass"   -- N/S highway w/ E/W underpass (drive-through)
			isPass = true
		else
			path = "packs/vanilla/highroad_n_alt"     -- lit alt variant (alternating lights)
		end
		forceHighwayLot(LC, W, x, fz, path, 'n', y)
		-- Road data: underpass lots also carry the low E/W cross-road so you can drive under.
		local hL = LC:getLotAt(x, fz)
		if hL then
			local LRD = turf.LotRoadData.genNew()
			if isPass then
				LRD:set2(false, false, true, true, true, true, false, false)  -- low E/W under, high N/S
			else
				LRD:setHighPerservingLow(true, true, false, false)            -- high N/S only
			end
			hL.vtype = turf.Lot.LOT_ROAD
			hL.lotData = LRD
		end
		idx = idx + 1
		x = x + LSZ
		if x % (64 * LSZ) == 0 then Net:doKeepAlive() end
	end

	-- "Highway Cross TL" 5 lots past the center-end ramp top, into the deck (per request).
	local crossX = toward and (centerEdge + 9 * LSZ) or (centerEdge - 9 * LSZ)
	if toward then _mb_crosses.north = { x = crossX, z = fz } else _mb_crosses.south = { x = crossX, z = fz } end
	_mb_crosses.y = hwY
	forceHighwayLot(LC, W, crossX, fz, "packs/vanilla/highroad_crosstl", 'n', hwY)
	local cL = LC:getLotAt(crossX, fz)
	if cL then
		local LRD = turf.LotRoadData.genNew()
		LRD:setHighPerservingLow(true, true, false, false)   -- N/S through, matches deck
		cL.vtype = turf.Lot.LOT_ROAD
		cL.lotData = LRD
	end
end


-- ─── Part 6c: Ring loop joining the 4 cross-TL junctions ─────────────────────
-- All 4 highways share one elevated deck level (lotHeight(0,0)), recorded as _mb_crosses.y,
-- so the ring runs/corners sit flat at that level and line up with the crosses.

-- Lay a straight elevated highway run between two endpoints along one axis, at the deck
-- level y. Fills only the lots STRICTLY BETWEEN from and to (the endpoints are the cross
-- junction / corner pieces, placed separately). axis 'z' = run along z at fixed x (E/W
-- highway); axis 'x' = run along x at fixed z (N/S highway). Mirrors the main decks exactly:
-- every other lot is the drive-through underpass piece (low cross-road under, high on-axis),
-- the rest are the lit _alt variant (staggered lamps).
local function buildRingRun(LC, W, Net, axis, fixed, from, to, y)
	local LSZ = turf.Lot.LOT_SIZE
	if from == to then return end
	local step = (to > from) and LSZ or -LSZ
	local pos = from + step
	local idx = 0
	while pos ~= to do
		local x = (axis == 'z') and fixed or pos
		local z = (axis == 'z') and pos or fixed
		local isPass = (idx % 2 == 0)
		local path
		if axis == 'z' then
			path = isPass and "packs/vanilla/highroad_ew_pass" or "packs/vanilla/highroad_e_alt"
		else
			path = isPass and "packs/vanilla/highroad_ns_pass" or "packs/vanilla/highroad_n_alt"
		end
		forceHighwayLot(LC, W, x, z, path, 'n', y)
		local hL = LC:getLotAt(x, z)
		if hL then
			local LRD = turf.LotRoadData.genNew()
			if axis == 'z' then
				if isPass then
					LRD:set2(true, true, false, false, false, false, true, true)  -- low N/S under, high E/W
				else
					LRD:setHighPerservingLow(false, false, true, true)            -- high E/W
				end
			else
				if isPass then
					LRD:set2(false, false, true, true, true, true, false, false)  -- low E/W under, high N/S
				else
					LRD:setHighPerservingLow(true, true, false, false)            -- high N/S
				end
			end
			hL.vtype = turf.Lot.LOT_ROAD
			hL.lotData = LRD
		end
		idx = idx + 1
		pos = pos + step
		if idx % 64 == 0 then Net:doKeepAlive() end
	end
end

-- Drop a 90-degree elevated corner piece at (cx,cz) with high-traffic on the two faces it
-- opens toward, so AI cars drive the turn. highN/S/E/W mark those faces.
local function placeRingCorner(LC, W, cx, cz, piece, highN, highS, highE, highW, y)
	forceHighwayLot(LC, W, cx, cz, piece, 'n', y)
	local L = LC:getLotAt(cx, cz)
	if L then
		local LRD = turf.LotRoadData.genNew()
		LRD:setHighPerservingLow(highN, highS, highE, highW)
		L.vtype = turf.Lot.LOT_ROAD
		L.lotData = LRD
	end
end

-- Connect a N/S cross (north/south, at z=0) to an E/W cross (east/west, at x=0) with an L:
-- a straight run out from the N/S cross along z to the corner column, the corner piece, then
-- a straight leg down along x into the E/W cross. The corner sits at (nsCross.x, ewCross.z).
-- Caller passes the geometrically-correct corner piece + the two faces it opens toward.
local function connectCrosses(LC, W, Net, nsCross, ewCross, cornerPiece, hN, hS, hE, hW, y)
	local cornerX = nsCross.x   -- N/S cross supplies the x column
	local cornerZ = ewCross.z   -- E/W cross supplies the z column
	buildRingRun(LC, W, Net, 'z', cornerX, nsCross.z, cornerZ, y)   -- run along z from N/S cross to corner
	placeRingCorner(LC, W, cornerX, cornerZ, cornerPiece, hN, hS, hE, hW, y)
	buildRingRun(LC, W, Net, 'x', cornerZ, cornerX, ewCross.x, y)   -- leg along x from corner into E/W cross
end


-- ─── Part 7: Metro system ────────────────────────────────────────────────────
-- All r*sub* connecting lots have road surfaces (ROADFLAGS) on top — there are no
-- pure-underground track lots in this mod. So we place only stations at city edges;
-- the underground tunnel between them is implied.

local METRO_COLORS = { "blue", "green", "orange", "purple" }

-- Scan outward from a city center along a N/S metro column (fixed x = metroX)
-- and return the first lot z that lies OUTSIDE the city radius.
local function scanStationZ(cx, cz, cityRadius, metroX, goNorth)
	local LSZ = turf.Lot.LOT_SIZE
	local step = goNorth and LSZ or -LSZ
	local z = cz
	for _ = 1, math.ceil(cityRadius / LSZ) + 4 do
		z = z + step
		local dx, dz = metroX - cx, z - cz
		if dx*dx + dz*dz >= cityRadius*cityRadius then return z end
	end
	return z
end

-- Same but scans along an E/W metro row (fixed z = metroZ, variable x).
local function scanStationX(cx, cz, cityRadius, metroZ, goEast)
	local LSZ = turf.Lot.LOT_SIZE
	local step = goEast and LSZ or -LSZ
	local x = cx
	for _ = 1, math.ceil(cityRadius / LSZ) + 4 do
		x = x + step
		local dx, dz = x - cx, metroZ - cz
		if dx*dx + dz*dz >= cityRadius*cityRadius then return x end
	end
	return x
end


-- ─── Part 7b: per-player spawn helpers ───────────────────────────────────────
-- Deterministic satellite centers (matches the OnMapGen pre-hook math; also works after a
-- restart, where the pre-hook didn't run this session, so spawns can still be located).
local function computeSatelliteCenters(W, LC)
	local LSZ  = turf.Lot.LOT_SIZE
	local xMax = LC:getXMax()
	local zMax = LC:getZMax()
	local out = {}
	if math.min(xMax, zMax) < MAIN_CITY_RADIUS + SAT_CITY_RADIUS + 100 then return out end
	local targetDist = MAIN_CITY_RADIUS + SAT_CITY_RADIUS + 800
	local minDist    = MAIN_CITY_RADIUS + SAT_CITY_RADIUS + 100
	for i = 0, 3 do
		local angle = i * (math.pi / 2)
		local cosA, sinA = math.cos(angle), math.sin(angle)
		local maxDistX = math.abs(cosA) > 0.01 and (xMax - SAT_CITY_RADIUS - LSZ) / math.abs(cosA) or math.huge
		local maxDistZ = math.abs(sinA) > 0.01 and (zMax - SAT_CITY_RADIUS - LSZ) / math.abs(sinA) or math.huge
		local maxDist = math.min(maxDistX, maxDistZ)
		if maxDist >= minDist then
			local dist = math.min(maxDist, targetDist)
			local sx = (math.abs(cosA) < 0.01) and 0 or (math.floor(cosA * dist / LSZ) * LSZ)
			local sz = (math.abs(sinA) < 0.01) and 0 or (math.floor(sinA * dist / LSZ) * LSZ)
			out[#out + 1] = { x = sx, z = sz }
		end
	end
	return out
end

local CITY_SPAWNS = nil

-- Find the LOT_SERVER_SPAWN nearest a city centre (cities are >1100 blocks apart, so a 24-lot
-- search box never reaches a neighbouring city). Returns {x,z} lot coords or nil.
local function findServerSpawnNear(LC, cx, cz, Net)
	local LSZ = turf.Lot.LOT_SIZE
	local cx0 = cx - (cx % LSZ)
	local cz0 = cz - (cz % LSZ)
	local R = 24
	local found, bestD2 = nil, nil
	local t = 0
	local x = cx0 - R * LSZ
	while x <= cx0 + R * LSZ do
		local z = cz0 - R * LSZ
		while z <= cz0 + R * LSZ do
			local L = LC:getLotAt(x, z)
			if L and L.vtype == turf.Lot.LOT_SERVER_SPAWN then
				local d2 = (x - cx0) * (x - cx0) + (z - cz0) * (z - cz0)
				if bestD2 == nil or d2 < bestD2 then bestD2 = d2; found = { x = x, z = z } end
			end
			z = z + LSZ
		end
		x = x + LSZ
		t = t + 1
		if Net and t % 8 == 0 then Net:doKeepAlive() end
	end
	return found
end

-- A spawn point {x,z,y} for the centre city + each satellite (LOT_SERVER_SPAWN if found, else
-- the city centre at terrain height).
local function buildCitySpawns(W, LC, Net)
	local LSZ = turf.Lot.LOT_SIZE
	local centers = { { x = 0, z = 0 } }
	for _, c in ipairs(computeSatelliteCenters(W, LC)) do centers[#centers + 1] = c end
	local spawns = {}
	for _, c in ipairs(centers) do
		local s = findServerSpawnNear(LC, c.x, c.z, Net)
		if s then
			spawns[#spawns + 1] = { x = s.x, z = s.z, y = 11 }
		else
			local cx0 = c.x - (c.x % LSZ)
			local cz0 = c.z - (c.z % LSZ)
			local y = getTerrainHeight(W, LC, cx0 + math.floor(LSZ / 2), cz0 + math.floor(LSZ / 2))
			spawns[#spawns + 1] = { x = cx0, z = cz0, y = y }
		end
	end
	return spawns
end

local function getCitySpawns(W, LC, Net)
	if CITY_SPAWNS == nil or #CITY_SPAWNS == 0 then CITY_SPAWNS = buildCitySpawns(W, LC, Net) end
	return CITY_SPAWNS
end


-- ─── Part 8: city generation ─────────────────────────────────────────────────
-- Satellites are generated in the OnMapGen PRE-hook (before standard generation) so the
-- engine's economy/ownership init — which runs as part of standard generation — includes
-- them. Built in OnMapGen_extra instead (as before), their buildings were economically dead:
-- 0 income, could not be owned or racketeered. Roads/metro/highways stay in _extra below;
-- they only touch road lots, so highway behaviour is unchanged.
local _mb_satellites = {}

customFunc.OnMapGen = function(GMS, W, LC, nFactions, nBasesPerFaction)
	local Net = turf.NetworkHandler.getInstance()
	local LSZ  = turf.Lot.LOT_SIZE
	local xMax = LC:getXMax()
	local zMax = LC:getZMax()
	_mb_satellites = {}

	-- Bail (centre city only) if the map can't fit a satellite at least minDist away.
	if math.min(xMax, zMax) < MAIN_CITY_RADIUS + SAT_CITY_RADIUS + 100 then return end

	local nSat = 4
	local targetDist = MAIN_CITY_RADIUS + SAT_CITY_RADIUS + 800  -- 1800 blocks
	local minDist    = MAIN_CITY_RADIUS + SAT_CITY_RADIUS + 100  -- 1100 blocks

	-- Satellites at cardinal directions (z=E/W, x=N/S): N(0°,+x), E(90°,+z), S(180°,-x), W(270°,-z).
	Net:forceUpdateStartupStatusString("Generating Satellite Cities")
	for i = 0, nSat - 1 do
		local angle = i * (math.pi / 2)
		local cosA  = math.cos(angle)
		local sinA  = math.sin(angle)

		local maxDistX = math.abs(cosA) > 0.01
			and (xMax - SAT_CITY_RADIUS - LSZ) / math.abs(cosA)
			or  math.huge
		local maxDistZ = math.abs(sinA) > 0.01
			and (zMax - SAT_CITY_RADIUS - LSZ) / math.abs(sinA)
			or  math.huge
		local maxDist = math.min(maxDistX, maxDistZ)

		if maxDist >= minDist then
			local dist = math.min(maxDist, targetDist)
			-- Snap the near-zero (perpendicular) axis to exactly 0 so axis-aligned cities
			-- land on x=0 / z=0. (floor() otherwise lands the west/south city on -16 because
			-- cos/sin of 270deg is a tiny negative float, leaving it 1 lot off-axis.)
			local sx = (math.abs(cosA) < 0.01) and 0 or (math.floor(cosA * dist / LSZ) * LSZ)
			local sz = (math.abs(sinA) < 0.01) and 0 or (math.floor(sinA * dist / LSZ) * LSZ)
			table.insert(_mb_satellites, { x = sx, z = sz })
			_orig_generate_city(W, LC, SAT_CITY_RADIUS, sx, sz, 0)
			Net:doKeepAlive()
		end
	end
	-- return nil -> standard generation runs next and economically initializes the satellites.
end

-- ─── Part 8b: OnMapGen_extra — roads/metro/highways over the already-built cities ──
customFunc.OnMapGen_extra = function(GMS, W, LC, nFactions, nBasesPerFaction)
	local Net = turf.NetworkHandler.getInstance()
	local LSZ  = turf.Lot.LOT_SIZE
	local satellites = _mb_satellites

	-- Metro: 1 underground hub station at the main city center + 1 station per
	-- satellite at its city edge facing inward. All 5 stations form one implied network.
	Net:forceUpdateStartupStatusString("Generating Metro System")
	forceHighwayLot(LC, W, 0, 0, "packs/Metros/metrostationred", 'n')
	for i, sat in ipairs(satellites) do
		local color = METRO_COLORS[((i - 1) % #METRO_COLORS) + 1]
		if math.abs(sat.z) >= LSZ then
			local fx     = sat.x + LSZ
			local satStZ = scanStationZ(sat.x, sat.z, SAT_CITY_RADIUS, fx, sat.z < 0)
			forceHighwayLot(LC, W, fx, satStZ, "packs/Metros/metrostation" .. color, 'n')
		else
			local fz     = LSZ
			local satStX = scanStationX(sat.x, sat.z, SAT_CITY_RADIUS, fz, sat.x < 0)
			forceHighwayLot(LC, W, satStX, fz, "packs/Metros/metrostation" .. color, 'n')
		end
		Net:doKeepAlive()
	end

	-- Terrain conforming runs before highways so it can't flatten the highway ramps.
	Net:forceUpdateStartupStatusString("Conforming Roads To Terrain")
	conformRoadsToTerrain(W, LC, Net, 0, 0, MAIN_CITY_RADIUS)
	for _, sat in ipairs(satellites) do
		conformRoadsToTerrain(W, LC, Net, sat.x, sat.z, SAT_CITY_RADIUS)
		Net:doKeepAlive()
	end

	-- Highways run LAST so the terrain-conform pass can't wipe the ramps.
	-- East (+z) and West (-z) highways along the z-axis, one satellite at a time.
	-- (z = east/west, x = north/south.) N/S along x still to come.
	Net:forceUpdateStartupStatusString("Generating Highways")
	_mb_crosses = {}
	for _, sat in ipairs(satellites) do
		-- z-axis (east/west) satellites: x ~= 0 (floor() can land on -16 for the west
		-- one due to cos(270deg) being a tiny negative float), z large.
		if math.abs(sat.x) <= LSZ and math.abs(sat.z) >= 2 * LSZ then
			buildHighwayZ(LC, Net, W, sat.z)
			Net:doKeepAlive()
		end
		-- x-axis (north/south) satellites: z ~= 0, x large.
		if math.abs(sat.z) <= LSZ and math.abs(sat.x) >= 2 * LSZ then
			buildHighwayX(LC, Net, W, sat.x)
			Net:doKeepAlive()
		end
	end

	-- Ring loop: join the 4 cross-TL junctions into a square so they form a loop around the
	-- centre. Each corner runs out along z from a N/S cross, turns, and drops along x into an
	-- E/W cross. The corner piece opens toward the two runs (the loop interior), so it carries
	-- the ANTIPODAL name to its position: NW corner -> cse, NE -> csw, SW -> cne, SE -> cnw.
	Net:forceUpdateStartupStatusString("Connecting Highway Ring")
	pcall(function()
		local C = _mb_crosses
		if not C.y then return end
		-- NW corner (North<->West): run from North arrives E, leaves S -> opens S+E -> cse.
		if C.north and C.west then
			connectCrosses(LC, W, Net, C.north, C.west, "packs/vanilla/highroad_cse", false, true, true, false, C.y)
		end
		-- NE corner (North<->East): run from North arrives W, leaves S -> opens S+W -> csw.
		if C.north and C.east then
			connectCrosses(LC, W, Net, C.north, C.east, "packs/vanilla/highroad_csw", false, true, false, true, C.y)
		end
		-- SW corner (South<->West): run from South arrives E, leaves N -> opens N+E -> cne.
		if C.south and C.west then
			connectCrosses(LC, W, Net, C.south, C.west, "packs/vanilla/highroad_cne", true, false, true, false, C.y)
		end
		-- SE corner (South<->East): run from South arrives W, leaves N -> opens N+W -> cnw.
		if C.south and C.east then
			connectCrosses(LC, W, Net, C.south, C.east, "packs/vanilla/highroad_cnw", true, false, false, true, C.y)
		end
	end)

	-- Per-player spawn support: record each city's spawn lot and default the world spawn to the
	-- centre city (each generate_city set it to its own city, so otherwise the last one wins).
	CITY_SPAWNS = buildCitySpawns(W, LC, Net)
	if CITY_SPAWNS[1] then
		W:setSpawnPoint(turf.iVec3(CITY_SPAWNS[1].x + math.floor(LSZ / 2), CITY_SPAWNS[1].y,
			CITY_SPAWNS[1].z + math.floor(LSZ / 2)))
	end

	W:genLotCache()
end


-- ─── Part 9: per-player random spawn city (per save, first join) ──────────────
-- A player's first spawn (before they own a base) lands in a city chosen by a deterministic
-- hash of their account id + the map's spawn signature: different players get different
-- cities, a given player is stable on rejoin, and it varies per map. Once they own a base
-- they respawn there normally. Chained so TakaroConnector's hook still runs; pcall-guarded
-- because a login-hook error would take down the --strictlua server.
local _mb_prev_onPlayerLogin_extra = customFunc.onPlayerLogin_extra
customFunc.onPlayerLogin_extra = function(GMS, P)
	if _mb_prev_onPlayerLogin_extra then _mb_prev_onPlayerLogin_extra(GMS, P) end
	pcall(function()
		if not P then return end
		local nBases = turf.TriggerHandler.getNBasesOwnedByPlayer(P)
		if nBases and nBases > 0 then return end          -- already settled in a city
		local W = P:getWorld()
		if not W then return end
		local LC = W:getLotContainer()
		if not LC then return end
		local Net = turf.NetworkHandler.getInstance()
		local spawns = getCitySpawns(W, LC, Net)
		if not spawns or #spawns == 0 then return end
		local sig = 0
		for _, s in ipairs(spawns) do sig = sig + s.x * 73856093 + s.z * 19349663 end
		local cred = P:getCredentials()
		local acct = (cred and cred.accountId) or P:getId() or 0
		local a = math.abs(math.floor(acct)) % 1000003
		local b = math.abs(math.floor(sig)) % 1000003
		local pick = spawns[((a * 17 + b) % #spawns) + 1]
		local LSZ = turf.Lot.LOT_SIZE
		P:teleport3i(pick.x + math.floor(LSZ / 2), pick.y, pick.z + math.floor(LSZ / 2))
	end)
end


-- ─── Part 10: contain AI buying/racketeering to base area (like players) ──────
-- The engine's pickLotsToBuy() picks a lot to BUY and a lot to RACKETEER from ANYWHERE on the
-- map (it floods the richest/centre city), then attemptToBuyLots() acts ONLY on the two fields
-- PCAI.nextTargetLot and PCAI.nextTargetRacketteer. The probe confirmed those are userdata with
-- read/write .x/.z lot coords. So we override aiPlayer_doTurn (a global the engine calls each AI
-- turn): let pickLotsToBuy choose, then if a chosen target is outside this gang's base radius,
-- redirect it onto one of the gang's OWN base lots — buying/racketeering an owned lot is a no-op,
-- so the AI can only ever expand within turf.Lot.BASE_RADIUS of its bases, exactly like players.
--
-- The construction/zoning path (aiplayer_doBuilding -> getVacantLotsAttachedToBase) is already
-- base-bound, so it's untouched. We faithfully replicate vanilla aiPlayer_doTurn and only insert
-- the containment between pickLotsToBuy and attemptToBuyLots (pcall-guarded so it can't crash).
local function _mb_containTargets(PCCAI, W)
	local LC = W:getLotContainer()
	local bases = LC:getBasesOwnedBy(PCCAI.PCC.accountId)
	if bases:size() < 1 then return end
	local home = bases:get(0)                 -- a lot this gang owns (safe no-op redirect target)
	local r = turf.Lot.BASE_RADIUS * turf.Lot.LOT_SIZE
	local thr2 = r * r
	local function outOfArea(t)
		if not t then return false end        -- no target -> nothing to clamp
		for i = 1, bases:size() do
			local b = bases:get(i - 1)
			local dx, dz = t.x - b.x, t.z - b.z
			if dx * dx + dz * dz <= thr2 then return false end
		end
		return true
	end
	if outOfArea(PCCAI.nextTargetLot)        then PCCAI.nextTargetLot        = turf.LotCoordinate(home.x, home.z) end
	if outOfArea(PCCAI.nextTargetRacketteer) then PCCAI.nextTargetRacketteer = turf.LotCoordinate(home.x, home.z) end
end

function aiPlayer_doTurn(PCCAI, W)
	if (PCCAI.PCC.nBases < 1) then return end

	PCCAI.targetWarchest = aiPlayer_calculateWarchest(PCCAI.PCC.networth)
	PCCAI.constructionBudget = math.max(PCCAI.PCC:getMoney() * 0.5, 0)

	if (PCCAI.isAtWar) then
		PCCAI.timeInWarModifier = math.max(PCCAI.timeInWarModifier - 1, -30)
	else
		PCCAI.timeInWarModifier = math.min(PCCAI.timeInWarModifier + 5, 30)
		PCCAI.PCC:addReputation(0.1 * 100)
		if (PCCAI.PCC:getReputation() > 10 * 100 and PCCAI.PCC.landValue < BASE_LOT_PRICE * 4) then
			PCCAI.PCC:addReputation(-100)
			PCCAI.PCC:transactMoney(5000 * 100)
		end
	end

	if (not PCCAI.isAtWar and PCCAI.PCC.nBases > 0) then
		PCCAI.PCC.bonuses.smallTownMayor = true
		if (aiplayer_hasExpanded(PCCAI) or PCCAI.PCC:getMoney() > AI_EXPANSION_CASH_THRESH) then
			PCCAI.racketeerRepuationThresh = 5 * 100
		end
		PCCAI:pickLotsToBuy(W)
		pcall(_mb_containTargets, PCCAI, W)    -- clamp targets to base area; never crash the turn
		PCCAI:attemptToBuyLots(W)
		if (aiplayer_wantsNewBase(PCCAI, W)) then
			aiplayer_establishNewBase(PCCAI, W)
		end
	end
end


-- Skip the engine's gen-time initial buy/racketeer pass. aiPlayer_doInitTurn runs in a loop at
-- generation while every gang is still on its CENTRE start-base (before distribution moves them),
-- so its racketeering floods the centre with buildings we'd otherwise have to strip. We end that
-- loop immediately: gangs start with just their base and build out their OWN city over time via
-- the base-area-contained aiPlayer_doTurn — so the rule applies BEFORE anything is racketeered,
-- and we never release a gang's buildings.
function aiPlayer_doInitTurn(PCCAI, W, turnCount)
	return false
end


-- ─── Part 11: distribute gangs evenly across cities (runtime, once per world) ──
-- The engine's initial gang->base assignment is origin-bounded C++: it seeds every gang in the
-- CENTRE and ignores satellite faction bases, so gen-time placement can't move them (thinning
-- centre bases just starves it -> gangs with no base). Instead, once the gangs exist we reassign
-- them: each gang is given a couple of bandit bases in an evenly-chosen city (claim = the
-- engine's own MOB_BASE->BASE conversion) and the centre base it was handed is released. With the
-- base-area containment (Part 10), each gang then develops only its own city. No kickstart, no
-- economy edits. Runs once; a restart re-detects existing spread and skips.
local _mb_distributed = false
local MB_BASES_PER_GANG = 2
local _mb_prev_poll_dist = customFunc.pollServerTick_extra
customFunc.pollServerTick_extra = function(NH)
	if _mb_prev_poll_dist then _mb_prev_poll_dist(NH) end
	if _mb_distributed then return end
	pcall(function()
		local PC = NH:getPlayerContainer()
		if not PC then return end
		local W = nil
		for i = 0, PC:getNPlayers() - 1 do local P = PC:get(i); if P then W = P:getWorld() end; if W then break end end
		local gangs = {}
		for i = 0, PC:getNPlayersStored() - 1 do
			local c = PC:getCredentialsAt(i)
			if c and c:isAiPlayer() then
				gangs[#gangs + 1] = c
				if not W then W = c:getWorld() end
			end
		end
		if not W or #gangs == 0 then return end          -- not ready; retry next tick
		local LC = W:getLotContainer()
		if not LC then return end

		local cities = { { x = 0, z = 0, r = MAIN_CITY_RADIUS } }
		for _, c in ipairs(computeSatelliteCenters(W, LC)) do
			cities[#cities + 1] = { x = c.x, z = c.z, r = SAT_CITY_RADIUS }
		end
		local nC = #cities

		-- restart safety: if any gang already owns a satellite base, we've already distributed.
		for _, c in ipairs(gangs) do
			local owned = LC:getBasesOwnedBy(c.accountId)
			for j = 1, owned:size() do
				local b = owned:get(j - 1)
				for ci = 2, nC do
					local d = cities[ci]; local dx, dz = b.x - d.x, b.z - d.z
					if dx * dx + dz * dz <= d.r * d.r then _mb_distributed = true; return end
				end
			end
		end

		-- per-world PRNG (runtime math.random is unseeded); seed from city geometry -> varies per map
		local seed = 1234567
		for _, c in ipairs(cities) do seed = seed + c.x * 73856093 + c.z * 19349663 end
		local rng = math.abs(seed) % 2147483647
		if rng == 0 then rng = 1 end
		local function nextRand(n) rng = (rng * 16807) % 2147483647; return (rng % n) + 1 end

		-- even round-robin city assignment for the gangs, shuffled per world
		local order = {}
		local base = math.floor(#gangs / nC)
		local extra = #gangs - base * nC
		for ci = 1, nC do for _ = 1, base do order[#order + 1] = ci end end
		local pe = {}
		while extra > 0 do local ci = nextRand(nC); if not pe[ci] then pe[ci] = true; order[#order + 1] = ci; extra = extra - 1 end end
		for i = #order, 2, -1 do local j = nextRand(i); order[i], order[j] = order[j], order[i] end

		-- pre-scan each city for unoccupied bandit bases
		local LSZ = turf.Lot.LOT_SIZE
		local cityBandits = {}
		local tick = 0
		for ci = 1, nC do
			local city = cities[ci]
			local pool = {}
			local cx0 = city.x - (city.x % LSZ); local cz0 = city.z - (city.z % LSZ)
			local rr = math.ceil(city.r / LSZ)
			for ix = -rr, rr do
				for iz = -rr, rr do
					if ix * ix + iz * iz <= rr * rr then
						local x, z = cx0 + ix * LSZ, cz0 + iz * LSZ
						local L = LC:getLotAt(x, z)
						if L and L.vtype == turf.Lot.LOT_MOB_BASE and L.owner == 0 and L.occupier == 0 then
							pool[#pool + 1] = { x = x, z = z }
						end
					end
					tick = tick + 1; if tick % 64 == 0 then NH:doKeepAlive() end
				end
			end
			cityBandits[ci] = pool
		end

		-- give each gang bases in its city, release the centre base(s) it was handed
		for gi, c in ipairs(gangs) do
			local ci = order[gi]
			local city = cities[ci]
			local pid = c.accountId
			local got = 0
			local pool = cityBandits[ci]
			while got < MB_BASES_PER_GANG and #pool > 0 do
				local b = table.remove(pool)
				local L = LC:getLotAt(b.x, b.z)
				if L and L.vtype == turf.Lot.LOT_MOB_BASE and L.owner == 0 and L.occupier == 0 then
					LC:createSpawnFlagInCentreOfLot(b.x, b.z, 0)
					L.owner = pid; L.occupier = pid
					LC:manualAddCacheUpdate(b.x, b.z, turf.Lot.LOT_MOB_BASE, turf.Lot.LOT_BASE)
					got = got + 1
				end
			end
			if got > 0 then
				local owned = LC:getBasesOwnedBy(pid)
				for j = 1, owned:size() do
					local b = owned:get(j - 1)
					local dx, dz = b.x - city.x, b.z - city.z
					if dx * dx + dz * dz > city.r * city.r then
						local L = LC:getLotAt(b.x, b.z)
						if L and L.owner == pid then L.owner = 0; L.occupier = 0 end
					end
				end
			end
			NH:doKeepAlive()
		end

		LC:refreshLotCache()
		_mb_distributed = true
	end)
end


-- ─── Part 12: missions target the NEAREST building, not a random one ──────────
-- Missions pick their target via turf.TriggerHandler.getRandomBuisnessWithName(P,...), which
-- returns a RANDOM matching building anywhere on the map. With multiple cities the target is
-- usually in another city (ambulance impossible, mechanic "towns away"). We wrap it so it samples
-- the engine's random pick several times and returns the one NEAREST the player. Defensive:
-- the setup and the per-call logic both fall back to vanilla on any error, so it can never break
-- the mod or crash a mission under --strictlua.
pcall(function()
	local TH = turf.TriggerHandler
	if not TH then return end
	local _orig = TH.getRandomBuisnessWithName
	if type(_orig) ~= "function" then return end
	TH.getRandomBuisnessWithName = function(P, a, b, name)
		-- Only force "nearest" for mission-critical service buildings. Other lookups (e.g.
		-- heist/undermining targets that are meant to be across town) keep vanilla random.
		if not (name == "Hospital" or name == "Mechanic Garage" or name == "Caryard") then
			return _orig(P, a, b, name)
		end
		local ok, result = pcall(function()
			if not P then return nil end
			local W = P:getWorld()
			local LC = W and W:getLotContainer()
			if not LC then return nil end
			local px, pz = P:getPos(0), P:getPos(2)
			local best, bestD2 = nil, nil
			for _ = 1, 15 do
				local idx = _orig(P, a, b, name)
				if idx then
					local lc = LC:indexToLotCoordinate(idx)
					if lc then
						local dx, dz = lc.x - px, lc.z - pz
						local d2 = dx * dx + dz * dz
						if bestD2 == nil or d2 < bestD2 then bestD2 = d2; best = idx end
					end
				end
			end
			return best
		end)
		if ok and result ~= nil then return result end
		return _orig(P, a, b, name)
	end
end)


-- ─── Part 13: ambulance patient pickup must be NEAR the player ────────────────
-- Vanilla ambulanceMission_getRandomLot accepts a random house within a radius that starts at
-- ~400 lots (6.4km) and grows — so with multiple cities the patient is often in another city,
-- impossible to reach before the timer. Override it (global function) to pick the NEAREST of
-- several sampled houses, so the patient is in/near the player's own city. Saves and falls back
-- to the original on any error (strictlua-safe).
local MB_AMBULANCE_MAX_DIST = 1000   -- patient must be within this many metres of the player
local _mb_orig_amblot = ambulanceMission_getRandomLot
if type(_mb_orig_amblot) == "function" then
	function ambulanceMission_getRandomLot(M, P, objectiveId)
		local ok = pcall(function()
			local LC = P:getWorld():getLotContainer()
			local px, pz = P:getPos(0), P:getPos(2)
			local limit2 = MB_AMBULANCE_MAX_DIST ^ 2
			local chosen, closest, closestD2 = nil, nil, nil
			for _ = 1, 50 do
				local h = turf.TriggerHandler.getRandomHouseWithPopRange(P, 0, 0.25, 2, 200)
				if h >= LC:getNLots() then h = turf.TriggerHandler.getRandomHouse(P, 0, 0.25) end
				if h < LC:getNLots() then
					local lc = LC:indexToLotCoordinate(h)
					local dx, dz = lc.x - px, lc.z - pz
					local d2 = dx * dx + dz * dz
					if d2 <= limit2 then chosen = h; break end          -- within the limit: take it
					if closestD2 == nil or d2 < closestD2 then closestD2 = d2; closest = h end
				end
			end
			local pick = chosen or closest                            -- closest only if none in range
			if not pick then error("no house found") end
			local lc = LC:indexToLotCoordinate(pick)
			local llaabb = LC:getLotAABB(lc.x, lc.z)
			M:getObjective(objectiveId).waypoint = turf.iVec3(llaabb:getMidX(), 10, llaabb:getMidZ())
		end)
		if not ok then return _mb_orig_amblot(M, P, objectiveId) end
	end
end
