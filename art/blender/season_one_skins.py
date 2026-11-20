# Season one weapon skins and wraps (CardMenusAndShop.md section 3.1, items 1-29) as recipes on WeaponsV3.
#
# A skin never changes the mesh: it re-colours (and may re-material) the parts of every star tier of its
# weapon by role, and some add extra parts that sit inside the silhouette (built by season_one.py, welded in
# the weapon's Grip frame; the WeaponsV3 core geometry is identical for t1..t5, so one extra fits all tiers).
#
# Recipe keys (applied in this order, later wins):
#   group keys by the part's finishRole: "Steel" (all Steel roles except Edge), "Leather", "Cord", "Wood",
#        "Brass" (Brass + Inlay), "Rope"
#   role keys: "Blade", "Edge", "Fitting", "Satin", "Etch", "LayerLight", "LayerDark", "Grip", "Wrap", "Tassel", ...
# Each value: (r, g, b) or ((r, g, b), "RobloxMaterial"). Roles a recipe does not name keep their star finish.
# "Layer" tone: when "Steel" is set and LayerLight / LayerDark / Etch are not, they follow the Steel tone
# (+18 / -22 / -30) so the t4-t5 pattern layers stay readable.

SKINS = [
    # --- Longsword ---
    dict(n=1, id="skin_sword_blued_steel", weapon="sword", name="Blued Steel", grade="Plain", source="C, Shelf",
         roles={"Steel": (84, 98, 122), "Edge": (150, 160, 176), "Fitting": (120, 120, 118), "Brass": (120, 120, 118),
                "Leather": (74, 54, 40), "Cord": (74, 54, 40)},
         look="Heat-blued matte slate-blue blade; plain grey guard and pommel; dark-brown leather grip"),
    dict(n=2, id="skin_sword_riverstone", weapon="sword", name="Riverstone", grade="Crafted", source="C, Shelf",
         roles={"Steel": (116, 118, 120), "Edge": (172, 174, 174), "Fitting": (104, 106, 108), "Brass": (104, 106, 108),
                "Leather": (78, 92, 112), "Cord": (78, 92, 112)},
         extras=["wave"], look="Low-contrast grey wave-pattern blade (two raised wave lines a side); slate-blue cord grip"),
    dict(n=3, id="skin_sword_temper_line", weapon="sword", name="Temper Line", grade="Prized", source="C, Shelf",
         roles={"Steel": (128, 126, 120), "Edge": (184, 182, 176), "Brass": (164, 132, 74)},
         extras=["temper_bands", "ricasso_collar"], look="Straw, bronze and blue temper bands up from the guard; brass collar at the ricasso"),
    dict(n=4, id="skin_sword_oakcrown", weapon="sword", name="Oakcrown", grade="Storied", source="C, Shelf",
         roles={"Steel": (124, 122, 116), "Fitting": (164, 132, 74), "Brass": (164, 132, 74),
                "Leather": (104, 46, 42), "Cord": (104, 46, 42), "Tassel": (164, 132, 74)},
         extras=["oak_leaves", "fuller_inlay"], look="Oak-leaf quillons in brass inside the guard's footprint; brass fuller line; oxblood grip"),
    dict(n=5, id="skin_sword_starfall", weapon="sword", name="Starfall", grade="Fabled", source="P50 (season exclusive)",
         roles={"Steel": (72, 74, 80), "Edge": (170, 172, 176), "Fitting": (88, 90, 96), "Brass": (88, 90, 96),
                "Leather": (62, 64, 72), "Cord": (62, 64, 72), "Tassel": (104, 120, 140)},
         extras=["crosshatch", "pommel_stone"], look="Dark-grey meteoric blade with a raised crosshatch; rough blue-grey stone in the pommel"),
    # --- Hatchet ---
    dict(n=6, id="skin_hatchet_camp_orange", weapon="hatchet", name="Camp Orange", grade="Plain", source="F2",
         roles={"Blade": ((196, 104, 52), "SmoothPlastic"), "Fitting": ((196, 104, 52), "SmoothPlastic"),
                "Edge": (176, 174, 168), "Wood": (176, 140, 96)},
         look="Safety-orange painted head with the honed steel edge showing; plain hickory haft"),
    dict(n=7, id="skin_hatchet_northwood", weapon="hatchet", name="Northwood", grade="Crafted", source="C, Shelf",
         roles={"Blade": (76, 74, 72), "Fitting": (76, 74, 72), "Edge": (198, 196, 188), "Wood": (172, 142, 102)},
         extras=["haft_bands"], look="Oiled ash haft with three carved bands; darkened head, bright honed bevel"),
    dict(n=8, id="skin_hatchet_rime", weapon="hatchet", name="Rime", grade="Prized", source="C, Shelf",
         roles={"Blade": ((186, 194, 202), "Glacier"), "Fitting": (176, 182, 188), "Edge": (214, 218, 222),
                "Cord": ((150, 148, 144), "Fabric"), "Leather": ((150, 148, 144), "Fabric")},
         look="Pale frosted-grey head (Roblox Glacier material, matte); grey wool strip on the haft"),
    dict(n=9, id="skin_hatchet_copperhead", weapon="hatchet", name="Copperhead", grade="Storied", source="C, Shelf",
         roles={"Blade": (176, 108, 70), "Fitting": (176, 108, 70), "Edge": (204, 156, 116),
                "Cord": ((98, 70, 48), "Leather")},
         extras=["verdigris_patches", "butt_cap"], look="Hammered copper head with verdigris patches; braided leather; copper butt cap"),
    # --- Twin-Bit Axe ---
    dict(n=10, id="skin_twin_axe_ironbark", weapon="twin_axe", name="Ironbark", grade="Crafted", source="C, Shelf",
         roles={"Steel": (72, 58, 48), "Edge": (152, 142, 130), "Wood": (98, 76, 56), "Brass": (112, 90, 64)},
         look="Blackened-brown heads (never near-black); dark bark-brown haft"),
    dict(n=11, id="skin_twin_axe_sunforge", weapon="twin_axe", name="Sunforge Bronze", grade="Storied", source="P1",
         roles={"Steel": (166, 124, 72), "Edge": (206, 178, 130), "Brass": (186, 146, 86), "Cord": ((98, 70, 48), "Leather")},
         extras=["sunburst"], look="Cast-bronze heads with a low-relief sunburst on each cheek; stitched leather bands"),
    dict(n=12, id="skin_twin_axe_glacier", weapon="twin_axe", name="Glacier", grade="Fabled", source="C, Shelf",
         roles={"Blade": ((196, 210, 222), "Glacier"), "LayerLight": ((206, 218, 228), "Glacier"), "LayerDark": ((170, 186, 200), "Glacier"),
                "Edge": (222, 228, 236), "Fitting": (150, 158, 166), "Etch": (132, 146, 160), "Brass": (150, 158, 166)},
         extras=["fur_collar"], look="Milky blue-white frosted stone heads (Glacier material, matte); grey fur collar; steel langets"),
    # --- Paired Blades ---
    dict(n=13, id="skin_paired_twin_moons", weapon="paired_blades", name="Twin Moons", grade="Prized", source="C, Shelf",
         roles={"Blade": (98, 100, 106), "Edge": (170, 172, 176)},
         rolesL={"Blade": (198, 200, 204), "Edge": (222, 222, 224)},
         extras=["moon_discs"], look="Left blade pale silver, right gunmetal; each guard carries a moon-phase disc"),
    dict(n=14, id="skin_paired_jade_lacquer", weapon="paired_blades", name="Jade Lacquer", grade="Storied", source="C, Shelf",
         roles={"Fitting": ((88, 140, 112), "SmoothPlastic"), "Satin": ((88, 140, 112), "SmoothPlastic"),
                "Cord": (70, 110, 90), "Blade": (162, 162, 158), "Etch": (120, 120, 118), "Brass": (190, 156, 84)},
         rolesL="same", look="Hilts in matte jade lacquer with brass details; satin blades"),
    # --- Hunting Knife ---
    dict(n=15, id="skin_knife_field_green", weapon="knife", name="Field Green", grade="Plain", source="C, Shelf",
         roles={"Leather": (100, 104, 70), "Cord": (100, 104, 70), "Blade": (140, 140, 134), "Fitting": (110, 112, 104)},
         look="Olive-drab scales; stonewashed blade"),
    dict(n=16, id="skin_knife_antler", weapon="knife", name="Antler", grade="Crafted", source="C, Shelf",
         roles={"Leather": (200, 186, 160), "Cord": (186, 170, 142), "Fitting": (164, 132, 74), "Blade": (160, 160, 156)},
         look="Antler-coloured handle, brass bolster, satin blade"),
    # --- Spear ---
    dict(n=17, id="skin_spear_driftwood", weapon="spear", name="Driftwood", grade="Plain", source="C, Shelf",
         roles={"Wood": (180, 172, 158), "Leather": (150, 140, 124), "Cord": (196, 186, 160)},
         extras=["rope_lashing"], look="Bleached driftwood haft; rope lashing at the socket"),
    dict(n=18, id="skin_spear_stormcaller", weapon="spear", name="Stormcaller", grade="Fabled", source="C, Shelf",
         roles={"Blade": (128, 128, 126), "Edge": (188, 188, 184), "Cord": (96, 108, 126), "Wood": (110, 104, 98)},
         extras=["lightning_inlay", "storm_ferrule"], look="Steel head with a forked lightning line inlaid in silver (not glowing); blue-grey cord; brass storm-cloud ferrule"),
    # --- Bows ---
    dict(n=19, id="skin_bow_hornbow", weapon="bow", name="Hornbow", grade="Prized", source="P21",
         roles={"Wood": (214, 196, 160), "Fitting": (188, 140, 80), "Leather": (98, 70, 48), "Cord": (98, 70, 48), "Rope": (206, 198, 176)},
         look="Cream limbs on an amber laminate (horn); leather grip; waxed string"),
    dict(n=20, id="skin_bow_autumn_leaf", weapon="bow", name="Autumn Leaf", grade="Storied", source="C, Shelf",
         roles={"Wood": (168, 98, 54), "Fitting": (196, 140, 72), "Leather": (110, 70, 44), "Cord": (110, 70, 44)},
         extras=["leaf_rest"], look="Limbs stained amber to rust; leaf-shaped arrow rest"),
    dict(n=24, id="skin_short_bow_birchbark", weapon="short_bow", name="Birchbark", grade="Plain", source="C, Shelf",
         roles={"Wood": (222, 216, 202), "Fitting": (90, 80, 70), "Cord": (120, 100, 80)},
         look="Pale birch-bark limbs with dark tips"),
    # --- the rest ---
    dict(n=21, id="skin_machete_brass_spine", weapon="machete", name="Brass Spine", grade="Crafted", source="C, Shelf",
         roles={"Leather": (178, 150, 108), "Cord": (178, 150, 108)},
         extras=["brass_spine"], look="A brass-capped spine strip along the back of the blade; tan cord grip"),
    dict(n=22, id="skin_ring_blade_moonring", weapon="ring_blade", name="Moonring", grade="Prized", source="C, Shelf",
         roles={"Blade": (176, 178, 180), "Edge": (206, 208, 210), "Cord": (170, 170, 166), "Leather": (170, 170, 166)},
         look="Satin hoop; pale grey cord grip"),
    dict(n=23, id="skin_climb_pick_glacier_guide", weapon="climb_pick", name="Glacier Guide", grade="Crafted", source="C, Shelf",
         roles={"Blade": ((110, 128, 146), "SmoothPlastic"), "Edge": (176, 174, 168), "Wood": (214, 204, 180),
                "Rawhide": (130, 74, 54)},
         look="Chipped blue-grey enamel head; pale birch haft; red-brown wrist loop"),
    dict(n=25, id="skin_leaf_dagger_verdigris", weapon="leaf_dagger", name="Verdigris", grade="Prized", source="C, Shelf",
         roles={"Blade": (98, 150, 128), "Edge": (142, 180, 162), "Fitting": (120, 108, 80)},
         look="Leaf blade with a soft copper-green patina"),
    dict(n=26, id="skin_throwing_knife_bone_grip", weapon="throwing_knife", name="Bone Grip", grade="Plain", source="C, Shelf",
         roles={"Cord": (222, 212, 188), "Fitting": (222, 212, 188), "Blade": (166, 166, 162)},
         look="Pale bone-coloured handles, satin blades"),
]

