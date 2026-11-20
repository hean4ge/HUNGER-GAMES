--[[
	CosmeticLooks - THE LOOK TABLE for season one's cosmetics (docs/design/CardMenusAndShop.md section 3.1) and what
	each one does to the game's look. Shared: the server sets skins on held models, every client draws kill icons,
	banners and (through Shared.CosmeticFx) kill effects. Cosmetic only: nothing here is read by combat, and a skin
	only changes the Color of parts that already exist (same parts, sizes, welds and hitbox; Stars.def never sees it).

	One table, swappable later. Every item is drawn from a stand-in today (part colours, Frame glyphs, part VFX). When
	the blender-icons agent's SeasonOne models and icon images are uploaded, the lead fills the three swap tables
	below and nothing else changes:
	  CosmeticLooks.Images     { [id] = "rbxassetid://..." }  kill icons, banners, trims (and any item's card icon)
	  CosmeticLooks.Models     { [id] = "TemplateName" }     a skin's own meshes: ReplicatedStorage.Assets.SeasonOne
	                                                          .<TemplateName>_t<stars> (same Grip and PartRole names as
	                                                          WeaponsV3; TierLooks swaps them in), or a kill effect's prop
	                                                          (the bell, the pennant) as a Model in Assets.SeasonOne
	  (an empty entry keeps the stand-in)

	Ids are the catalogue names in snake case ("blued_steel", "petal_fall", "crossed_axes", "oak_and_iron").
	CosmeticLooks.get also finds an item by its name or by any id that normalises to it ("BluedSteel",
	"skin_blued_steel", "Blued Steel"), so another module's catalogue ids resolve here.

	Grades: Plain, Crafted, Prized, Storied, Fabled, Honour (CosmeticLooks.Grades; colours from the design page 1.3).

	EQUIPPED LOOKS (one per player, saved by Server CosmeticService in Econ.Looks, mirrored to the player attribute
	"LooksJson" so every client can draw anyone's kill icon, kill effect and banner):
	  looks = { s = { [weaponId] = skinOrWrapId }, e = { [weaponId | "*"] = killEffectId },
	            i = { [weaponId | "*"] = killIconId }, b = bannerId, t = trimId }
	  "*" is "use on all weapons"; a weapon's own entry wins over it.

	API
	  CosmeticLooks.get(id) -> item?                     { id, kind, name, grade, weapon?, ... }
	  CosmeticLooks.list(kind?) -> { item }              in catalogue order
	  CosmeticLooks.fits(itemId, weaponId) -> boolean    a skin of that weapon, or a wrap (any weapon); other kinds: true
	  CosmeticLooks.decode(json) -> looks                CosmeticLooks.encode(looks) -> json
	  CosmeticLooks.of(player) -> looks                  from the player's LooksJson attribute (never nil)
	  CosmeticLooks.skinFor(looks, weaponId) -> id?      CosmeticLooks.effectFor / iconFor(looks, weaponId) -> id?
	  CosmeticLooks.applySkin(model, skinId?, fresh?)    recolour a built weapon model (ItemModels.build + Stars.applyFinish)
	                                                     by PartRole; nil or "" puts the star look back. Sets attribute Skin.
	                                                     TierLooks calls it after every star swap or tint, so a menu only
	                                                     sets model:SetAttribute("Skin", id) before Stars.applyFinish.
	  CosmeticLooks.skinMesh(model, stars) -> Model?     a skin's own SeasonOne meshes (TierLooks swaps them in)
	  CosmeticLooks.clean(raw) -> looks                  a safe looks table from anything (DataService uses it)
	  CosmeticLooks.killIcon(id, px, props?) -> CanvasGroup?   the badge (fade it with GroupTransparency)
	  CosmeticLooks.banner(id, props?, trimId?) -> Frame?      a 3:1 card; size it with props.Size
	  CosmeticLooks.gradeColor(grade) -> Color3
]]
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CosmeticLooks = {}

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

-- Swap tables (see the header). Empty until the uploads: the stand-ins draw.
CosmeticLooks.Images = {} :: { [string]: string }
CosmeticLooks.Models = {} :: { [string]: string }

CosmeticLooks.Grades = {
	Plain = { order = 1, color = hex("A39D90") },
	Crafted = { order = 2, color = hex("B87A52") },
	Prized = { order = 3, color = hex("5E9E8E") },
	Storied = { order = 4, color = hex("9E5C78"), text = hex("C58AA3") },
	Fabled = { order = 5, color = hex("C9D3E0") },
	Honour = { order = 6, color = hex("E8D9B0") },
}

function CosmeticLooks.gradeColor(grade: string?): Color3
	local g = grade and CosmeticLooks.Grades[grade]
	return if g then g.color else hex("A39D90")
end

--[[ The catalogue's looks. Skins: `parts` = { [PartRole] = hex } (the WeaponsV3 part roles: Blade, Edge, Fitting,
	Grip, Wrap, Wood, Brass, Rope, Cord, Etch, Inlay, Tassel, Strap, Patch); a role not listed keeps its star colour, so
	the star's detail (etch, inlay, tassel) still shows. `off` = the left blade of the pair, when it differs. Wraps
	(weapon "*") recolour the steel only. ]]
local LIST: { any } = {
	-- weapon skins (26)
	{ id = "blued_steel", kind = "skin", weapon = "sword", name = "Blued Steel", grade = "Plain",
		parts = { Blade = "4E5C6E", Edge = "8D9AA8", Etch = "33404E", Fitting = "7C7E82", Grip = "4A3426", Wrap = "3C2E24" } },
	{ id = "riverstone", kind = "skin", weapon = "sword", name = "Riverstone", grade = "Crafted",
		parts = { Blade = "707070", Edge = "ABABA5", Etch = "4A4A48", Wrap = "4A5A6A", Grip = "3E4C5A" } },
	{ id = "temper_line", kind = "skin", weapon = "sword", name = "Temper Line", grade = "Prized",
		parts = { Blade = "9C8458", Edge = "6E86A0", Etch = "5C4A30", Fitting = "B08A4E" } },
	{ id = "oakcrown", kind = "skin", weapon = "sword", name = "Oakcrown", grade = "Storied",
		parts = { Fitting = "8C6A3C", Etch = "C9A24E", Inlay = "C9A24E", Grip = "5E2C28", Wrap = "B08A4E", Brass = "C9A24E" } },
	{ id = "starfall", kind = "skin", weapon = "sword", name = "Starfall", grade = "Fabled",
		parts = { Blade = "4C4E54", Edge = "8E9196", Etch = "2E3034", Fitting = "68727E", Brass = "7088A0", Grip = "3A3E46" } },
	{ id = "camp_orange", kind = "skin", weapon = "hatchet", name = "Camp Orange", grade = "Plain",
		parts = { Blade = "C8642C", Edge = "B8B4AC", Fitting = "B85A28", Wood = "B08E64" } },
	{ id = "northwood", kind = "skin", weapon = "hatchet", name = "Northwood", grade = "Crafted",
		parts = { Wood = "C6AC82", Blade = "4E4C4A", Edge = "D2CEC4", Grip = "6A4E38" } },
	{ id = "rime", kind = "skin", weapon = "hatchet", name = "Rime", grade = "Prized",
		parts = { Blade = "C4CCD2", Edge = "E4EAEC", Fitting = "AAB4BC", Grip = "8E8E8C" } },
	{ id = "copperhead", kind = "skin", weapon = "hatchet", name = "Copperhead", grade = "Storied",
		parts = { Blade = "A6603A", Edge = "6E9E8E", Fitting = "945634", Grip = "5A3E2A" } },
	{ id = "ironbark", kind = "skin", weapon = "twin_axe", name = "Ironbark", grade = "Crafted",
		parts = { Blade = "40382F", Edge = "9A9288", Fitting = "4C443A", Wood = "5E4A36" } },
	{ id = "sunforge_bronze", kind = "skin", weapon = "twin_axe", name = "Sunforge Bronze", grade = "Storied",
		parts = { Blade = "A27A3E", Edge = "C9A24E", Fitting = "8E6A34", Grip = "6A4A30" } },
	{ id = "glacier", kind = "skin", weapon = "twin_axe", name = "Glacier", grade = "Fabled",
		parts = { Blade = "D2DEE6", Edge = "EEF2F4", Fitting = "B6C2CA", Grip = "8A8A88", Wrap = "9C9C9A" } },
	{ id = "twin_moons", kind = "skin", weapon = "paired_blades", name = "Twin Moons", grade = "Prized",
		parts = { Blade = "5C6066", Edge = "9A9EA4", Fitting = "6A6E74" },
		off = { Blade = "C4C8CC", Edge = "E2E4E6", Fitting = "A8ACB0" } },
	{ id = "jade_lacquer", kind = "skin", weapon = "paired_blades", name = "Jade Lacquer", grade = "Storied",
		parts = { Grip = "3E7A5E", Wrap = "3E7A5E", Fitting = "C9A24E", Blade = "B2B0AA" } },
	{ id = "field_green", kind = "skin", weapon = "knife", name = "Field Green", grade = "Plain",
		parts = { Grip = "5C6440", Strap = "5C6440", Blade = "8E8C86", Edge = "A6A49E" } },
	{ id = "antler", kind = "skin", weapon = "knife", name = "Antler", grade = "Crafted",
		parts = { Grip = "C2B08E", Fitting = "B08A4E", Blade = "B2B0AA" } },
	{ id = "driftwood", kind = "skin", weapon = "spear", name = "Driftwood", grade = "Plain",
		parts = { Wood = "BAB09E", Wrap = "9A8A6A", Cord = "9A8A6A", Grip = "8E8068" } },
	{ id = "stormcaller", kind = "skin", weapon = "spear", name = "Stormcaller", grade = "Fabled",
		parts = { Blade = "8C9298", Etch = "D4D8DC", Inlay = "D4D8DC", Wrap = "52606E", Cord = "52606E", Brass = "B08A4E",
			Tassel = "52606E", Tassel2 = "8C98A6" } },
	{ id = "hornbow", kind = "skin", weapon = "bow", name = "Hornbow", grade = "Prized",
		parts = { Wood = "D6C49C", Grip = "5A4030", Brass = "B89050" } },
	{ id = "autumn_leaf", kind = "skin", weapon = "bow", name = "Autumn Leaf", grade = "Storied",
		parts = { Wood = "A65A2E", Brass = "B87A3E", Grip = "5A3A24" } },
	{ id = "brass_spine", kind = "skin", weapon = "machete", name = "Brass Spine", grade = "Crafted",
		parts = { Fitting = "B08A4E", Etch = "C9A24E", Grip = "B89A70", Wrap = "B89A70" } },
	{ id = "moonring", kind = "skin", weapon = "ring_blade", name = "Moonring", grade = "Prized",
		parts = { Blade = "B4B6B8", Edge = "D8DADC", Etch = "D8DADC", Grip = "A6A8A8", Wrap = "A6A8A8" } },
	{ id = "glacier_guide", kind = "skin", weapon = "climb_pick", name = "Glacier Guide", grade = "Crafted",
		parts = { Blade = "6A8094", Wood = "DED0B2", Grip = "7A4A32", Strap = "7A4A32" } },
	{ id = "birchbark", kind = "skin", weapon = "short_bow", name = "Birchbark", grade = "Plain",
		parts = { Wood = "E0DACA", Grip = "3E3A36" } },
	{ id = "verdigris", kind = "skin", weapon = "leaf_dagger", name = "Verdigris", grade = "Prized",
		parts = { Blade = "5E9E8E", Edge = "8CC0B0", Etch = "3E6E62" } },
	{ id = "bone_grip", kind = "skin", weapon = "throwing_knife", name = "Bone Grip", grade = "Plain",
		parts = { Grip = "DED4BC", Blade = "B2B0AA" } },
	-- wraps (3): the steel of any weapon
	{ id = "checker_plate", kind = "skin", weapon = "*", wrap = true, name = "Checker Plate", grade = "Plain",
		parts = { Blade = "8A9096", Fitting = "7A8086", Edge = "BCC2C6" } },
	{ id = "cobalt_enamel", kind = "skin", weapon = "*", wrap = true, name = "Cobalt Enamel", grade = "Crafted",
		parts = { Blade = "2E4A86", Fitting = "2E4A86", Edge = "C0C2C4" } },
	{ id = "sandstone", kind = "skin", weapon = "*", wrap = true, name = "Sandstone", grade = "Prized",
		parts = { Blade = "C49A64", Fitting = "B8905A", Edge = "C2BEB6" } },

	-- kill effects (9): Shared.CosmeticFx draws them (`fx` is its builder's key)
	{ id = "ash_scatter", kind = "effect", name = "Ash Scatter", grade = "Plain", fx = "ash" },
	{ id = "petal_fall", kind = "effect", name = "Petal Fall", grade = "Crafted", fx = "petals" },
	{ id = "leaf_swirl", kind = "effect", name = "Leaf Swirl", grade = "Crafted", fx = "leaves" },
	{ id = "paper_confetti", kind = "effect", name = "Paper Confetti", grade = "Prized", fx = "confetti" },
	{ id = "feather_burst", kind = "effect", name = "Feather Burst", grade = "Prized", fx = "feathers" },
	{ id = "bell_toll", kind = "effect", name = "Bell Toll", grade = "Prized", fx = "bell" },
	{ id = "flag_drop", kind = "effect", name = "Flag Drop", grade = "Storied", fx = "flag" },
	{ id = "frost_over", kind = "effect", name = "Frost Over", grade = "Storied", fx = "frost" },
	{ id = "recall_beam", kind = "effect", name = "Recall Beam", grade = "Fabled", fx = "beam" },

	-- kill icons (5): `glyph` is the stand-in drawing below
	{ id = "crossed_axes", kind = "icon", name = "Crossed Axes", grade = "Plain", glyph = "axes" },
	{ id = "compass_star", kind = "icon", name = "Compass Star", grade = "Crafted", glyph = "compass" },
	{ id = "wolf_head", kind = "icon", name = "Wolf Head", grade = "Prized", glyph = "wolf" },
	{ id = "laurel", kind = "icon", name = "Laurel", grade = "Storied", glyph = "laurel" },
	{ id = "horned_helm", kind = "icon", name = "Horned Helm", grade = "Fabled", glyph = "helm" },

	-- banners (5) and trims (4)
	{ id = "linen", kind = "banner", name = "Linen", grade = "Plain", free = true, paint = "linen" },
	{ id = "oak_and_iron", kind = "banner", name = "Oak and Iron", grade = "Plain", paint = "oak" },
	{ id = "mountain_dawn", kind = "banner", name = "Mountain Dawn", grade = "Prized", paint = "dawn" },
	{ id = "the_first_ride", kind = "banner", name = "The First Ride", grade = "Honour", paint = "ride" },
	{ id = "top_48", kind = "banner", name = "Top 48", grade = "Honour", paint = "top48" },
	{ id = "regular", kind = "trim", name = "Regular", grade = "Honour", rail = "B08A4E" },
	{ id = "warden", kind = "trim", name = "Warden", grade = "Honour", rail = "8E969C" },
	{ id = "sentinel", kind = "trim", name = "Sentinel", grade = "Honour", rail = "C8CDD2" },
	{ id = "paragon", kind = "trim", name = "Paragon", grade = "Honour", rail = "C9D3E0", frame = true },
}

-- Other modules' ids for the same items (Shared.Crates.Fallback, ShopService's Owned keys): get() finds them, and
-- CosmeticService checks ownership under every one.
local ALIASES: { [string]: string } = {
	sk_sword_blued = "blued_steel", sk_knife_field = "field_green", sk_spear_drift = "driftwood", sk_sbow_birch = "birchbark",
	sk_tknife_bone = "bone_grip", wr_checker = "checker_plate", ke_ash = "ash_scatter", ki_axes = "crossed_axes",
	bn_oak = "oak_and_iron", sk_sword_river = "riverstone", sk_hatchet_north = "northwood", sk_taxe_ironbark = "ironbark",
	sk_knife_antler = "antler", sk_machete_brass = "brass_spine", sk_pick_guide = "glacier_guide", ke_petals = "petal_fall",
	ke_leaves = "leaf_swirl", sk_sword_temper = "temper_line", sk_hatchet_rime = "rime", sk_paired_moons = "twin_moons",
	sk_ring_moon = "moonring", sk_dagger_verdigris = "verdigris", wr_sandstone = "sandstone", ke_confetti = "paper_confetti",
	ki_wolf = "wolf_head", bn_dawn = "mountain_dawn", sk_sword_oakcrown = "oakcrown", sk_hatchet_copper = "copperhead",
	sk_paired_jade = "jade_lacquer", sk_bow_autumn = "autumn_leaf", ke_flag = "flag_drop", ke_frost = "frost_over",
	sk_taxe_glacier = "glacier", sk_spear_storm = "stormcaller", ke_recall = "recall_beam", ki_helm = "horned_helm",
	-- season and rank items (not in the crates), in the same pattern
	sk_hatchet_camp = "camp_orange", sk_taxe_sunforge = "sunforge_bronze", sk_sword_starfall = "starfall",
	sk_bow_horn = "hornbow", wr_cobalt = "cobalt_enamel", ke_feathers = "feather_burst", ke_bell = "bell_toll",
	ki_compass = "compass_star", ki_laurel = "laurel", bn_linen = "linen", bn_ride = "the_first_ride", bn_top48 = "top_48",
}
CosmeticLooks.Aliases = ALIASES

local ITEMS: { [string]: any } = {}
local BY_KEY: { [string]: any } = {}

local function norm(s: string): string
	return (string.gsub(string.lower(s), "[^%w]", ""))
end

local aliasesOf: { [string]: { string } } = {}
for other, mine in pairs(ALIASES) do
	aliasesOf[mine] = aliasesOf[mine] or {}
	table.insert(aliasesOf[mine], other)
end

for i, item in ipairs(LIST) do
	item.order = i
	item.aliases = table.freeze(aliasesOf[item.id] or {})
	table.freeze(item)
	ITEMS[item.id] = item
	BY_KEY[norm(item.id)] = item
	BY_KEY[norm(item.name)] = item
	if item.kind == "skin" and not item.wrap then
		BY_KEY[norm(item.weapon .. item.id)] = item
	end
end
CosmeticLooks.Items = ITEMS

local PREFIXES = { "skin", "wrap", "fx", "effect", "killeffect", "icon", "killicon", "banner", "trim", "ke", "ki", "sk" }

function CosmeticLooks.get(id: any): any
	if type(id) ~= "string" or id == "" or #id > 64 then
		return nil
	end
	local hit = ITEMS[id] or ITEMS[ALIASES[id] or ""]
	if hit then
		return hit
	end
	local key = norm(id)
	hit = BY_KEY[key]
	if hit then
		return hit
	end
	for _, p in ipairs(PREFIXES) do
		if string.sub(key, 1, #p) == p then
			hit = BY_KEY[string.sub(key, #p + 1)]
			if hit then
				return hit
			end
		end
	end
	return nil
end

function CosmeticLooks.list(kind: string?): { any }
	local out = {}
	for _, item in ipairs(LIST) do
		if kind == nil or item.kind == kind then
			table.insert(out, item)
		end
	end
	return out
end

function CosmeticLooks.fits(itemId: any, weaponId: any): boolean
	local item = CosmeticLooks.get(itemId)
	if not item then
		return false
	end
	if item.kind ~= "skin" then
		return true
	end
	return item.weapon == "*" or item.weapon == weaponId
end

-- Equipped looks -------------------------------------------------------------------------------------------------------

local function cleanMap(raw: any, kind: string, perWeapon: boolean): { [string]: string }
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	local n = 0
	for k, v in pairs(raw) do
		if type(k) == "string" and #k <= 32 and type(v) == "string" and n < 64 then
			local item = CosmeticLooks.get(v)
			if item and item.kind == kind and (not perWeapon or CosmeticLooks.fits(item.id, k)) then
				out[k] = item.id
				n += 1
			end
		end
	end
	return out
end

-- A clean looks table from anything (a decoded attribute, a saved Econ.Looks).
function CosmeticLooks.clean(raw: any): { [string]: any }
	local src = if type(raw) == "table" then raw else {}
	local banner = CosmeticLooks.get(src.b)
	local trim = CosmeticLooks.get(src.t)
	return {
		s = cleanMap(src.s, "skin", true),
		e = cleanMap(src.e, "effect", false),
		i = cleanMap(src.i, "icon", false),
		b = if banner and banner.kind == "banner" then banner.id else nil,
		t = if trim and trim.kind == "trim" then trim.id else nil,
	}
end

function CosmeticLooks.decode(json: any): { [string]: any }
	if type(json) ~= "string" or json == "" then
		return CosmeticLooks.clean(nil)
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, json)
	return CosmeticLooks.clean(if ok then data else nil)
end

function CosmeticLooks.encode(looks: any): string
	local ok, json = pcall(HttpService.JSONEncode, HttpService, CosmeticLooks.clean(looks))
	return if ok then json else "{}"
end

function CosmeticLooks.of(player: Instance?): { [string]: any }
	if not player then
		return CosmeticLooks.clean(nil)
	end
	return CosmeticLooks.decode(player:GetAttribute("LooksJson"))
end

function CosmeticLooks.skinFor(looks: any, weaponId: string?): string?
	if type(looks) ~= "table" or type(looks.s) ~= "table" or not weaponId then
		return nil
	end
	return looks.s[weaponId] or looks.s["*"]
end

function CosmeticLooks.effectFor(looks: any, weaponId: string?): string?
	if type(looks) ~= "table" or type(looks.e) ~= "table" then
		return nil
	end
	return (weaponId and looks.e[weaponId]) or looks.e["*"]
end

function CosmeticLooks.iconFor(looks: any, weaponId: string?): string?
	if type(looks) ~= "table" or type(looks.i) ~= "table" then
		return nil
	end
	return (weaponId and looks.i[weaponId]) or looks.i["*"]
end

-- Skins on a model -----------------------------------------------------------------------------------------------------

local ROLE_TO_PART = { Steel = "Blade", Wood = "Wood", Leather = "Grip", Rope = "Rope", Brass = "Brass", Cord = "Wrap" }

local function partRole(p: BasePart): string?
	local r = p:GetAttribute("PartRole")
	if type(r) == "string" then
		return r
	end
	local role = p:GetAttribute("Role")
	return if type(role) == "string" then ROLE_TO_PART[role] else nil
end

local function itemIdOf(model: Instance): string?
	local id = model:GetAttribute("ItemId")
	if type(id) == "string" then
		return id
	end
	return model.Name
end

local function recolour(model: Instance, skin: any)
	local offHand = model:GetAttribute("OffHand") == true
	local map = if skin and offHand and skin.off then skin.off elseif skin then skin.parts else nil
	for _, p in ipairs(model:GetChildren()) do -- (the OffHand child model is coloured on its own)
		if p:IsA("BasePart") and p.Transparency < 1 then
			local base = p:GetAttribute("SkinBase")
			if typeof(base) ~= "Color3" then
				base = p.Color
				p:SetAttribute("SkinBase", base)
			end
			local role = partRole(p)
			local want = map and role and map[role]
			p.Color = if want then Color3.fromHex(want) else base :: Color3
		end
	end
end

-- Recolour a built weapon (and its OffHand child). Same parts, same sizes: only Color changes. skinId nil / "" = the
-- star look. A wrap or a skin that does not fit the weapon is ignored.
function CosmeticLooks.applySkin(model: Instance?, skinId: any, fresh: boolean?)
	if not model or not model:IsA("Model") then
		return
	end
	local id = itemIdOf(model)
	local item = CosmeticLooks.get(skinId)
	if item and (item.kind ~= "skin" or not CosmeticLooks.fits(item.id, id)) then
		item = nil
	end
	-- a new star mesh (TierLooks swapped the parts) or a fresh star tint (fresh = true): the parts' colours now are
	-- the star look, so they become the base the skin goes back to
	if fresh or model:GetAttribute("SkinMesh") ~= model:GetAttribute("TierMesh") then
		for _, p in ipairs(model:GetChildren()) do
			if p:IsA("BasePart") then
				p:SetAttribute("SkinBase", nil)
			end
		end
		model:SetAttribute("SkinMesh", model:GetAttribute("TierMesh"))
	end
	model:SetAttribute("Skin", if item then item.id else "")
	recolour(model, item)
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("OffHand") then
			child:SetAttribute("Skin", if item then item.id else "")
			CosmeticLooks.applySkin(child, if item then item.id else nil, fresh)
		end
	end
end

-- The SeasonOne mesh of a skin at a star, when it ships (CosmeticLooks.Models): TierLooks prefers it.
function CosmeticLooks.skinMesh(model: Instance, stars: number): Model?
	local skin = model:GetAttribute("Skin")
	local name = type(skin) == "string" and CosmeticLooks.Models[skin]
	if not name then
		return nil
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("SeasonOne")
	if not folder then
		return nil
	end
	local m = (model:GetAttribute("OffHand") and folder:FindFirstChild(string.format("%s_L_t%d", name, stars)))
		or folder:FindFirstChild(string.format("%s_t%d", name, stars))
	return if m and m:IsA("Model") and m.PrimaryPart then m else nil
end

-- GUI stand-ins: kill icons and banners (Frames only, no images until CosmeticLooks.Images is filled) ---------------

local function new(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = props.Parent
	for k, v in pairs(props) do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	for _, c in ipairs(children or {}) do
		c.Parent = inst
	end
	inst.Parent = parent
	return inst
end

local function corner(r: number?): UICorner
	return new("UICorner", { CornerRadius = if r then UDim.new(0, r) else UDim.new(1, 0) })
end

-- a box in a 100-unit design square: x, y = centre (0..100), w, h, rot (degrees)
local function box(parent: Instance, color: string, x: number, y: number, w: number, h: number, rot: number?, round: number?, z: number?): Frame
	local f = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x / 100, y / 100),
		Size = UDim2.fromScale(w / 100, h / 100),
		Rotation = rot or 0,
		BackgroundColor3 = Color3.fromHex(color),
		BorderSizePixel = 0,
		ZIndex = z or 1,
		Parent = parent,
	})
	if round then
		corner(if round >= 50 then nil else round).Parent = f
	end
	return f
end

local GLYPHS: { [string]: (Instance, number) -> () } = {}

GLYPHS.axes = function(g, px)
	box(g, "5A4535", 50, 50, 96, 96, 0, 50)
	for _, side in ipairs({ -1, 1 }) do
		box(g, "B08E64", 50, 52, 9, 78, side * 38, 2, 2) -- haft
		local hx, hy = 50 + side * 21, 24
		box(g, "A7AEB2", hx, hy, 26, 18, side * 38, 3, 3) -- head
		box(g, "D8DCDE", hx + side * 6, hy - 6, 14, 5, side * 38, 1, 4) -- honed edge
	end
end

GLYPHS.compass = function(g, px)
	box(g, "9C7A34", 50, 50, 50, 50, 45, 3)
	box(g, "9C7A34", 50, 50, 50, 50, 0, 3)
	box(g, "C9A24E", 50, 50, 14, 92, 0, 6, 2)
	box(g, "C9A24E", 50, 50, 92, 14, 0, 6, 2)
	box(g, "E2C47A", 50, 28, 8, 40, 0, 4, 3) -- north
	box(g, "5A4535", 50, 50, 18, 18, 0, 50, 4)
	box(g, "C9A24E", 50, 50, 8, 8, 0, 50, 5)
end

GLYPHS.wolf = function(g, px)
	local ring = box(g, "4A5A6C", 50, 50, 96, 96, 0, 50)
	local s = new("UIStroke", { Color = Color3.fromHex("E8DFC8"), Thickness = math.max(1, px / 22), Parent = ring })
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	box(g, "E8DFC8", 34, 28, 16, 26, -18, 2, 2) -- ear (cream edge)
	box(g, "6E86A0", 34, 30, 11, 20, -18, 2, 3)
	box(g, "6E86A0", 46, 50, 40, 34, 0, 10, 2) -- skull
	box(g, "6E86A0", 68, 60, 34, 18, 12, 6, 2) -- muzzle
	box(g, "E8DFC8", 82, 64, 8, 8, 0, 50, 3) -- nose
	box(g, "E8DFC8", 50, 44, 7, 5, 0, 2, 3) -- eye
	box(g, "6E86A0", 36, 70, 24, 22, 20, 6, 2) -- neck
end

GLYPHS.laurel = function(g, px)
	box(g, "3A3530", 50, 50, 96, 96, 0, 50)
	for i = 0, 8 do
		for _, side in ipairs({ -1, 1 }) do
			local a = math.rad(200 + i * 17)
			local x = 50 + side * 36 * math.cos(a) * -1
			local y = 50 - 36 * math.sin(a)
			box(g, if i % 2 == 0 then "C9A24E" else "A8862E", x, y, 9, 17, side * (i * 17 - 70), 50, 2)
		end
	end
	new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromScale(0.6, 0.42),
		BackgroundTransparency = 1, Text = "48", TextScaled = true, TextColor3 = Color3.fromHex("E2C47A"), ZIndex = 4,
		FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.SemiBold), Parent = g,
	})
