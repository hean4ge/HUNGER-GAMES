--[[
	Lore - the names the game speaks, kept in one place (Roadmap §2 glossary), so a
	rename is a single edit. Client and server.

	Player-facing text only. Code ids (Config.Events' keys, the ArenaEvent value and the like) keep their names until
	the Phase 7 lore pass.
	Never put a source-franchise name in this module (Roadmap §7).

	Use:
		local Lore = require(ReplicatedStorage.Shared.Lore)
		Lore.Offering             --> "the Offering"   sentence form
		Lore.upper("Offering")    --> "THE OFFERING"   banners and HUD lines
		Lore.bare("RollCall")     --> "Roll Call"      without the article
		Lore.cap("Border")        --> "The border"     at the start of a sentence
	An unknown key is returned as given, so a typo shows on screen instead of erroring.

	One arena's names (docs/design/Map1Build.md, decisions 9 and 14): the names below are the forest arena's. The
	names in MAPS[Config.Map] are laid over them when this module loads, so text follows the arena in the place with no
	change to any reader. The KEYS never change: Lore.Spire is "the arena's centre, where the supplies are" on every
	map ("the Spire" in the forest, "the Horn" on Map 1). Lore.map is the arena whose names are in use.
	The start signal: its sound is a horn on every map, but its word in text is Lore.StartSignal, because on Map 1 the
	centre is called the Horn. (The old key Lore.Horn, the start signal, is gone: nothing read it.)
]]

local Lore = {}

-- The show and its people
Lore.Game = "LAST STANDING"
Lore.Contender = "contender" -- a player in a round
Lore.Contenders = "contenders"
Lore.Wardens = "the Wardens" -- the arena's directors
Lore.Herald = "the Herald" -- the Wardens' voice
Lore.Citadel = "the Citadel"

-- Places
Lore.Vale = "the Vale" -- the arena valley
Lore.Arena = "the arena"
Lore.Spire = "the Spire" -- the arena's centre, where the supplies are (the forest arena's monolith)
Lore.Cover = "the trees" -- where a contender who turns away from the centre runs to ("RUN FOR THE TREES")
Lore.Plate = "launch plate"
Lore.Plates = "launch plates"
Lore.Tor = "the Tor" -- the lobby island
Lore.RunnerCache = "runner's cache" -- a supply crate behind the plates, marked by a pale flag (QW7)
Lore.RunnerCaches = "runner's caches"
Lore.WaitingGrounds = "the Waiting Grounds" -- the Tor's courtyard

-- The round's beats
Lore.StartSignal = "the horn" -- the sound that starts a round, as text says it
Lore.Border = "the border" -- the force field that closes on the centre
Lore.RollCall = "the Roll Call" -- the nightly sky show of the fallen
Lore.Fallen = "the Fallen"
Lore.Knell = "the Knell" -- one toll from the centre for each contender who falls
Lore.Offering = "the Offering" -- the centre's restock on the second morning
Lore.LastStand = "the Last Stand" -- the ring closing to nothing at the end
Lore.PracticeRound = "practice round"
Lore.Dusk = "dusk"
Lore.Dawn = "dawn"

-- Names that belong to one arena, by Config.Map.
local MAPS: { [string]: { [string]: string } } = {
	ClassicForest = {},
	GreenLand = {
		Vale = "the Green Land",
		Spire = "the Horn", -- the horn of plenty at the heart of the Green Land
		Cover = "the hills", -- the plinths stand in an open meadow: the first trees are 150 studs behind them
		StartSignal = "the signal", -- the centre is the Horn here, so the start is not called a horn in text
	},
}

Lore.map = "ClassicForest"
do
	-- Config sits beside this module (on a client it may still be on its way: waited for, a few seconds at most); a
	-- copy of Lore that stands alone (a test) keeps the forest arena's names
	local configModule = script.Parent and script.Parent:WaitForChild("Config", 8)
	if configModule and configModule:IsA("ModuleScript") then
		local ok, config = pcall(require, configModule)
		if ok and type(config) == "table" and type(config.Map) == "string" then
			Lore.map = config.Map
		end
	end
	local names = MAPS[Lore.map]
	if names then
		for key, value in pairs(names) do
			(Lore :: any)[key] = value
		end
	end
end

local function lookup(key: string): string
	local value = (Lore :: any)[key]
	if type(value) == "string" then
		return value
	end
	return key
end

-- "THE OFFERING"
function Lore.upper(key: string): string
	return string.upper(lookup(key))
end

-- "Offering" (drops a leading "the ")
function Lore.bare(key: string): string
	local value = lookup(key)
	local stripped = string.match(value, "^[Tt]he%s+(.+)$")
	return stripped or value
end

-- "The Offering"
function Lore.cap(key: string): string
	local value = lookup(key)
	return string.upper(string.sub(value, 1, 1)) .. string.sub(value, 2)
end

return Lore
