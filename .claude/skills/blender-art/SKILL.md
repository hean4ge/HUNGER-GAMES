---
name: blender-art
description: How to make 3D art in Blender for LAST STANDING (and any Roblox game with the same taste). Use it to turn high-level game design into chunky, faceted "realistic blockish" assets that emulate realism inside Roblox's natural look, and for any modelling, look-dev, asset review, creature, item, scene or cinematic work, or whenever a design document describes the world loosely.
---

# Blender art for LAST STANDING

## The one rule
In the owner's words: **"you are not incorporating realism, you are emulating it to the game design of roblox natural aesthetic."**

Realism is the reference, never the target:
- Take real proportions, silhouettes, light, colour values and behaviour from the real thing.
- Express them in Roblox's own language: chunky readable volumes, flat-shaded facets, matte painted colour, and Roblox's Realistic lighting doing the shading.
- Hyper-real detail, photo textures, film grain, glossy plastic and "uncanny" anatomy all make the game look tacky (the owner's word). Leave them out.

## The lens: from high-level design to an asset
When a brief is high-level ("make it like the movie", "a squirrel should look like a squirrel", "the grey room"), reimagine it qualitatively before modelling anything.

1. **Feeling.** What should the player feel when they see it? For example: calm, a trap, wealth, danger, home.
2. **Essence.** Find the 2–4 traits that make it read instantly: the silhouette, the proportion, the motion, the material contrast. Keep those and drop the rest.
3. **Roblox-native form.** Rebuild those traits from a handful of chunky volumes. The facets are the "blocks". The result should look good next to a default avatar and Roblox's terrain grass and water.
4. **Gameplay reads first.** Make it clear what can be climbed, hidden in, picked up or hurt you before it is pretty.
5. **Only now, numbers.** Scale, facet size, colour values, triangle budget, parts (below).
6. **Our own design, the feel of the source.** Use generic genre elements; never copy a film's signature objects, names or logos (docs/Roadmap.md §7, ArenaV3.md §1's avoid list).

| Brief | Reimagined as |
|---|---|
| "a squirrel that looks and behaves like a squirrel" | A 1–1.5-stud faceted body with a big plume tail (the read) and alert ears. Grey-brown in the light band. 300–800 triangles. Quick stop-start animation, freezes, then darts up a trunk. |
| "an engineered creature" | One real animal's silhouette pushed in one deliberate, wrong direction (too long, too many, too symmetrical). It wears one unnatural accent (a seam, a plate), not glowing gore. |
| "the grey launch room" | Plain cast-concrete volumes, a single cool overhead light, the plate and a glass tube. The quiet before the noise. Semi-real: no grime decals, no hyper detail. |
| "blockish realistic-ish hands" | Bare hands built from chunky faceted segments with real finger and thumb proportions and a simple sleeve. The skin takes the player's tone. Relaxed at idle; fists only while punching. |

