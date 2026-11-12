# Part 2 and Part 3 plan (lead's notes)

Part 2 starts when Part 1 (world, motion, day/night), Part 1b (realistic structures and items art) and the
bow fix have reported. Read every agent report first, then brief the Part 2 agents with what is below.

> **Update, 12 November 2026:** Part 2 is done: the uploads, the templates, the items swap, the set dressing, the movement polish and QA. The playability quick wins were added too. See [Status.md](Status.md) for the current state, what's verified, and the next steps. The notes below are kept as history.

## Status on 2026-11-11 (after the network-outage restart)

- **Part 1b art is done.** The art director reviewed all six realistic sets: 87 assets in 8 GLBs
  (TreesReal, GroundReal_Flora, GroundReal_Rocks, GroundReal_Cliffs, LandmarksReal, BuildingsReal,
  PropsReal, ItemsReal). `ad_finalize.py` checks the Roblox limits on every set and reports 0 problems.
  - Drive the import from `BlenderExports/RealSets.index.json`.
  - The import checklist is in `art/README.md` section 11.4.
  - There are 77 unique upload images. Never upload `textures/*/glb_only/*`.
  - Nothing is uploaded yet.
- **The must-dos below are done**, apart from the one-asset Studio test:
  - The tangent re-export is done.
  - Separate 8-bit grayscale roughness PNGs are exported. The packed metallicRoughness stays embedded in the GLBs only.
  - GroundReal is split into three GLBs to stay under 20 MB.
- **No ArmsReal was built.** The user wants the original v1 part-built first-person hands. Those were
  restored (ViewmodelController and Poses are byte-identical to v1; Rig is v1 plus mesh-item handling),
  and `Lighting.LightingStyle` is now Realistic. The manual step below is done.
- **The bow-aim fix** (keep the target visible while drawing and shooting) was running when this was written.
- **Two testing gotchas:**
  - A minimised Studio window stops RenderStepped, so `screen_capture` times out and the viewmodel doesn't update.
  - Don't give test items by requiring InventoryService from `execute_luau`: it returns an un-initialised copy. Set `ClientState.inventory` on the client instead.
- **Known art limits** to keep in mind while dressing the world:
  - Spruce and fir cards read flat within 8-15 studs.
  - Cliffs still read blocky at arm's length.
  - Tall grass reads golden under strong sun.
  - LandmarksReal.glb has only 0.38 MB of headroom under the 20 MB limit.

## Must-dos before any upload

- **Re-export every textured GLB with tangents.** The research found `export_tangents=False` in
  `gr_export.py` (around line 180), `trees_real.py` (around line 1623) and `tex_items.py` (around line 927).
  Roblox needs tangents on imported meshes, or normal maps may show no effect. Check the Part 1b
  generators too (`landmarks_real.py`, `buildings_real.py`, `arms_real.py`). Fix any mesh without UVs
  that blocks tangent export, re-run the generators, and confirm the tangents are present in the
  glTF JSON.
- Decide whether to export separate 8-bit grayscale roughness and metalness PNGs instead of relying
  on the importer to split glTF's packed metallicRoughness image. Test one asset in Studio first (one
  upload), then do the rest the same way.
- Upload each GLB once. Reuse asset IDs. Never re-upload to dodge a pending moderation state.
- Don't upload v1 `Foliage.glb`, `Rocks.glb`, `Landmarks.glb`, `Buildings.glb` or `Props.glb`; the
  realistic sets replace them. `Items.glb` and `Arms.glb` are already uploaded (assets 89569069083663 and
  130319005401961); `ItemsReal.glb` and `ArmsReal.glb` replace them in the templates.

## Part 2 agents (planned)

1. **integrate:world-assets**: upload TreesReal, GroundReal, LandmarksReal and BuildingsReal/PropsReal
   (after the tangent re-export) and build `ServerStorage.MeshAssets` templates. Follow the
   `rbx-import-asset` skill and `docs/research/LookDevPlaybook.md` (foliage: AlphaMode Transparency with
   Transparency 0, real back faces with DoubleSided off).
2. **integrate:items-realistic**: swap ItemsReal (items and crates only) into `ReplicatedStorage.Assets`.
   Do NOT integrate ArmsReal: the user wants the original part-built first-person hands (restored by the
   viewmodel-old-hands-bow workflow). Keep that workflow's bow-aim pose and re-run its screen-coverage
   check. Apply `docs/handoff/ItemsArmsNotes.md`.
3. **world:set-dressing**: populate the new terrain from ArenaLayout's scatter rules; Spire, plaza,
   plates, cabin, tower, bridge, camps; loot markers; streaming and performance budgets.
4. **lookdev:shading**: work through the playbook's prioritized tasks, starting with:
   - rebalance `Shared.DayCycle` for LightingStyle Realistic
   - custom valley skybox
   - terrain PBR MaterialVariants
   - wind
   - hide the sun/moon switch near clock 19.2 and 4.7 (measure it); it lands during Roll Call 1
   - eye adaptation and zone looks
   - atmospheric depth
   - fire and ember lighting
   - shadow and light budgets
   - detail decals
5. **movement:polish**:
   - The user said "jumping is tacky". Check the movement agent's new jump against that, and tune
     slopes and footing on the dressed terrain.
   - The user also said "make the roblox charachter the same as a normal one": stop PlayerService
     forcing standard body scales and proportions, so avatars load as they normally look.
   - Make the movement code fit any avatar size: crouch height, mantle reach, the first-person body,
     the Fallen busts and the hitboxes must follow each avatar's measured rig (measureRig) instead of
     one standard size.
   - Keep the realistic animations.
6. **qa:integration**: full loop playtest, performance on low quality levels, fixes.

## Manual steps for the user

- ~~Lighting → LightingStyle → Realistic, keeping PrioritizeLightingQuality on.~~ Done by an agent on
  2026-11-11. It turned out to be writable from `execute_luau` in the Edit datamodel.
- Studio Settings → Rendering → Editor Quality Level to the highest during look-dev, so screenshots
  match the game.
- Later, only when no agent is editing terrain: decide on Workspace.ExpandedTerrain (up to 62 custom
  terrain materials). It restarts the place.

## Part 3: combat physics

The plan is in `docs/research/CombatPhysicsPlan.md`: phases 0-7, 13 open questions. The recommended
defaults (to confirm with the user before building):
- a simple guard with a perfect-block window
- tap for a light attack, hold for a heavy one
- attack direction from mouse or stick motion
- ragdoll corpses that stay until the round ends (Moderate content label)
- no blood
- knockdowns only from heavy head hits or when exhausted
- near-real thrown speeds with assist
- hit zones, torso-only armour and light wounds
- realistic reach with visible wind-ups
- exhaustion weakens swings
- loot stays on the corpse
- procedural third-person poses first
- stay on the current networking model
