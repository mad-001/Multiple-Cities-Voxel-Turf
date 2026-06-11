-- ─── Part 1: Guaranteed mission-critical buildings ───────────────────────────
local _orig_get_footprints = get_footprints

function get_footprints(W, LC, radius, startX, startZ, maxPlayerBases)
	local FP_POOL, nPoolWithMaxConuts = _orig_get_footprints(W, LC, radius, startX, startZ, maxPlayerBases)
	local LPC = turf.LotPackContainer:getInstance()
	local nLPI = LPC:getNLotPackItems()
	local guaranteed = {
		{ name = "Hospital",                cat = turf.LotPackItem.LPI_CAT_COMMERCE },
		{ name = "Mechanic Garage",         cat = turf.LotPackItem.LPI_CAT_COMMERCE },
		{ name = "Caryard",                 cat = turf.LotPackItem.LPI_CAT_COMMERCE },
		{ name = "Helifield",               cat = turf.LotPackItem.LPI_CAT_COMMERCE },
		{ name = "S-Mart Department Store", cat = turf.LotPackItem.LPI_CAT_COMMERCE },
		{ name = "Big Office #1",           cat = turf.LotPackItem.LPI_CAT_OFFICE   },
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

-- Single highway: center city (0,0) -> north satellite at (0,satZ).
-- Reads every road along the x=0 column from origin to the satellite, then splits at
-- the LARGEST gap between roads (that gap is the wilderness between the two cities).
-- The roads on either side of it are the center city's north edge and the north city's
-- south edge. Lays flat highway between them, leaving a 4-lot gap at each for the ramps.
local function buildNorthHighway(LC, Net, W, satZ)
	local LSZ = turf.Lot.LOT_SIZE
	local fx = 0
	local baseY = lotHeight(W, LC, fx, 0)

	-- 1) Collect every road z along x=0 from just north of origin up to the satellite.
	local roads = {}
	local z = 0
	while z < satZ do
		z = z + LSZ
		if isRoadLot(LC, fx, z) then roads[#roads + 1] = z end
		if z % (64 * LSZ) == 0 then Net:doKeepAlive() end
	end
	if #roads < 2 then return end

	-- 2) Largest gap between consecutive roads = wilderness between the two cities.
	local bestGap, splitIdx = -1, nil
	for i = 2, #roads do
		local d = roads[i] - roads[i - 1]
		if d > bestGap then bestGap = d; splitIdx = i end
	end
	local cNorthEdge = roads[splitIdx - 1]   -- center city's north road edge
	local nSouthEdge = roads[splitIdx]       -- north city's south road edge

	-- 3) A 4-lot hramp ramp at each city edge, then flat highway between:
	--    city road -> hramp (4 lots) -> highway -> hramp (4 lots) -> city road.
	-- Highway and ramps share one flat level, baseY - 1, so they line up.
	local hwY = baseY - 1
	place4LotRampNS(LC, fx, cNorthEdge + LSZ,     "packs/vanilla/hramp4", hwY)
	place4LotRampNS(LC, fx, nSouthEdge - 4 * LSZ, "packs/vanilla/hramp2", hwY)

	local zStart = cNorthEdge + 5 * LSZ
	local zEnd   = nSouthEdge - 5 * LSZ
	z = zStart
	while z <= zEnd do
		local L  = LC:getLotAt(fx, z)
		local vt = L and L.vtype or turf.Lot.LOT_HILLS
		local path = (vt == turf.Lot.LOT_SEA) and "packs/vanilla/highroad_canal_e"
		                                       or  "packs/vanilla/highroad_e"
		forceHighwayLot(LC, W, fx, z, path, 'n', hwY)
		z = z + LSZ
		if z % (64 * LSZ) == 0 then Net:doKeepAlive() end
	end
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


-- ─── Part 8: OnMapGen_extra ───────────────────────────────────────────────────
customFunc.OnMapGen_extra = function(GMS, W, LC, nFactions, nBasesPerFaction)
	local Net = turf.NetworkHandler.getInstance()
	local LSZ  = turf.Lot.LOT_SIZE
	local xMax = LC:getXMax()
	local zMax = LC:getZMax()

	-- Always try all 4 NSEW directions; the minDist check below filters any that
	-- don't fit on this particular map. Bail early only if even one satellite can't
	-- possibly be at least minDist from the main city.
	local nSat = 4
	if math.min(xMax, zMax) < MAIN_CITY_RADIUS + SAT_CITY_RADIUS + 100 then
		W:genLotCache(); return
	end

	local targetDist = MAIN_CITY_RADIUS + SAT_CITY_RADIUS + 800  -- 1800 blocks
	local minDist    = MAIN_CITY_RADIUS + SAT_CITY_RADIUS + 100  -- 1100 blocks

	-- Satellites placed at cardinal directions: E(0°), N(90°), W(180°), S(270°).
	local satellites = {}
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

		if maxDist < minDist then goto next_satellite end

		local dist = math.min(maxDist, targetDist)
		local sx = math.floor(cosA * dist / LSZ) * LSZ
		local sz = math.floor(sinA * dist / LSZ) * LSZ
		table.insert(satellites, { x = sx, z = sz })
		_orig_generate_city(W, LC, SAT_CITY_RADIUS, sx, sz, 0)
		Net:doKeepAlive()

		::next_satellite::
	end

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
	-- Focus: perfect the center city -> north satellite highway only, for now.
	Net:forceUpdateStartupStatusString("Generating Highways")
	for _, sat in ipairs(satellites) do
		if sat.x == 0 and sat.z > 0 then
			buildNorthHighway(LC, Net, W, sat.z)
			Net:doKeepAlive()
		end
	end

	W:genLotCache()
end