end

GLYPHS.helm = function(g, px)
	local ring = box(g, "2A3038", 50, 50, 96, 96, 0, 50)
	new("UIStroke", { Color = Color3.fromHex("C9D3E0"), Thickness = math.max(1, px / 18), Parent = ring })
	for _, side in ipairs({ -1, 1 }) do
		box(g, "E8DFC8", 50 + side * 30, 30, 10, 30, side * 30, 4, 2) -- horn
		box(g, "C9C0A8", 50 + side * 36, 18, 7, 16, side * 12, 4, 2) -- horn tip
	end
	box(g, "A7AEB2", 50, 50, 46, 44, 0, 18, 3) -- dome
	box(g, "C9A24E", 50, 60, 52, 8, 0, 2, 4) -- brass rim
	box(g, "6C747A", 50, 72, 30, 16, 0, 4, 3) -- face guard
	box(g, "2A3038", 50, 68, 26, 4, 0, 1, 4) -- eye slit
	box(g, "C9A24E", 50, 74, 4, 14, 0, 1, 5) -- nasal
end

-- A kill icon badge (16 design px in the kill feed). A CanvasGroup: fade it with GroupTransparency.
function CosmeticLooks.killIcon(id: any, px: number, props: { [string]: any }?): CanvasGroup?
	local item = CosmeticLooks.get(id)
	if not item or item.kind ~= "icon" then
		return nil
	end
	local g = new("CanvasGroup", {
		Name = "KillIcon",
		Size = UDim2.fromOffset(px, px),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
	local image = CosmeticLooks.Images[item.id]
	if image then
		new("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = image, Parent = g })
	else
		local draw = GLYPHS[item.glyph]
		if draw then
			draw(g, px)
		end
	end
	g:SetAttribute("CosmeticId", item.id)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			(g :: any)[k] = v
		end
	end
	if props and props.Parent then
		g.Parent = props.Parent
	end
	return g
end

local PAINT: { [string]: (Frame) -> () } = {}

PAINT.linen = function(f)
	f.BackgroundColor3 = Color3.fromHex("EDE6D6")
	local inner = box(f, "EDE6D6", 50, 50, 94, 84, 0, 4)
	inner.BackgroundTransparency = 1
	new("UIStroke", { Color = Color3.fromHex("C8BEA8"), Thickness = 1.5, Parent = inner })
	for i = 0, 5 do
		box(f, "E2DAC8", 50, 18 + i * 13, 90, 1.5, 0, nil)
	end
end

PAINT.oak = function(f)
	f.BackgroundColor3 = Color3.fromHex("8E6B4C")
	local shades = { "8E6B4C", "7E5E42", "94704E", "6A4E38" }
	for i = 1, 4 do
		box(f, shades[i], 50, 12.5 + (i - 1) * 25, 100, 24, 0)
	end
	for _, x in ipairs({ 22, 78 }) do
		box(f, "4C4E52", x, 50, 7, 100, 0, nil, 2)
		for _, y in ipairs({ 14, 50, 86 }) do
			box(f, "8E9094", x, y, 3, 9, 0, 50, 3)
		end
	end
end

PAINT.dawn = function(f)
	f.BackgroundColor3 = Color3.fromHex("E8B88A")
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromHex("C9D3E0"), Color3.fromHex("E8B07A")),
		Parent = f,
	})
	box(f, "F0D2A0", 70, 30, 12, 36, 0, 50, 2) -- sun
	box(f, "6E7F96", 28, 92, 46, 46, 45, nil, 3)
	box(f, "56677E", 62, 98, 56, 56, 45, nil, 3)
	box(f, "44546A", 92, 100, 40, 40, 45, nil, 4)
