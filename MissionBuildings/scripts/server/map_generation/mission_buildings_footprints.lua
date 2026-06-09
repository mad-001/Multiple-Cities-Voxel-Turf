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

-- Overwrites any existing lot (used to replace backbone with junction piece).
local function forceHighwayLot(LC, W, x, z, lotPath, dir)
	local L = LC:getLotAt(x, z)
	if not L then return end
	local old = L.vtype
	L:clearData(LC)
	L.vtype = turf.Lot.LOT_VACANT
	LC:markUpdate(x, z, old, L.vtype)
	LC:loadLot(x, z, lotHeight(W, LC, x, z), lotPath, dir, turf.Lot.LOT_FILL_MODE_NORMAL)
end

-- E/W backbone at z=fz.
-- - City edge ramps: hramp2 (W=hw,E=road) before city; hramp4 (W=road,E=hw) after city.
-- - Off-ramp exit every 50 highway lots: T-junction + perpendicular ramp.
-- - juncXSet: x positions of N/S spur junctions (skipped here, placed in caller).
local function buildHighwayEW(LC, Net, W, fz, skipCenters, juncXSet)
	local LSZ = turf.Lot.LOT_SIZE
	local x = LC:getXMin(); x = x - (x % LSZ)
	local prevSkip = false
	local tick  = 0
	local hwTick = 0  -- actual highway lots placed (for off-ramp spacing)
	local rampSide = 0  -- 0 = north (+z) exit, 1 = south (-z) exit
	while x <= LC:getXMax() do
		local skip  = inCityRadius(x, fz, skipCenters)
		local isJunc = juncXSet[x]
		if not skip and not isJunc then
			local nextSkip = inCityRadius(x + LSZ, fz, skipCenters)
			local nextJunc = juncXSet[x + LSZ]
			local L  = LC:getLotAt(x, fz)
			local vt = L and L.vtype or turf.Lot.LOT_HILLS
			local path
			if nextSkip and not prevSkip then
				path = "packs/vanilla/hramp2"           -- city edge: W=hw, E=road
				hwTick = 0
			elseif prevSkip then
				path = "packs/vanilla/hramp4"           -- city edge: W=road, E=hw
				hwTick = 0
			elseif vt == turf.Lot.LOT_SEA then
				path = "packs/vanilla/highroad_canal_e"
				hwTick = hwTick + 1
			elseif hwTick > 0 and hwTick % 50 == 0 and not nextSkip and not nextJunc then
				-- off-ramp: T-junction → 2 approach lots → ramp (3 lots total)
				local rampDir = rampSide == 0 and 1 or -1
				local appr1Z  = fz + rampDir * LSZ
				local appr2Z  = fz + rampDir * 2 * LSZ
				local rampZ   = fz + rampDir * 3 * LSZ
				if not inCityRadius(x, appr1Z, skipCenters)
				   and not inCityRadius(x, appr2Z, skipCenters)
				   and not inCityRadius(x, rampZ,  skipCenters) then
					path = (rampSide == 0) and "packs/vanilla/highroad_jnew_tl"
					                       or  "packs/vanilla/highroad_jsew_tl"
					local rp = (rampSide == 0) and "packs/vanilla/hramp3"
					                           or  "packs/vanilla/hramp1"
					forceHighwayLot(LC, W, x, appr1Z, "packs/vanilla/highroad_n", 'n')
					forceHighwayLot(LC, W, x, appr2Z, "packs/vanilla/highroad_n", 'n')
					forceHighwayLot(LC, W, x, rampZ,  rp, 'n')
					rampSide = 1 - rampSide
				else
					path = (tick % 4 == 0) and "packs/vanilla/highroad_e_alt"
					                       or  "packs/vanilla/highroad_e"
				end
				hwTick = hwTick + 1
			else
				path = "packs/vanilla/highroad_e"
				hwTick = hwTick + 1
			end
			forceHighwayLot(LC, W, x, fz, path, 'n')
		elseif skip then
			hwTick = 0
		end
		prevSkip = skip
		x = x + LSZ; tick = tick + 1
		if tick % 64 == 0 then Net:doKeepAlive() end
	end
end