WRAPS = [
    dict(n=27, id="wrap_checker_plate", weapon="*", name="Checker Plate", grade="Plain", source="C, Shelf",
         roles={"Blade": ((150, 152, 154), "DiamondPlate"), "Fitting": ((150, 152, 154), "DiamondPlate"), "Satin": ((150, 152, 154), "DiamondPlate")},
         look="Steel parts take Roblox's DiamondPlate material; edges and wood unchanged"),
    dict(n=28, id="wrap_cobalt_enamel", weapon="*", name="Cobalt Enamel", grade="Crafted", source="F25",
         roles={"Blade": ((64, 88, 140), "SmoothPlastic"), "Fitting": ((64, 88, 140), "SmoothPlastic"), "Satin": ((64, 88, 140), "SmoothPlastic"),
                "LayerLight": ((78, 104, 156), "SmoothPlastic"), "LayerDark": ((54, 74, 120), "SmoothPlastic")},
         look="Steel parts in matte cobalt enamel; the honed edge stays bare steel"),
    dict(n=29, id="wrap_sandstone", weapon="*", name="Sandstone", grade="Prized", source="C, Shelf",
         roles={"Blade": ((196, 162, 112), "Sandstone"), "Fitting": ((196, 162, 112), "Sandstone"), "Satin": ((196, 162, 112), "Sandstone"),
                "LayerLight": ((214, 184, 136), "Sandstone"), "LayerDark": ((170, 136, 92), "Sandstone")},
         look="Banded ochre-and-buff Sandstone material on non-edge steel; edges stay steel"),
]

GROUP_OF = {  # finishRole -> recipe group key
    "Steel": "Steel", "Leather": "Leather", "Cord": "Cord", "Wood": "Wood", "Brass": "Brass", "Rope": "Rope",
}