end

PAINT.ride = function(f)
	f.BackgroundColor3 = Color3.fromHex("EBE2CC")
	-- the trestle
	box(f, "5A4535", 50, 70, 100, 4, 0, nil, 2)
	for i = 0, 6 do
		local x = 8 + i * 14
		box(f, "6A5444", x, 85, 2.5, 30, 18, nil, 2)
		box(f, "6A5444", x, 85, 2.5, 30, -18, nil, 2)
	end
	-- the train in silhouette
	box(f, "8E2E26", 34, 58, 18, 18, 0, 2, 3) -- engine
	box(f, "8E2E26", 24, 50, 5, 12, 0, nil, 3) -- stack
	for i = 0, 2 do
		box(f, "8E2E26", 52 + i * 15, 59, 13, 16, 0, 2, 3)
	end
	local stamp = box(f, "EBE2CC", 90, 22, 13, 32, 0, 50, 4)
	stamp.BackgroundTransparency = 1
	new("UIStroke", { Color = Color3.fromHex("8E2E26"), Thickness = 1.5, Parent = stamp })
	new("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "S1", TextScaled = true, ZIndex = 5,
		TextColor3 = Color3.fromHex("8E2E26"), FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.SemiBold),
		Parent = stamp,
	})
end

PAINT.top48 = function(f)
	f.BackgroundColor3 = Color3.fromHex("2E3640")
	box(f, "38424E", 50, 50, 100, 30, 0)
	local seal = box(f, "B08A4E", 84, 50, 21, 62, 0, 50, 3)
	new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = seal })
	new("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "48", TextScaled = true, ZIndex = 4,
		TextColor3 = Color3.fromHex("2E3640"), FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.SemiBold),
		Parent = seal,
	})