## The owner's taste
- **Likes:** Roblox terrain water and grass; LightingStyle Realistic; warm dusk light.
- **Dislikes:**
  - card foliage
  - photo-textured, "grainy" surfaces
  - plain-textured buildings
  - cartoonish animals and generic Roblox NPCs
  - glowing fantasy effects and loud trails
  - every past first-person hand (plain block fists, realistic gloves, the player's boxy R15 avatar arms)
- **Every asset is made by us in Blender:** no downloaded, marketplace or AI-generated assets.

## Style rules (docs/design/ArtStyle.md §6 has the full text)
1. **True scale, few volumes.**
   - 1 stud ≈ 0.28 m; a player is 5.5 studs; a door is 4 × 7.5.
   - Nothing modelled or painted smaller than about 0.25 stud, except trim on items.
2. **Facets are the blocks, sized by class:**
   - trees and buildings 1–2.5 studs;
   - cliffs 2–6;
   - rocks and props 0.5–1.5;
   - items and hands 0.1–0.4.
   - No smooth blobs, no cube staircases, no alpha cards.
3. **Grow living things; build built things.**
   - Trees: forked, tapering limbs; tiered or lobed crowns.
   - Rocks: jointed blocks.
   - Buildings: real members as chamfered prisms.
4. **Paint colour per facet; don't texture it.**
   - Lighter and warmer on top, cooler underneath.
   - No grain finer than about 0.3 stud.
   - Normal maps only round edges.
5. **Bake AO only, never below half the painted value.** Everything matte (roughness 0.75–0.95); metal and glass only where they're real.
6. **Values in the light band:**
   - bark 95–120
   - needles G 55–80
   - leaves G 65–95
   - wood 90–130
   - stone 105–140
   - forest floor luma 80–95
   - Saturated colour only for loot and hazards.
7. **Budgets:**
   - trees 3–5k triangles, plus a far mesh;
   - buildings ≤ 10k, each part under 5k;
   - props and items 300–1,500;
   - boulders 150–400.
8. **Approve it in game, not in Blender.** Put it in the StyleTest diorama next to terrain grass and water, and capture it at 14:00 and 17:30.

## How we build (art/README.md)
- **Generators, not hand edits.**
  - Every asset comes from a seeded script in `art/blender/`, run headless:
    `blender --background --factory-startup --python art/blender/<set>.py -- <export dir> <preview dir>`.
  - To change an asset, change the script and re-run it. Never hand-edit an exported file.
- **Export:**
  - GLB with tangents, textures ≤ 1024 px, ≤ 20k triangles per mesh, single-sided;
  - exports go to `%USERPROFILE%/OneDrive/Documents/LastStanding/BlenderExports`;
  - every GLB comes with a manifest JSON (pieces, triangles, pivots, attachments, materials).
- **Previews:** in `art/previews/<Set>/`. Look at every one yourself before anyone else sees it.
- **Upload once.**
  - Use Open Cloud `POST /assets/v1/assets` (Model type).
  - Record the ids in `art/manifests/<Set>.assetIds.json` and reuse them.
  - An upload is permanent and needs the owner's go-ahead.
- **Import:** Studio's importer creates the SurfaceAppearances. Build templates by script (`ServerStorage.WorldGen.RealAssets` style), then check them in the diorama and in a playtest.

## Tools
- **The Blender MCP** (`tools/blender_mcp`):
  - `blender_run_script` runs a generator;
  - `blender_inspect_model` reports triangles, sizes and materials;
  - `blender_render_preview` renders a quick look at midday or dusk;
  - `blender_live_exec` and `blender_live_screenshot` work in an open Blender window that has the bridge add-on enabled.
- **Without the MCP:** the same work runs as headless command lines.

## Review checklist (before showing the owner)
- [ ] It reads as the right thing in silhouette at 100 studs (at arm's length for held items and hands).
- [ ] It's built from chunky facets at its class size: no smooth blobs, no hyper-detail, no grain.
- [ ] Its values are in the light band at 14:00 and still readable at 17:30 and at night.
- [ ] It sits naturally next to terrain grass and water and a default avatar.
- [ ] It's within its triangle budget, and its parts are split sensibly (recolourable skin, colliders, far meshes).
- [ ] Gameplay reads: climbables flat and tagged, cover solid, foliage non-colliding, doors 4 × 7.5.
- [ ] It's original: no copied signature objects, names or logos.
- [ ] It's been seen in game, not just in a render.

## Category notes
- **First-person hands:**
  - Bare faceted hands, real proportions, a simple sleeve, and skin that takes the player's tone.
  - Hand shapes: relaxed (idle), fist (punch only), grip, and open.
  - The crosshair area always stays clear.
  - Keep the art/README.md arm-kit conventions: pivots, Grip, Palm and Knuckles.
- **Animals:**
  - Believable anatomy and motion in faceted form.
  - Rig with few bones; export a skinned GLB or FBX for Roblox.
  - Behaviour sells it: flee, freeze, hide.
- **Engineered creatures:** one clear design idea each, plus a sound, a movement pattern and a tell. Never a reskinned NPC with a big health bar.
- **Interiors and cinematics (the launch room, a training hall):** a few strong volumes, one key light, restrained colour, slow and deliberate camera moves. Semi-real, never hyper-real.
- **Effects:** restrained and natural: dust, mist, sparks, a faint arrow streak. Nothing neon or fantasy.

## Where things live
- `docs/design/ArtStyle.md`: the style, its rules and the measurements.
- `art/README.md`: the pipeline and conventions.
- `docs/design/owner/`: the owner's own design documents.
- Memory: `last-standing-art-direction`.
