-- ─── No-Spawn Building List ──────────────────────────────────────────────────
-- Buildings listed here will NEVER auto-spawn in generated cities/maps, so players
-- have to build them themselves. This is the same effect as the vanilla "NOSPAWN"
-- lot flag, but applied from Lua so it survives Steam updates and doesn't touch any
-- game data file. doNotSpawn only blocks map-gen placement -- everything here is
-- still fully buildable from the in-game build menu.
--
-- TO EDIT: just add or remove display names (exactly as they appear in the build
-- menu) from the NO_SPAWN table below. Names are matched against LotPackItem.name.

local NO_SPAWN = {
	["Helifield"]     = true,   -- vanilla air transport (helipads)
	["Airfield"]      = true,   -- vanilla air transport (light plane)
	["Large Airport"] = true,   -- modded "More Commerce" pack airport
}

-- Walk every loaded lot pack item and flag the ones on our list. Idempotent, so it's
-- safe to call as often as we like. Wrapped per-item in pcall in case doNotSpawn is
-- read-only for a given item (strictlua: an uncaught error would crash the server).
local function applyNoSpawn()
	local LPC = turf.LotPackContainer:getInstance()
	if not LPC then return 0 end
	local n = LPC:getNLotPackItems()
	local applied = 0
	for i = 0, n - 1 do
		local LPI = LPC:get(i)
		if LPI and NO_SPAWN[LPI.name] then
			if pcall(function() LPI.doNotSpawn = true end) then
				applied = applied + 1
			end
		end
	end
	return applied
end

-- 1) Apply once at boot (when this script loads). If the lot packs are already loaded
--    by now this is all that's needed.
pcall(applyNoSpawn)

-- 2) Belt-and-suspenders: re-apply at the start of every map generation by chaining
--    get_footprints (the vanilla function called right before city building selection).
--    Guarantees the flags are set even if the packs weren't ready at boot. We MUST be
--    loaded before any other mod that wraps get_footprints so this runs first.
local _ns_orig_get_footprints = get_footprints
if type(_ns_orig_get_footprints) == "function" then
	function get_footprints(W, LC, radius, startX, startZ, maxPlayerBases)
		pcall(applyNoSpawn)
		return _ns_orig_get_footprints(W, LC, radius, startX, startZ, maxPlayerBases)
	end
end