end

-- A 3:1 banner card. props: Instance properties (Size, Position, Parent ...). trimId: a trim drawn on top (a rail along
-- the lower edge, or the Paragon frame). Unknown id -> Linen.
function CosmeticLooks.banner(id: any, props: { [string]: any }?, trimId: any): Frame
	local item = CosmeticLooks.get(id)
	if not item or item.kind ~= "banner" then
		item = ITEMS.linen
	end
	local f = new("Frame", {
		Name = "Banner",
		Size = UDim2.fromOffset(240, 80),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		BackgroundColor3 = Color3.fromHex("EDE6D6"),
	})
	corner(6).Parent = f
	local image = CosmeticLooks.Images[item.id]
	if image then
		new("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = image, ScaleType = Enum.ScaleType.Crop, Parent = f })
	else
		local paint = PAINT[item.paint]
		if paint then
			paint(f)
		end
	end
	local trim = CosmeticLooks.get(trimId)
	if trim and trim.kind == "trim" then
		local img = CosmeticLooks.Images[trim.id]
		if img then
			new("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = img, ZIndex = 8, Parent = f })
		elseif trim.frame then
			-- (a stroke draws outside its frame and the banner clips: an inset frame of four rails instead)
			local c = trim.rail
			box(f, c, 50, 4, 100, 6, 0, nil, 8)
			box(f, c, 50, 96, 100, 6, 0, nil, 8)
			box(f, c, 1.5, 50, 2.2, 100, 0, nil, 8)
			box(f, c, 98.5, 50, 2.2, 100, 0, nil, 8)
		else
			local rail = box(f, trim.rail, 50, 95, 100, 7, 0, nil, 8)
			rail.AnchorPoint = Vector2.new(0.5, 0.5)
		end
	end
	f:SetAttribute("CosmeticId", item.id)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			(f :: any)[k] = v
		end
	end
	if props and props.Parent then
		f.Parent = props.Parent
	end
	return f
end

return CosmeticLooks
