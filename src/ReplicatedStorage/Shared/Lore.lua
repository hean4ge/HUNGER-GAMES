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
Lore.Spire = "the Spire" -- the central supply monolith
Lore.Plate = "launch plate"
Lore.Plates = "launch plates"
Lore.Tor = "the Tor" -- the lobby island
Lore.RunnerCache = "runner's cache" -- a supply crate at the meadow edge, marked by a pale flag (QW7)
Lore.RunnerCaches = "runner's caches"
Lore.WaitingGrounds = "the Waiting Grounds" -- the Tor's courtyard

-- The round's beats
Lore.Horn = "the horn" -- the start of a round
Lore.Border = "the border" -- the force field that closes on the Spire
Lore.RollCall = "the Roll Call" -- the nightly sky show of the fallen
Lore.Fallen = "the Fallen"
Lore.Knell = "the Knell" -- one toll from the Spire for each contender who falls
Lore.Offering = "the Offering" -- the Spire's restock on the second morning
Lore.LastStand = "the Last Stand" -- the ring closing to nothing at the end
Lore.PracticeRound = "practice round"
Lore.Dusk = "dusk"
Lore.Dawn = "dawn"

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