-- N/S spur from z=0 toward satZ. Junction at z=0 placed in caller.
-- Off-ramp exit every 50 highway lots.
--   goingNorth (+z): ramp at city edge is hramp3 (N=road,S=hw); exit ramps go E/W.
--   goingSouth (-z): ramp at city edge is hramp1 (S=road,N=hw); exit ramps go E/W.
local function buildHighwayNS(LC, Net, W, fx, satZ, skipCenters)
	local LSZ = turf.Lot.LOT_SIZE
	local goingNorth = satZ > 0
	local zStep = goingNorth and LSZ or -LSZ
	local z = zStep
	local prevSkip = false
	local tick  = 0
	local hwTick = 0
	local rampSide = 0  -- 0 = east (+x) exit, 1 = west (-x) exit
	local function pastEnd(cur) return goingNorth and (cur > satZ) or (cur < satZ) end
	while not pastEnd(z) do
		local skip = inCityRadius(fx, z, skipCenters)
		if not skip then
			local nextSkip = inCityRadius(fx, z + zStep, skipCenters)
			local L  = LC:getLotAt(fx, z)
			local vt = L and L.vtype or turf.Lot.LOT_HILLS
			local path
			if nextSkip and not prevSkip then
				path = goingNorth and "packs/vanilla/hramp3" or "packs/vanilla/hramp1"
				hwTick = 0
			elseif prevSkip then
				path = goingNorth and "packs/vanilla/hramp1" or "packs/vanilla/hramp3"
				hwTick = 0
			elseif vt == turf.Lot.LOT_SEA then
				path = "packs/vanilla/highroad_canal_n"
				hwTick = hwTick + 1
			elseif hwTick > 0 and hwTick % 50 == 0 and not nextSkip then
				-- off-ramp: T-junction → 2 approach lots → ramp (3 lots total)
				local rampDir = rampSide == 0 and 1 or -1
				local appr1X  = fx + rampDir * LSZ
				local appr2X  = fx + rampDir * 2 * LSZ
				local rampX   = fx + rampDir * 3 * LSZ
				if not inCityRadius(appr1X, z, skipCenters)
				   and not inCityRadius(appr2X, z, skipCenters)
				   and not inCityRadius(rampX,  z, skipCenters) then
					path = (rampSide == 0) and "packs/vanilla/highroad_jnse_tl"
					                       or  "packs/vanilla/highroad_jnsw_tl"
					local rp = (rampSide == 0) and "packs/vanilla/hramp2"
					                           or  "packs/vanilla/hramp4"
					forceHighwayLot(LC, W, appr1X, z, "packs/vanilla/highroad_e", 'n')
					forceHighwayLot(LC, W, appr2X, z, "packs/vanilla/highroad_e", 'n')
					forceHighwayLot(LC, W, rampX,  z, rp, 'n')
					rampSide = 1 - rampSide
				else
					path = (tick % 4 == 0) and "packs/vanilla/highroad_n_alt"
					                       or  "packs/vanilla/highroad_n"
				end
				hwTick = hwTick + 1
			else
				path = "packs/vanilla/highroad_n"
				hwTick = hwTick + 1
			end
			forceHighwayLot(LC, W, fx, z, path, 'n')
		elseif skip then
			hwTick = 0
		end
		prevSkip = skip
		z = z + zStep
		tick = tick + 1
		if tick % 64 == 0 then Net:doKeepAlive() end
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

	-- Skip list prevents highway lots from overwriting city buildings.
	local skipCenters = {{ x = 0, z = 0, r = MAIN_CITY_RADIUS }}
	for _, sat in ipairs(satellites) do
		skipCenters[#skipCenters + 1] = { x = sat.x, z = sat.z, r = SAT_CITY_RADIUS }
	end

	Net:forceUpdateStartupStatusString("Generating Highways")
	-- Pre-compute which N/S directions exist at each spur x so the junction type
	-- is correct when N and S satellites share the same x column.
	local juncXSet = {}
	local juncHasN = {}
	local juncHasS = {}
	for _, sat in ipairs(satellites) do
		if math.abs(sat.z) >= LSZ then
			juncXSet[sat.x] = true
			if sat.z > 0 then juncHasN[sat.x] = true
			else              juncHasS[sat.x] = true end
		end
	end
	buildHighwayEW(LC, Net, W, 0, skipCenters, juncXSet)
	local placedJunc = {}
	for _, sat in ipairs(satellites) do
		if math.abs(sat.z) >= LSZ then
			if not placedJunc[sat.x] then
				local juncPath
				if juncHasN[sat.x] and juncHasS[sat.x] then
					juncPath = "packs/vanilla/highroad_crosstl"
				elseif juncHasN[sat.x] then
					juncPath = "packs/vanilla/highroad_jnew_tl"
				else
					juncPath = "packs/vanilla/highroad_jsew_tl"
				end
				forceHighwayLot(LC, W, sat.x, 0, juncPath, 'n')
				placedJunc[sat.x] = true
			end
			buildHighwayNS(LC, Net, W, sat.x, sat.z, skipCenters)
			Net:doKeepAlive()
		end
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

	-- Terrain conforming runs last so a crash here won't kill cities or highways.
	Net:forceUpdateStartupStatusString("Conforming Roads To Terrain")
	conformRoadsToTerrain(W, LC, Net, 0, 0, MAIN_CITY_RADIUS)
	for _, sat in ipairs(satellites) do
		conformRoadsToTerrain(W, LC, Net, sat.x, sat.z, SAT_CITY_RADIUS)
		Net:doKeepAlive()
	end

	W:genLotCache()
end
