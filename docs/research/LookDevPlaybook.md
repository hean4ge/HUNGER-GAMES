# LAST STANDING - Look-Dev Playbook (Roblox rendering, shading, atmosphere)

Research date: 2026-11-10. Engine docs checked on that date (create.roblox.com pages show `last_updated 2026-11-10`).
The place audit (section 8) is a read-only snapshot of placeId 120572716460286 taken the same day. Other agents
were editing the place at the time. Sources are tagged `[S#]` and listed with URLs in section 15. **[unverified]**
marks anything I could not confirm from a primary source. Test those items in Studio before relying on them.

Roblox has no user shader language. "Shaders and shading" here means choosing and tuning the engine's fixed
feature set: the lighting engine, PBR surfaces, atmosphere and sky, water, post-processing, and scripted tricks.
This document is the playbook for the look-dev pass that follows placing the new Blender art on the new terrain.

---

## 0. TL;DR - the eight things that matter most

> **Update, 11 November 2026:** the place now uses `LightingStyle = Realistic`, with `PrioritizeLightingQuality` on. It
> can be set from the Edit datamodel (Studio's command bar or the MCP's `execute_luau`), though not from game scripts at
> runtime, so the "by hand only" notes below are out of date. Task 2 (tangents and separate grayscale roughness maps) is
> also done; see `art/README.md` §11.

1. **The place renders with `Lighting.LightingStyle = Soft`.** Roblox calls Soft "a flat, retro-Roblox look"
   [S2][S3]. `ShadowSoftness` has no effect in Soft [S2]. Local lights don't cast proper shadows or give
   specular highlights the way Realistic does [S28][S29]. Switch to **Realistic** by hand in the Properties panel,
   because it can't be set by script [S4][S5], and keep `PrioritizeLightingQuality = true`. No other change gives as
   much realism. `docs/GameDesign.md` still says "set Technology to Future". That property is deprecated, and the
   place's Technology value was migrated automatically (`RBX_LightingTechnologyUnifiedMigration`).
2. **Every textured GLB is exported without tangents.** `export_tangents=False` is set at `gr_export.py:180`,
   `trees_real.py:1623` and `tex_items.py:927`. Roblox expects imported meshes to carry tangents. Without them,
   normal maps may make no visible difference [S9][S12]. Re-export with `export_tangents=True` (MikkTSpace, which
   matches the Blender bakes) before the textures are judged in Studio.
3. **Raise the sky's share of fill light and lower the flat ambient.** `EnvironmentDiffuseScale` is the only fill
   term that follows the sky and the time of day. `Ambient`/`OutdoorAmbient` are flat [S1]. Roblox's realistic
   tutorials use `EnvironmentDiffuseScale = EnvironmentSpecularScale = 1` [S28][S29]. Metalness does nothing when
   `EnvironmentSpecularScale` is 0 [S9]. The current values are 0.6/0.9 with a high flat ambient
   (`Ambient 70,72,82`, `OutdoorAmbient 108,112,126`), which gives flat, milky shadows.
4. **Replace the default 2020 Roblox skybox with our own.** The sky is the image-based lighting (IBL) source for
   diffuse fill and reflections [S34]. The Atmosphere also takes most of its colours from the skybox [S28]. Use a
   valley/mountain sky whose lower hemisphere is darker and terrain-coloured [S28].
5. **The world is still: `Workspace.GlobalWind = (0,0,0)`.** Wind drives terrain grass, dynamic clouds and
   particles [S22]. Set a breeze and script gusts on the client. This is the cheapest "alive" upgrade.
6. **The day/night look already exists as `Shared.DayCycle.Looks`.** It is keyframed and applied on the client every
   frame. Build on it rather than replacing it. Add these: re-tuned values for Realistic (section 9); a brightness dip
   at the engine's sun-to-moon hand-off, which community reports place near 19.2 h and 4.7 h, so it needs measuring
   [S45]; Clouds, depth of field, water and wind tracks; and zone and eye-adaptation layers (section 10).
   **Roll Call 1 starts at 18.55, and the night then runs at about 4 in-game hours per minute, so the hand-off
   lands inside the Roll Call show.**
7. **Foliage cards follow the right recipe.** Use `AlphaMode = Transparency` with `MeshPart.Transparency = 0`
   for depth-correct cut-outs with no sorting, and real flipped back faces with `DoubleSided = false`. The art
   pipeline already does this [S8][S9]. Expect a screen-door dither at low quality levels [S46]. Roblox has no
   translucency or two-sided lighting on foliage [S47], so fake it (section 6).
8. **Performance comes down to three things.** First, shadowed local lights: they are capped per frame, point
   shadows cost the most and narrow spots the least [S6]. Second, small parts that cast shadows; 5,074 of 6,981
   parts do today. Third, transparent overdraw [S7][S31]. Below graphics quality level 4, shadows switch off
   entirely [S7], so every scene must also read without shadows.

---

## 1. What we control (Roblox has no shaders)

| Effect a shader would give | Roblox tool | Notes |
|---|---|---|
| Lighting model | `Lighting.LightingStyle` (Realistic / Soft) + `PrioritizeLightingQuality` | Set by hand only [S4][S5] |
| PBR surfaces | `SurfaceAppearance` (per MeshPart, UV-mapped) and `MaterialVariant` (tiling, parts + terrain) | Colour, normal, roughness, metalness, emissive [S8][S12] |
| Detail layers | PBR `Decal` / `Texture` (they now take normal, roughness, metalness and emissive maps) | Don't batch well; use sparingly [S39][S7] |
| Sky, fog, aerial perspective | `Sky`, `Atmosphere`, `Clouds` (under Terrain) | `Lighting.Fog*` is ignored when an Atmosphere exists [S1] |
| Water | Terrain water properties (global) | One water look for the whole place [S16][S17] |
| Grading / tonemap | `ColorCorrectionEffect` (stackable), `ColorGradingEffect.TonemapperPreset` | No LUT or curves [S23][S24] |
| Lens effects | `BloomEffect`, `SunRaysEffect`, `DepthOfFieldEffect`, `BlurEffect` | In Lighting (everyone) or Camera (one player) [S23] |
| Vertex animation / wind | `GlobalWind` (grass, clouds, particles), CFrame sway, skinned meshes + Bones | Trees can't move with "actual wind" [S32] |
| Volumetrics | Atmosphere + ParticleEmitters + Beams | Duvall Drive used Beams for "volumetric lighting" [S32] |
| Auto-exposure, local grading | Client scripts writing `ExposureCompensation` / effects | Section 10 |

Not available: custom shaders, lightmaps or baked GI, screen-space reflections (outdoor reflections come from the
skybox), parallax or tessellation, subsurface or translucency, LUTs, and user-controlled AO.

---

## 2. Lighting engine

### 2.1 LightingStyle and PrioritizeLightingQuality (they replace `Technology`)

Unified Lighting launched as a beta on 2025-01-21 and went fully live on 2025-07-23 [S4]. `Lighting.Technology` is
now deprecated and readable only by Roblox scripts [S1]. The replacements are listed below.

| Old Technology | LightingStyle | PrioritizeLightingQuality | Look |
|---|---|---|---|
| Future | **Realistic** | true | Per-pixel local lights with shadows and specular, crisp sun shadows [S4][S6] |
| ShadowMap | Soft | true | **Our current setting** |
| Voxel | Soft | false | Flat and blocky |
| (new) | Realistic | false | Future-style shading with a shorter shading distance [S4] |

- **Neither property can be set by script.** Roblox stated this when it shipped [S4], and the light-sources guide
  says the property is "modifiable only in the Properties window" [S5]. The API page lists no security on them,
  but treat them as manual settings.
- `PrioritizeLightingQuality = true` means that when quality has to drop, the engine keeps good shadows and shading
  up close and gives up view distance first [S1][S2]. Keep it on. The forest limits sightlines anyway, and the
  Atmosphere hides pop-in at distance.
- Devices that can't run the Future path fall back to ShadowMap, then Voxel. Per-pixel lighting distance shrinks at
  lower quality levels [S6].

### 2.2 Global properties (all scriptable unless noted)

| Property | What it does | Range / default | How we use it |
|---|---|---|---|
| `Brightness` | Strength of the sun (or moon) light [S1] | Ours: 2.8 | The main time-of-day curve. It also drives the moon at night. Dip it at the hand-off |
| `ExposureCompensation` | Exposure bias before the tonemapper: +1 doubles, -1 halves | -5..5, default 0 [S1] | Base exposure plus eye adaptation. Prefer it over `Brightness` to lift dark scenes, because Brightness also lifts shadows and goes murky [S29] |
| `Ambient` | Flat fill where the sky is blocked (indoors, caves, dense cover) | Default 0,0,0 [S1] | The cave and cabin floor. Keep it dim, never black |
| `OutdoorAmbient` | Flat fill where the sky is visible but the sun isn't. Clamped to at least `Ambient` per channel | Default 127,127,127 [S1] | Shadow fill colour: cool by day, blue at night. **Doesn't change with time, so animate it** |
| `EnvironmentDiffuseScale` | Diffuse light from the sky/environment map, "dynamic... according to the sky and time of day" | 0..1, default 0 [S1] | 1 by day. Lower flat ambient when you raise it [S1] |
| `EnvironmentSpecularScale` | Reflections of the environment. Metalness has no effect at 0 | 0..1, default 0 [S1][S9] | 1 by day, 0.7-1 at night |
| `ColorShift_Top` | Tint on surfaces facing the sun or moon. Altering Brightness strengthens or weakens it [S1] | Black = engine default | Warm key at golden hour, cool moonlight. Blend maths **[unverified]**, see section 10.4 |
| `ColorShift_Bottom` | Tint on surfaces facing away from the sun | - | Reported non-functional with ShadowMap/Future at high quality [S54]. Don't rely on it |
| `GlobalShadows` | Shadows on/off, plus the indoor/outdoor split (4-stud lighting voxels) [S1] | true | Keep true |
| `ShadowSoftness` | Shadow blur, 0 hard to 1 soft. **Realistic only** [S2] | Default 0.2 | 0.12-0.18 at noon, 0.3+ for dawn mist and moonlight |
| `ClockTime` / `TimeOfDay` | Sun and moon position | 0..24 | The client sets it every frame from `DayCycle` |
| `GeographicLatitude` | Sun path (and the moon, which is opposite) | Ours: 44 | Keep. It gives long morning and evening shadows |
| `GetSunDirection()` / `GetMoonDirection()` | Unit vectors, which keep pointing below the horizon after set | - | Use for god-ray beams and "facing the sun" checks |
| `GetMoonPhase()` | Always 0.75; the phase can't be changed [S1] | - | - |
| `ExtendLightRangeTo120` | Unused. Light `Range` is always clamped at **120 studs** [S1] | - | - |
| `FogColor`/`FogStart`/`FogEnd` | Legacy fog, hidden and ignored when an Atmosphere exists [S1] | - | Ignore |

### 2.3 Sun, moon and sky through the day

- The sun rises at 06:00 and sets at 18:00 whatever the latitude. That is what `Shared.DayCycle`'s header says,
  and it matches the TerrainGen notes. The moon sits opposite the sun [S45].
- **Only one directional light is active at a time.** The engine hands off from the sun to the moon well after
  sunset; one report times it at 19:13:40 at latitude 41.7. It hands back from the moon to the sun before sunrise,
  reported near 04:43. At the switch, brightness and shadow direction snap [S45]. **[unverified for latitude 44]:
  measure it in our place** (section 12).
- The sky's IBL (`EnvironmentDiffuseScale`) darkens on its own as night falls [S1]. Flat `Ambient` and
  `OutdoorAmbient` don't, so the day/night look must animate them. DayCycle already does.
- Underwater lighting follows the light above the water and dims at night. "Ambient" limits how dark it gets [S44].
- Roblox heavily dims custom skyboxes at night, according to community reports [S55] **[unverified]**. Keep one day
  sky and check the night look. If it fails, swap the `Sky` faces at the hand-off (preload them with
  `ContentProvider`).

### 2.4 Local lights (PointLight, SpotLight, SurfaceLight)

- Properties: `Brightness`, `Color`, `Range` (at most 120), `Shadows`, `Enabled`, plus `Angle` and `Face` for spot
  and surface lights [S5]. Parent point lights to an **Attachment** [S5].
- Realistic/Future lights each light pixels individually and cast real shadows. "The number of per-pixel lights as
  well as number of shadowed lights is limited in each particular frame" [S6].
- **Shadow cost, from cheapest to dearest:** narrow spot (under about 120°), then surface, then point. Wide spot or
  surface angles cost about as much as a point light. "Shadowed lights are significantly much more expensive" [S6].
  Point lights are also the costliest unshadowed option on low-end devices [S29].
- Community experience: keep about 5-8 shadowed lights active and switch `Shadows` off beyond a distance [S56]
  (anecdotal). Roblox throttles light updates when many lights cluster [S6].
- Neon parts and emissive maps glow (with Bloom) but **light nothing**. Add a real light where illumination is
  needed.
- Turn on Studio Settings > **Show Light Guides** while placing lights [S5].

### 2.5 Ambient occlusion and reflections (limits)

- AO: there's no developer control. Community reports say engine SSAO appears only at the highest graphics level
  [S60] **[unverified]**. Bake **micro-occlusion only** into albedo (section 11), and let the light grid's
  indoor/outdoor split do the large-scale darkening.
- The Realistic engine decides what is "indoors" from geometry. Wrap interiors in solid parts at least 1 stud thick
  (Roblox's sample used 2.5) to stop light leaks [S29]. Cave walls built from terrain voxels (4 studs) are fine.
- Reflections: outdoor surfaces reflect the **skybox**. Enclosed spaces get automatic indoor environment maps with
  no developer control. The only way to turn them off is `EnvironmentSpecularScale = 0`, which turns off all
  reflections [S48]. No screen-space reflections. Terrain water reflects "the sky and surrounding objects" [S16].

---

## 3. Materials

### 3.1 SurfaceAppearance (one per MeshPart)

| Map / property | Format | Notes |
|---|---|---|
| `ColorMap` (albedo) | sRGB RGB(A), 24/32-bit | No baked lighting. The alpha channel's meaning depends on `AlphaMode` [S8][S10] |
| `NormalMap` | RGB, **OpenGL (+Y), tangent space** | `(127,127,255)` = flat. Bytes 0..255 map to -1..1.016. Invert G if the map is DirectX. **The mesh must carry tangents** [S9] |
| `RoughnessMap` | 8-bit grayscale | 0 smooth, 1 rough. Add about **+0.1** over what looks right in your DCC tool, because of Roblox's Fresnel [S8] |
| `MetalnessMap` | 8-bit grayscale | Mostly 0 or 1. **No effect if `EnvironmentSpecularScale` is 0** [S9] |
| `EmissiveMaskContent` + `EmissiveStrength` + `EmissiveTint` | 8-bit grayscale mask | The glow multiplies albedo and clamps if driven too hard. Strength and tint **can be scripted** [S9] |
| `Color` | Color3 tint | A multiply on `ColorMap`. Free, and **scriptable**. Author near-white maps if you want to tint them [S8] |
| `ResampleMode` | Default / Pixelated | Leave on Default |

- **AlphaMode** [S8][S40]:
  - `Overlay` is the default. Transparent texels show `MeshPart.Color` through.
  - `Transparency`: at `MeshPart.Transparency = 0` it is a **cut-out with depth**. That suits foliage. It works with
    DOF, water reflection and refraction, and has no sorting problems.
  - `Transparency` at `MeshPart.Transparency >= 0.02` blends smooth gradients. It doesn't work with every effect,
    and occlusion is imperfect.
  - `TintMask`: alpha controls where `Color` tints. Keep colour in the transparent texels and don't premultiply.
  - `Opaque`: ignores alpha. It is in beta under File > Beta Features > "MaterialVariant Alpha Mode".
- Most map properties can't be changed at runtime; only Color, Emissive strength and tint, and AlphaMode can [S8][S9].
- The engine packs the maps into one "texture pack" when you publish [S9].
- Undocumented: the current build exposes a `SurfaceAppearance.SurfaceSlot` property (seen through
  ReflectionService [S58]). It has no docs, so don't use it. One material per mesh remains the rule [S10].

### 3.2 Texture size, streaming, colour space

- **Texture streaming is automatic** (December 2025). It loads mips by camera importance and the device's memory
  budget [S35]. It covers MeshPart, SurfaceAppearance, Texture, Decal and MaterialVariant. The March 2026 update marks
  Beam and ParticleEmitter as supported, though the post contradicts itself on ParticleEmitter. **Terrain,
  TerrainDetail, Sky, UI and SurfaceGui are not covered yet** [S35].
- **4K textures work in live games** (January 2026). Uploads up to 8K are stored and transcoded down to 4K. The
  engine only uses more than 1K when an object fills enough of the screen and the device can afford it [S36].
  Android devices under 3.5 GB get no 4K [S35].
- Streaming works best with **individual, unique textures** and with near-uniform texel density. An atlas streams
  at the mip its most-demanding user needs, so use atlases only for textures that are seen together and batch
  together [S35]. Our foliage atlases qualify: one atlas is shared by every conifer.
- Memory scales with pixel count, not file size. Removing alpha or compressing before upload doesn't help
  [S7]. Roblox's built-in texel densities: **parts 1024 px per 8 studs (128 px/stud), terrain 512 px per 8 studs
  (64 px/stud)** [S10].
- A practical map-size pattern from Duvall Drive: **normal 1024, colour 512, roughness 256, no metalness** [S33].
  Drop the metalness map for anything non-metal, which gives black (non-metal) for free.
- Import pitfall: meshes imported with an embedded base texture create duplicate `TextureID` uploads. Clear
  `TextureID` when you apply a shared SurfaceAppearance [S33].

### 3.3 MaterialVariant, MaterialService and terrain

- `MaterialVariant` (tiling PBR material): `BaseMaterial`, `ColorMap`/`NormalMap`/`RoughnessMap`/`MetalnessMap`,
  `StudsPerTile`, `MaterialPattern` (`Regular` for man-made, `Organic` for less visible repetition [S41]),
  `AlphaMode`, `EmissiveStrength`/`EmissiveTint`, `CustomPhysicalProperties` [S12]. It **only works as a descendant
  of MaterialService** [S12].
- Per part: set `BasePart.MaterialVariant` to the variant's **name**; Studio sets `Material` to the base material.
  The link is by name, so renaming a variant breaks the parts that use it. That same name-matching lets you swap
  whole material packs ("adaptive materials") [S14]. On MeshParts, the mesh UVs should drive tiling; our
  `ls_common.box_uv` (8 studs/tile) assumes so **[unverified]**.
- Global overrides: the `MaterialService.<Material>Name` properties, such as `GrassName`, can't be set by script.
  Use `MaterialService:SetBaseMaterialOverride(Enum.Material.Grass, "GrassForest_MV")` [S13]. An override applies to
  **parts and terrain** [S14].
- `TerrainDetail` children customise the **top / side / bottom** faces of terrain using a variant: grass on top,
  soil or roots on the sides [S14].
- **Expanded Terrain** (`Workspace.ExpandedTerrain`, set per place): up to **62 paintable terrain materials**, each
  with its own colour and an optional MaterialVariant, plus smaller files and faster terrain streaming [S15]. It
  swaps the terrain backend and needs a place restart. In Team Create, exit and wait about 15 s before reopening.
  Variant `CustomPhysicalProperties` aren't respected in custom terrain slots yet [S15].
- Terrain `MaterialColors` tint the terrain textures. **[unverified]** whether they multiply a variant's ColorMap.
  Start the matching material colour at a neutral light value and tint down from there (section 11).
- Terrain grass decoration (`Terrain.Decoration`, `GrassLength` 0.1-1) renders **only on `Grass`** [S16].
- Legacy (pre-2022) terrain materials plus MaterialVariants carry a performance penalty [S13]. We use the 2022 pack.

### 3.4 MeshPart rendering

- `RenderFidelity`: `Automatic` gives full detail under 250 studs, medium at 250-500 and lowest beyond 500 [S26].
  `Precise` everywhere costs triangles [S7]. Use Precise only on far tree crowns if they break up.
- `DoubleSided` renders both faces [S27]. We use real flipped back faces instead, so lighting is correct on both
  sides and nothing z-fights. Keep `DoubleSided = false` on those cards.
- **Instancing:** copies batch into one draw call when they share the MeshContent **and** an identical
  SurfaceAppearance. Upload each mesh and image once, then clone [S7].
- `Workspace.MeshStreamingAndImprovedLods` (RolloutState) streams low LODs first [S37]. There are live-game reports
  of meshes stuck at low LOD **[unverified]**. Leave it on Default.
- `Model.LevelOfDetail = SLIM` gives lightweight distant stand-ins. It needs streaming and a cloud-saved place
  [S7][S38]. Useful only beyond our 1024-stud streaming radius, for example the lobby island.

### 3.5 Foliage cards (best practice)

1. Use `AlphaMode = Transparency` with `MeshPart.Transparency = 0` for hard-edged cut-outs: depth-correct and
   unsorted [S8]. At low quality levels this renders as a screen-door dither [S46]. That is acceptable.
2. Bleed colour into the transparent texels to prevent mip halos. tex_trees and gr_atlas already push-pull fill.
3. Thicken very thin needles and blades in the alpha (about 1.5x). Our pipeline doesn't control mip generation, so
   thin cut-outs erode with distance. This is general practice, not a Roblox doc.
4. Avoid stacking semi-transparent layers. Overdraw is a named Roblox performance problem [S7][S31].
5. Roblox has no translucency or back-light on leaves [S47]. Bend card normals outward from the crown centre, keep
   inner-crown albedo slightly lighter, and lean on `OutdoorAmbient` plus `EnvironmentDiffuseScale`.
6. Check whether card shadows come out dappled (cut-out) or as solid card shapes **[unverified]**. trees_real's own
   import notes already ask for this. If they are solid, set `CastShadow = false` on that foliage part.

### 3.6 PBR Decals and Textures (new detail layer)

`Decal` and `Texture` now carry `NormalMapContent`, `RoughnessMapContent`, `MetalnessMapContent` and
`EmissiveMaskContent`/`EmissiveStrength`/`EmissiveTint` [S39] (I also listed them through ReflectionService).
Setting any of these maps makes the decal a PBR surface [S39]. Uses: moss and lichen on rocks, mud splashes, soot
round fire pits, wet stains on banks. `Texture` tiles with `StudsPerTileU/V`. Decals, textures and particles don't
batch well [S7], so limit them to hero spots. Duvall Drive layered `Texture` objects over SurfaceAppearances for
wear and variation [S32].

---

## 4. Atmosphere, sky, clouds, fog, water

### 4.1 Atmosphere (`Lighting.Atmosphere`) [S18]

| Property | Effect | Note |
|---|---|---|
| `Density` | Amount of airborne particles; hides distant objects | Default 0.395. Our day value is 0.28-0.32 |
| `Offset` | Light transmission between camera and sky. High values give a horizon silhouette, low values blend into the sky | Low (0-0.12) for mist. 0.2-0.3 by day keeps the mountains |
| `Haze` | Haziness above the horizon and at distance | Needed for Glare and Decay to show |
| `Color` | Hue of the haze | Pick something close to the scene's average colour [S28] |
| `Glare` | Sun glow; needs Haze > 0 | Strong at sunrise and sunset, 0 at night |
| `Decay` | Hue away from the sun; needs Haze and Glare | Cool or violet at dusk |

The Atmosphere also applies to distant world geometry. **Test the night "Fallen" display at its real distance**, so
that night haze doesn't wash it out.

### 4.2 Sky [S19][S20]

- Six faces: `SkyboxBk/Dn/Ft/Lf/Rt/Up`, or the matching `*Content` properties. `SkyboxOrientation` is cheap; it
  rotates only the faces, not the sun or moon.
- `SunAngularSize` defaults to 21 (clamped 0-60); `MoonAngularSize` to 11; `StarCount` to 3000.
  `CelestialBodiesShown` hides the sun, moon and stars. `SunTextureId`/`MoonTextureId` take custom sprites.
- Skybox content: keep the lower hemisphere darker than the upper and close to the terrain colour. Leave clouds out
  of the painting and use dynamic Clouds instead [S28]. The sky also drives IBL and reflections [S34].
- The Sky isn't streamed [S35]. Six faces at 1024 each is a sensible budget; 2048 is the ceiling **[our proposal]**.

### 4.3 Clouds (`Terrain.Clouds`) [S21]

`Cover` (0-1 sky fraction), `Density` (low = wispy, high = heavy and stormy), `Color`, `Enabled`. Clouds render only
when parented under Terrain, and they drift with `GlobalWind`. Lighting and Atmosphere colour them too.

### 4.4 Water (terrain, global) [S16][S17][S44]

| Property | Range / default | Effect |
|---|---|---|
| `WaterColor` | default (12,84,92) | Hue. Also tints the underwater fog |
| `WaterTransparency` | 0 opaque .. 1 clear, default 0.3 | Clarity. Also sets underwater visibility distance |
| `WaterReflectance` | 0..1, default 1 | Opacity of the sky and object reflections |
| `WaterWaveSize` | 0..1 studs | Wave height |
| `WaterWaveSpeed` | 0..100 | Wave speed |

Some water properties only show in play-test or at the highest Editor Quality Level [S16]. One global look covers
the lake, river, marsh and waterfall pool. Get variety from the bed material (sand or gravel shallows, mud in the
marsh), floating meshes such as reeds and duckweed cards, and mist particles.

---

## 5. Post-processing and grading

| Effect | Key properties | Our use |
|---|---|---|
| `BloomEffect` | `Intensity`, `Size`, `Threshold` | Threshold 1.6-1.9 by day (sun, neon, fire only). 1.25-1.4 at night so embers and the night display glow |
| `SunRaysEffect` | `Intensity`, `Spread` | Shaped by objects between the camera and the sun [S23]. 0.03-0.05 at noon, 0.1-0.15 at dawn and golden hour, 0 at night |
| `DepthOfFieldEffect` | `FarIntensity`, `FocusDistance`, `InFocusRadius`, `NearIntensity` | **Keep NearIntensity at 0** (first-person viewmodel). Use subtle far blur. Lower it at night so the sky display stays sharp |
| `ColorCorrectionEffect` | `Brightness`, `Contrast`, `Saturation`, `TintColor` | White balance (Tint), contrast, saturation. Several instances stack: the game already layers `BorderTint` over `ArenaGrade` |
| `BlurEffect` | `Size` | Menus and underwater only. It blurs the whole screen |
| `ColorGradingEffect` | `TonemapperPreset` Default / Retro | Keep Default. Retro means flat, pre-2019 colour. Only one instance counts, and it must be in Lighting [S24][S42] |

- **No LUT.** Build a "grade" from layers instead:
  - **White balance:** `ColorCorrection.TintColor`.
  - **Key/fill split-tone:** `ColorShift_Top` for the warm key, `OutdoorAmbient` and `Ambient` hue for cool shadows.
  - **Distance grade:** `Atmosphere.Color`/`Decay`.
  - **Mood grade:** zone ColorCorrections (cave, underwater, canopy), blended in and out.
  - **Optional vignette or grain:** a full-screen ScreenGui `ImageLabel`, cheap and UI only.
- **Eye adaptation:** none built in. Script `ExposureCompensation` (section 10.3). Community approaches use either
  raycasts or screen capture; the screen-space versions have proved fragile [S51].
- Some post effects only appear at higher Studio quality levels. Set **Editor Quality Level** to the highest while
  doing look-dev [S23].

---

## 6. Tricks (how to fake what a shader would do)

| Goal | Technique | Cost / caveat |
|---|---|---|
| Volumetric mist (dawn, lake, marsh) | Low, slow `ParticleEmitter` sheets: big soft texture, Size 24-48, Transparency 0.85 to 1, Lifetime 18-30 s, Rate 0.5-2, `LightInfluence 1`, `LightEmission 0`, `Drag 0.5`, `WindAffectsDrag = true`. Plus Atmosphere Density 0.45-0.5 with Offset near 0 | Overdraw. Never tween emitter properties every frame [S7]. DayCycle's `Mist` 0..1 already gates emitters |
| God rays through the canopy | `SunRaysEffect`, plus hand-placed **Beams** (soft vertical gradient, Width0 6-10, Width1 12-20, `LightEmission 0.3-0.6`, `LightInfluence 0-0.3`, Transparency 0.88-0.95, `FaceCamera false`) aimed along `GetSunDirection()`. Enable them only when the sun is 5-35° up and Mist is above 0.2 | Duvall Drive used Beams for "volumetric lighting" [S32] |
| Foliage wind | 1) `GlobalWind` with scripted gusts (grass, clouds, particles) [S22]. 2) **CFrame sway of small undergrowth** within about 60 studs, `CastShadow = false` (the WindShake approach; its author reports 77,750 leaves at over 400 FPS on their machine [S49]). 3) **Skinned trees + Bones** for a few hero trees, as Duvall Drive did with one shared animation [S32] or with Canopy Flow (paid, about 0.43 ms for 225 trees in its author's test [S50]) | Moving parts force shadow recalculation [S1]. Skinned meshes aren't instanced, which costs memory [S32]. Don't sway big canopies that cast shadows |
| Leaves, pollen, dust | ParticleEmitters with `WindAffectsDrag`, small sizes, low rates, near the camera | One draw call each |
| Detail (moss, cracks, mud splash) | PBR Decals and Textures (section 3.6); Texture overlays on SurfaceAppearances [S32] | Don't batch well |
| Wet surfaces | **Wet MaterialVariants** (Duvall Drive's wet and dry variant pairs [S33]): albedo × 0.6-0.75, roughness 0.25-0.45, normal strength × 0.7. Paint them on banks, the waterfall spray zone and the marsh. Shallow terrain-water puddles. With Expanded Terrain you get dry/wet shades as separate paintable materials [S15] | Free at runtime (it's just materials) |
| Fire and embers | Flipbook flame particles (`LightEmission 1`, `LightInfluence 0`), ember particles (small, `Drag`, wind), smoke (`LightInfluence 1`). Coals via `EmissiveMaskContent` + scripted `EmissiveStrength` pulse. A PointLight on an Attachment, Range 24-36, Brightness 1.5-2.5, Color (255,150,80), with a client-side noise flicker (±10-15 % brightness, ±5 % range) | Shadows only on the nearest 2-4 fires (section 7.3) |
| Moonlit night that stays playable | Cool `OutdoorAmbient` (about 44,52,76), a blue `ColorShift_Top`, `ExposureCompensation` +0.4-0.5, Saturation -0.25 to -0.3 (a scotopic look), bloom on fires, stars at 4000-4500, Atmosphere as a sky-gradient silhouette | Don't drop `Brightness` to 0. That turns off moonlight and moon shadows [S45] |
| Cave darkness and the mouth glow | Wall thickness of 4 studs or more (the light grid), dim `Ambient`, eye adaptation, Bloom threshold about 1.3 so the mouth glows | Section 9 |
| Underwater | Built-in fog from `WaterColor` and `WaterTransparency`, plus a camera-local grade, blur and DOF while submerged (section 9) | Detect with `Terrain:ReadVoxels` at the camera cell [S59] |

---

## 7. Performance and device scaling

### 7.1 Cost of each feature

| Feature | Relative cost | Scaling and notes |
|---|---|---|
| Realistic lighting | Medium-high GPU | Falls back to ShadowMap or Voxel. Per-pixel distance shrinks with quality level [S6] |
| Sun shadows | Medium | Shadow quality degrades as quality drops; **off below level 4** [S7]. Cost grows with shadow casters, and moving parts force re-renders [S1] |
| Shadowed local lights | High each | Capped per frame. Point > surface > narrow spot [S6] |
| Unshadowed local lights | Low-medium | Point lights cost the most on low-end devices [S29] |
| Env diffuse / specular (IBL) | Low | Automatic indoor environment maps; one old report of FPS drops [S48] |
| Atmosphere, ColorCorrection | Low | - |
| Clouds | Low-medium **[unverified]** | - |
| Bloom, SunRays, DOF, Blur | Medium | "Some post effects may be completely disabled" at low quality levels [S25] |
| Transparent surfaces (blended) | High when layered | Overdraw [S7][S31] |
| Cut-out foliage (Transparency 0) | Medium | Depth-correct; dithered at low quality [S8][S46] |
| ParticleEmitters, Beams, Decals | Medium each | Draw calls. Changing emitter properties is costly [S7] |
| Skinned meshes | High memory | Not instanced [S32]. FastCluster rebuilds when they move without a Humanoid [S7] |
| Textures | Memory | Streamed automatically except Terrain, TerrainDetail and Sky [S35] |
| Glass | Medium | No refraction on mobile [S14] |

### 7.2 Quality level and mobile

- Quality levels raise render distance, shading quality, geometry and texture resolution, particle limits and post
  effects. The exact effects are "platform- and device-specific and can not be relied upon" [S25].
- Shadows are fully off below level 4 [S7]. Light the scene so it reads with shadows off: albedo contrast,
  `OutdoorAmbient`, Atmosphere, local lights.
- `UserSettings():GetService("UserGameSettings").SavedQualityLevel` is readable from LocalScripts. It returns
  `Automatic` when the player hasn't set a level [S43].
  - At low levels, drop the optional extras: sway, extra mist emitters, god-ray beams, DOF.
  - Add a `DayCycle.Knobs` entry such as `LowQualityAmbientLift` to raise `OutdoorAmbient` a little when shadows are
    off.
- Accessibility: "Reduce Motion" slows grass animation [S22].
- Android devices under 3.5 GB get streaming but no 4K [S35].
- Test in the Studio Device Emulator **and** on one real mid-range phone.

### 7.3 Budgets (our starting proposals; tune them with MicroProfiler and Render Stats)

Watch these MicroProfiler scopes: `Perform/Scene/computeLightingPerform`, `ShadowMapSystem`, `LightGridCPU`,
`RenderView` [S7]. Shift+F2 opens Render Stats (draw calls) [S7]. The Developer Console shows memory.

| Item | Budget **[proposal]** |
|---|---|
| Frame time | 16.7 ms on a mid PC, 33 ms on a mid phone |
| Shadowed local lights visible at once | ≤ 4-6. Prefer narrow SpotLights. A client script turns `Shadows` off beyond 80 studs |
| Unshadowed local lights visible | ≤ 30-40. Range ≤ 40 for props (120 is the engine maximum) |
| Shadow casters | `CastShadow = false` on props under about 3 studs, pebbles, ferns, grass clumps, mushrooms, items, the viewmodel. Today 5,074 of 6,981 parts cast shadows |
| Moving shadow casters | None of the big canopies. Sway only small, non-casting undergrowth |
| Draw calls (visible) | ≤ 2,000 PC / ≤ 800 mobile. Reach it through instancing: one upload, many clones |
| Blended transparency layers on screen | ≤ 2-3 deep. The ForceField border is client-local; render it only near the player |
| ParticleEmitters active near the camera | ≤ 25-30. Mist emitters ≤ 200 live particles each |
| PBR texture sets | 1024 by default, 2048 for hero items (Spire, plaza, cabin), 512 or smaller for small props. Use 4K only where the camera gets close |
| Terrain MaterialVariants | ≤ 12, 1024 each (not streamed [S35]) |
| Skybox | 6 × 1024 (not streamed) |
| Skinned "hero" trees | ≤ 10 near the Spire, if used at all |

The sun moves quickly in this game: day 1 runs at about 2 in-game hours per minute. Moving the sun means shadow
maps re-render. If `ShadowMapSystem` costs too much on mobile, step the client's `ClockTime` updates every 0.5-1 s
at low quality levels **[proposal]**.

---

## 8. Audit of the current place (read-only, 2026-11-10)

Read from the Edit DataModel (Play-mode values matched except ClockTime) with `execute_luau` and ReflectionService.

| Item | Current value | Assessment for realism |
|---|---|---|
| `LightingStyle` / `PrioritizeLightingQuality` | **Soft** / true (the old ShadowMap) | Flat look, `ShadowSoftness` ignored, weak local lights. Switch to **Realistic** (section 12) |
| `Brightness` / `ExposureCompensation` | 2.8 / 0.1 | Good noon values. DayCycle animates them |
| `Ambient` / `OutdoorAmbient` | (70,72,82) / (108,112,126) | Too much flat fill. Caves and cabins won't go dark, and shadows look milky. See section 9 |
| `EnvironmentDiffuseScale` / `EnvironmentSpecularScale` | 0.6 / 0.9 | Raise to 1 / 1 once on Realistic with a custom sky |
| `ShadowSoftness` | 0.28 | Ignored until Realistic; then 0.15 at noon |
| `ColorShift_Top` / `ColorShift_Bottom` | (0,0,0) / (0,0,0) at edit time. DayCycle sets Top = (255,246,230) at noon | Neutral at edit time. The runtime near-white Top needs an A/B check (section 10.4) |
| `GeographicLatitude` / `ClockTime` | 44 / 14.5 (lobby) | Good |
| `Sky` | **Default Roblox 2020 skybox** (Bk/Ft/Lf/Rt `6444884337`, Dn `6444884785`, Up `6412503613`), Sun 12°, Moon 13°, Stars 3000 (DayCycle uses 4500) | Generic sky: it drives the IBL and the Atmosphere colours. Replace it |
| `Atmosphere` | Density 0.31, Offset 0.3, Color (198,207,218), Decay (104,118,138), Glare 0.35, Haze 1.1 | A good hazy-day baseline. DayCycle animates it |
| `Terrain.Clouds` | Cover 0.55, **Density 0.62**, Color (244,244,248) | Density 0.62 reads heavy for a fair day; 0.35-0.45 is better. Not animated, and **static because there is no wind** |
| `Workspace.GlobalWind` | **(0,0,0)** | Grass, clouds and particles don't move. Set (6,0,2.5) plus gusts |
| `BloomEffect` "Bloom" | 0.6 / 26 / 1.85 | Fine. Run slightly lower by day |
| `SunRaysEffect` "SunRays" | 0.06 / 0.72 | A little strong at noon. DayCycle ramps it to 0.22-0.24 at sunrise and sunset; check for wash-out near the sun |
| `DepthOfFieldEffect` | Far 0.07, Focus 200, Radius 420, Near 0 | Good (Near 0 protects the viewmodel). Lower Far at night |
| `ColorCorrectionEffect` "ArenaGrade" | B 0.01, C 0.10, S **+0.04**, Tint (255,249,240) | Positive saturation works against the "slightly desaturated" art direction. Use -0.03 to -0.05 by day. Contrast 0.06-0.08 once on Realistic |
| `ColorGradingEffect` | none (Default tonemapper) | Fine |
| Terrain water | Color (36,92,100), Transparency 0.68, Reflectance 0.6, WaveSize 0.1, WaveSpeed 8 | Plausible clear mountain water. A slightly darker, greener colour (32,74,72) reads deeper. Add an underwater layer |
| Terrain colours | Grass (98,122,62), LeafyGrass (86,112,56), Ground (120,103,80), Mud (86,74,58), Rock (112,110,104), Slate (92,94,96), Basalt (68,68,70), Sand (194,180,145), Snow (232,238,243); Limestone, Salt and CrackedLava at defaults | Natural and desaturated, which is good. Re-tune after the MaterialVariants land. Limestone's default (255,243,192) would read cartoonish if it gets used |
| `MaterialService` | **Empty.** No variants, no overrides (`GetBaseMaterialOverride` returns the base names) | The terrain PBR variants aren't in the place yet |
| `ExpandedTerrain`, `MeshStreamingAndImprovedLods`, `RenderingCacheOptimizations`, `ParticlesUseDynamicWind` | Not readable by script | Check them in the Properties window |
| Scene contents | 6,981 BaseParts, **0 MeshParts, 0 SurfaceAppearances** (the new art isn't placed yet), 87 Neon, 500 Plastic/SmoothPlastic, 40 Glass, 62 PointLights (**8 shadowed**, max Range 50), 66 ParticleEmitters, a `WaterfallMist` attachment on Terrain | Set the light and shadow budget when the art lands (section 7.3) |
| Streaming | Enabled, Target 1024, Min 128 | The whole arena streams in. SLIM isn't needed inside the arena |

The day/night code was mid-rewrite when I read it. `Shared.DayCycle` holds the keyframes (`Looks`), global
multipliers (`Knobs`), `applyLook()` with an epsilon cache, and the two-day `Config.Round.DaySchedule`. The schedule
runs 7.4, then dusk 1 (Roll Call at 18.55), a 2.5-minute night to 05:00, dawn 2, day 2 and dusk 2, ending at 21:00.
My earlier read of `ArenaController` showed the older "night grading" (Atmosphere and ArenaGrade only). DayCycle's
header says ArenaController will apply the whole look every frame.

---

## 9. Scene recipes (starting values for LightingStyle = Realistic)

These values assume a custom day skybox and `PrioritizeLightingQuality = true`. Keys use DayCycle's names, so the
day scenes can be pasted into `DayCycle.Looks`; the cave, underwater and plaza rows are client zone layers on top
of the time-of-day look. **These are our proposals.** Tune them in Studio against reference photos at Editor
Quality Level 21 and at in-game level 4. `ShiftTop` values assume black is neutral (section 10.4).

### 9.1 Lighting

| Scene (hour) | Brightness | Exposure | Ambient | Outdoor | ShiftTop | EnvDiffuse / EnvSpecular | Softness |
|---|---|---|---|---|---|---|---|
| Forest day (9.5-15.5; lobby 14.5) | 2.6 | 0.0 | (40,42,48) | (84,90,102) | (40,34,24) | 1.0 / 1.0 | 0.15 |
| Golden hour (17.0-18.0) | 2.2 down to 1.7 | 0.1 | (40,36,40) | (88,82,102) | (200,120,60) | 1.0 / 1.0 | 0.25 |
| Dusk hand-off window (18.9-19.4) | dip to **0.35** at the hand-off (±0.12 h) | 0.25 | (32,32,44) | (64,66,92) | (120,110,170) | 0.8 / 0.8 | 0.3 |
| Night with moon (19.5-4.4) | 1.4 (moon) | 0.45 | (20,24,34) | (44,52,76) | (70,95,150) | 0.8 / 0.8 | 0.35 |
| Dawn mist (day 2, 5.0-7.4; the round starts at 7.4) | 1.6 rising to 2.3 (dip at the dawn hand-off, about 4.7) | 0.15 | (40,40,48) | (86,90,108) | (180,120,80) | 1.0 / 0.9 | 0.35 |
| Cave interior (zone) | time-of-day value | **+0.7** target deep inside, +0.35 at the mouth (eye adaptation) | global: ≥ (36,36,42) by day, ≥ (18,20,28) at night | - | - | - | - |
| Underwater (zone) | time-of-day value | -0.1 | - | - | - | - | - |
| Spire plaza (zone, open sky) | time-of-day value | -0.05 (no canopy lift) | - | - | - | - | - |

### 9.2 Atmosphere, clouds and post-processing

| Scene | Atmosphere: Density / Offset / Color / Decay / Glare / Haze | Clouds: Cover / Density / Color | Bloom: Int / Size / Thr | SunRays: Int / Spread | Grade: Bright / Contrast / Sat / Tint | DOF: Far / Focus / Radius |
|---|---|---|---|---|---|---|
| Forest day | 0.28 / 0.25 / (200,210,222) / (110,124,144) / 0.3 / 1.2 | 0.5 / 0.4 / (252,252,255) | 0.4 / 26 / 1.8 | 0.04 / 0.45 | 0 / 0.06 / -0.04 / (255,250,244) | 0.05 / 150 / 450 |
| Golden hour | 0.34 / 0.12 / (236,188,148) / (120,96,120) / 0.9 / 2.0 | 0.55 / 0.45 / (255,240,228) | 0.5 / 30 / 1.5 | 0.10 / 0.6 | 0.01 / 0.10 / 0.04 / (255,236,214) | 0.05 / 150 / 450 |
| Dusk hand-off | 0.37 / 0.12 / (112,112,150) / (72,60,96) / 0.15 / 2.1 | 0.5 / 0.4 / (200,196,220) | 0.7 / 30 / 1.4 | 0 / - | 0 / 0.12 / -0.12 / (222,222,255) | 0.03 / 150 / 500 |
| Night with moon | 0.34 / 0.2 / (70,82,112) / (32,40,64) / 0 / 1.4 | 0.4 / 0.35 / (170,180,205) | 0.7 / 30 / 1.3 | 0 / - | 0 / 0.12 / -0.28 / (205,218,255) | **0.02** / 200 / 600 |
| Dawn mist | **0.48 / 0.03** / (214,206,204) / (150,140,156) / 0.9 / **2.6**; burns off to the day values by 9.0 | 0.65 / 0.3 / (255,246,240) | 0.5 / 40 / 1.45 | 0.12 / 0.75 | 0.01 / 0.05 / -0.06 / (255,244,236) | 0.10 / 120 / 300 |
| Cave interior | unchanged | - | Int +0.1, Thr 1.3 (the mouth glows) | occluded | 0 / +0.04 / -0.08 / (255,244,232) warm torch bias | - |
| Underwater | unchanged (water fog does the work) | - | unchanged | 0 | -0.03 / -0.05 / -0.25 / (150,205,200) on a Camera-local CC + `BlurEffect` Size 3-5 | **0.4 / 8 / 25** |
| Spire plaza (night) | night | night | 0.8 / 30 / 1.3 (the ember strips glow) | 0 | night | night |

### 9.3 Scene extras (water, wind, local lights)

- **Forest day.**
  - Water: Color (32,74,72), Transparency 0.65, Reflectance 0.6, WaveSize 0.08, WaveSpeed 6.
  - Wind: `GlobalWind` (6,0,2.5), gusting to (14,0,6).
  - Under canopy (cover ≥ 0.6): Exposure +0.25 and Saturation -0.03.
- **Golden hour.** Water Reflectance 0.7. Wind calms to (4,0,2). Long trunk shadows give the sun rays something to
  cut through.
- **Dusk hand-off.** Hold the dip through the hand-off; Roll Call 1 starts at 18.55 and runs through it. The
  "Fallen" display uses `LightInfluence 0` or emissive parts, so it is unaffected.
- **Night with moon.**
  - Stars 4500, Moon 11°. Water Reflectance 0.8.
  - Fires: the nearest 2-4 cast shadows.
  - Beacon: PointLight Range 80, Brightness 2.5, Color (255,150,80), Shadows on.
- **Dawn mist.** `Mist = 1` over the lake, marsh and meadow hollows. Wind (2,0,1) so the mist lingers. Turn on the
  god-ray beams.
- **Cave interior.**
  - Torch or camp light: PointLight Range 24, Brightness 1.8, Color (255,160,96), Shadows on (nearest only),
    flicker.
  - Dust motes in the light shaft. Walls ≥ 4 studs thick.
- **Underwater.**
  - While submerged, set `Terrain.WaterTransparency` locally from 0.68 to 0.35 and restore it on exit.
  - Bubbles at the camera, muffled audio, hysteresis of ±0.3 studs at the surface.
- **Spire plaza.**
  - Granite roughness 0.75-0.85, cobble 0.8-0.9.
  - Ember strips: `EmissiveStrength` 1-2 by day, 4-6 at night (or Neon with a darker orange by day).
  - Lighting: the Beacon plus one downward SpotLight (Angle 150, Range 60, Brightness 1, unshadowed) to wash the
    plaza. **No light per plinth.**
  - The 7.4 Countdown is the hero shot: low ESE sun, mist, SunRays 0.14 for the 10 s countdown.

Reference values from Roblox's own realistic samples, used as sanity checks:

- Outdoor campfire at 17:00 [S28]:
  - Ambient/Outdoor (156,136,176), EnvDiffuse/Specular 1.
  - Atmosphere Density 0.272, Haze 1, Color (85,78,54).
  - Fire PointLight Range 48, Brightness 2, Color (255,179,73), Shadows on.
- Indoor cabin [S29]:
  - ClockTime 15.6, Ambient (83,70,57), Exposure 0.5.
  - SunRays 0.023 / 0.266, Atmosphere Density 0.5.
  - Candle PointLight 0.7 (255,202,156) with shadows; lamp SpotLight Angle 140, Brightness 4, Range 12.
  - Colour correction: Contrast 0.05, Saturation 0.1.
- Island Jump [S30]:
  - Ambient (16,16,16), Outdoor (134,158,190), ColorShift_Top (196,222,255).
  - ShadowSoftness 0, ClockTime 9, Latitude 78.
  - Atmosphere Density 0.375, Offset 0.17.
- Community: the "Wooded Creek" showcase ran Brightness 6. Its author called contrast between light and shadow
  "the key" [S53].

---

## 10. Time-of-day plan (extend `Shared.DayCycle`)

### 10.1 What DayCycle already does (keep it)

- The server publishes the clock time base: the GameState `Clock` string, which `encodeClock` writes and
  `evalClock` reads.
- Clients evaluate the clock every frame, set `Lighting.ClockTime`, interpolate `DayCycle.Looks` with smoothstep,
  and call `applyLook()`. The epsilon cache skips unchanged properties.
- It drives Lighting (Brightness, Exposure, Ambient, Outdoor, ShiftTop/Bottom, EnvDiffuse/Specular, Softness),
  Atmosphere, ArenaGrade, Bloom, SunRays, Sky.StarCount and the Mist weight.

### 10.2 What to add

1. **Re-tune `Looks` for Realistic** (section 9). Raise `EnvDiffuse`/`EnvSpecular` to about 1 by day and 0.8 at
   night. Lower MIDDAY `Ambient`/`Outdoor` to about (40,42,48)/(84,90,102). Set MIDDAY `GradeSaturation` to -0.04.
   Raise NIGHT `BloomThreshold` from 1.05 to about 1.3, so moonlit surfaces don't bloom. NIGHT `Brightness` is 2.4
   today; start at about 1.4 and add `Exposure` (0.45) instead.
2. **Hand-off dips.** Add `DayCycle.Knobs.HandoffDusk` and `HandoffDawn`, measured in Studio (section 12). Multiply
   `Brightness` by a dip near each one. At night 1's speed of about 4 h/min, a ±0.12 h window lasts about 3.6 s.
3. **New tracks in `Looks` and `applyLook`:**
   - `Clouds.Cover`/`Density`/`Color`
   - `DepthOfField.FarIntensity`
   - `Terrain.WaterReflectance`, and optionally `WaterColor`
   - a wind "base" vector, with gusts added on the client
4. **Layers after `lookAt()`,** in this order: time of day → hand-off dip → quality-level knobs → zone layer (cave,
   canopy, underwater, plaza; weights eased over 0.5 s) → eye adaptation (exposure offset) → gameplay grades
   (BorderTint, damage, the Roll Call show).
5. **One writer.** Only the DayCycle apply path writes these properties. Remove any other script that eases the same
   Atmosphere or ArenaGrade properties (the old ArenaController night grading), so they don't fight. The server
   never writes Lighting at runtime except the authored edit-time look.
6. **Lobby.** It uses the same table at `LobbyClockTime` 14.5. The edit-time builder ("LightingRig", mentioned in
   DayCycle but not in the place yet) should write `lookAt(14.5)` so Studio matches the game.

### 10.3 Sketch (client, inside ArenaController's per-frame update)

```lua
-- after: local look = DayCycle.lookAt(hour, lookCache)
local function dip(h: number, center: number, half: number, depth: number): number
	local d = math.abs(((h - center + 12) % 24) - 12) / half -- wrap-safe distance in hours
	return if d < 1 then 1 - depth * (1 - d * d) else 1
end
local K = DayCycle.Knobs
look.Brightness *= math.min(dip(hour, K.HandoffDusk or 19.22, 0.12, 0.85), dip(hour, K.HandoffDawn or 4.72, 0.12, 0.85))

-- zone weights (0..1, eased): tagged invisible "LookZone" parts (attribute Zone = "Cave" | "Plaza" | "Canopy"),
-- point-in-box tested at 10 Hz like Duvall Drive's indoor volumes [S32]; canopy cover also from a baked 16-stud
-- grid written by the Populate builder (foliage is CanQuery = false, so raycasts can't see canopies)
look.Exposure += zone.cave * 0.7 + zone.canopy * 0.25 - zone.plaza * 0.05 + zone.water * -0.1

-- eye adaptation: openness from 5 rays (up + 4 tilted 30 deg, 150 studs, terrain + opaque parts only)
local target = (1 - openness) * 0.5 -- extra lift when enclosed by rock or roofs
local tau = if target > adapt then 2.5 else 0.6 -- slow when it gets darker, fast when it gets brighter
adapt += (target - adapt) * (1 - math.exp(-dt / tau))
look.Exposure = math.clamp(look.Exposure + adapt, -0.5, 1.5)

DayCycle.applyLook(look, targets, applyCache)
```

- Run the raycasts and zone tests at 10 Hz. Do the blending every frame; it's cheap.
- Underwater test: `Terrain:ReadVoxels(Region3.new(p - v2, p + v2):ExpandToGrid(4), 4)` at the camera cell, where
  `v2 = Vector3.one * 2`. The camera is underwater when the cell is Water with occupancy above 0.5. Add hysteresis.
  The camera-local grade and blur live under `workspace.CurrentCamera`.
- Night display: fade it in after the dusk hand-off, or keep it emissive with `LightInfluence 0` throughout.
  Keep DOF far blur near 0 and Bloom threshold at about 1.3 while it shows.

### 10.4 Verify `ColorShift_Top` before final tuning

The engine default is black (neutral). The docs describe it as a hue on surfaces that face the sun, scaled by
Brightness [S1][S2]. DayCycle's MIDDAY uses (255,246,230). If the shift adds to the sun's light **[unverified]**,
that value roughly doubles the sun key and clips sunlit grass once IBL is at 1. Run an A/B test at 13:00 on
Realistic: Top (0,0,0) with Brightness 2.6, against (255,246,230) with Brightness 1.4. Keep whichever matches
reference photos, and scale every keyframe's ShiftTop consistently.

---

## 11. Material-authoring checklist (Blender → Roblox)

**Export and import**

- [ ] **Export tangents.** Set `export_tangents=True` in `gr_export.py:180`, `trees_real.py:1623` and
      `tex_items.py:927`, and in any future texture-set exporter [S9][S12]. The Blender bakes assume MikkTSpace,
      which the glTF exporter writes.
- [ ] Use one SurfaceAppearance per MeshPart, built from the manifest. Upload every PNG **once** and share the asset
      IDs, which gives both instancing and memory savings [S7]. Clear any importer-created `TextureID` [S33].
- [ ] Use **separate 8-bit grayscale** Roughness and Metalness PNGs [S10]. Don't rely on Roblox splitting glTF's
      packed metallicRoughness: trees_real's notes say it doesn't. The BuildingsReal `BR_*_MR.png` (R=G=roughness,
      B=metal) therefore needs separate grayscale exports for hand-built SurfaceAppearances.
- [ ] Check UVs with one tiled bark trunk. The spec says UVs should be inside 0..1 and allows a single UV set [S10];
      confirm that tiling outside 0..1 repeats on world meshes **[unverified]**.
- [ ] Keep texel density near-uniform within an asset [S35]. Targets: about 100-200 px/stud on hero and near
      first-person assets, 50-100 px/stud on cliffs and big structures. Roblox's own densities are 128 px/stud for
      parts and 64 for terrain [S10].

**ColorMap (albedo, sRGB)**

- [ ] No lighting, shadow or large-scale AO; micro-occlusion only [S34][S52]. Non-metals stay between 30-50 sRGB
      (darkest) and 240 sRGB (brightest) [S52].
- [ ] Typical natural targets **[guidance, sRGB]**:

  | Surface | sRGB value |
  |---|---|
  | Conifer needles | 35-75 |
  | Broadleaf (green channel) | 50-110 |
  | Grass (green channel) | 60-120 |
  | Bark | 50-110 |
  | Dead or silver wood | 110-165 |
  | Dry soil | 90-140 |
  | Wet mud | 45-75 |
  | Granite | 110-160 |
  | Limestone | 160-200 |
  | Sand | 150-200 |
  | Snow | 215-240 |
  | Charcoal | 35-50 |

  Keep forest greens moderately saturated to match "slightly desaturated" (section 3 of GameDesign).
- [ ] For tint workflows, author near-white maps, because `SurfaceAppearance.Color` multiplies them [S8]. With
      `TintMask`, keep colour in the transparent texels and don't premultiply [S8].
- [ ] Card atlases: bleed colour into transparent texels (already done), use hard alpha, and thicken thin features
      against mip erosion. Use RGBA only where alpha is used.

**NormalMap**

- [ ] OpenGL (+Y green up), tangent space, 8-bit RGB, flat = (127,127,255) [S9]. Invert G if a source is DirectX.
- [ ] Use moderate strength. Over-strong normals turn to noise under Realistic specular. Shade foliage cards with
      outward-bent ("dome") normals, because there is no translucency [S47].

**RoughnessMap**

- [ ] 0 = smooth, 1 = rough. Add about +0.1 against the Blender look [S8]. Half the colour map's resolution is
      usually enough [S33].
- [ ] Values (Roblox's reference table [S11] plus the extra lines marked **[guidance]**):

  | Material | Roughness | Metalness |
  |---|---|---|
  | Bark **[guidance]** | 0.8-0.95 | 0 |
  | Moss **[guidance]** | 0.85-0.95 | 0 |
  | Dry needles and leaves **[guidance]** | 0.6-0.8 | 0 |
  | Waxy leaves **[guidance]** | 0.45-0.6 | 0 |
  | Dry rock **[guidance]** | 0.75-0.9 | 0 |
  | Wet rock or mud **[guidance]** | 0.25-0.45 | 0 |
  | Worn wood | 0.7-0.9 | 0 |
  | Glossy wood | 0.2-0.3 | 0 |
  | Canvas, cotton | 0.8-0.9 | 0 |
  | Worn leather | 0.5-0.7 | 0 |
  | Rust (non-metal) **[guidance]** | 0.6-0.85 | 0 |
  | Blades | 0.2-0.4 | 1 |
  | Glass **[guidance]** | about 0.05 | 0 |

**MetalnessMap**

- [ ] Leave it empty for non-metals. Use 1 for raw metal (235-255 sRGB in the map) [S52]. Raw-metal albedo is
      180-255 sRGB [S52]. Partial values only where dirt or rust breaks up a metal.

**Emissive**

- [ ] A grayscale mask plus `EmissiveStrength`/`EmissiveTint`, for coals, lantern glass and the plinth strips.
      Script the strength by time of day. Stay modest, because the result clamps [S9]. Always pair it with a real
      light.

**Alpha and part flags**

- [ ] Foliage: `Transparency` AlphaMode with `MeshPart.Transparency = 0` and `DoubleSided = false`, using real back
      faces [S8].
- [ ] Glass and bottles: `Transparency` with Transparency ≥ 0.02 [S8].
- [ ] Opaque sets: no alpha channel.
- [ ] `CastShadow = false` on small and non-colliding detail, as the GroundReal manifest already does (11 of 16
      parts).

**Sizes**

- [ ] 1024 standard, 2048 for heroes, 512 or 256 for small props. 4K only for camera-close heroes [S36].
- [ ] Terrain variants: 1024, tileable, low-frequency. `StudsPerTile` gives about 64-100 px/stud: grass 10-12,
      forest floor 8-10, rock and cliff 16-32, cobble 8. Use `Organic` for natural materials [S41].

**Studio checks**

- [ ] Light a lit sphere or plane at 7.4, 13, 18 and 22 on Realistic.
- [ ] Bumps lit from the left must brighten on the left side; otherwise the G channel or the tangents are wrong.
- [ ] No halos on cards, dappled card shadows, and roughness that reads sensibly at grazing angles.

---

## 12. Manual Studio steps (the user must do these)

1. **Lighting → `LightingStyle` = Realistic** in the Properties panel. It can't be scripted. Keep
   `PrioritizeLightingQuality` checked. Update the GameDesign manual-steps line, which still says "Technology →
   Future".
2. Studio Settings → Rendering → **Editor Quality Level = highest** while doing look-dev. Water and post effects
   show fully only there [S16][S23]. Also turn on **Show Light Guides** [S5].
3. **Measure the light hand-offs.** In Edit mode, step `ClockTime` in 0.02 h increments over 19.0-19.4 and 4.5-4.9,
   and note when shadows flip and brightness jumps [S45]. Put the results in `DayCycle.Knobs.HandoffDusk` and
   `HandoffDawn`.
4. **A/B the ColorShift_Top meaning** at 13:00 (section 10.4).
5. **Upload the art.**
   - Upload the skybox faces and the PBR PNGs once each (Asset Manager bulk import, or Open Cloud), and record the
     IDs in the manifests.
   - Create the terrain MaterialVariants in the **Material Manager**. Set overrides, add TerrainDetail top and side
     faces, and set the matching `Terrain.MaterialColors`.
6. **Decide on Expanded Terrain** (`Workspace.ExpandedTerrain = Enabled`) for multiple grass shades and wet
   variants [S15].
   - Do it only when no agent is editing terrain.
   - The place restarts. In Team Create, exit and wait about 15 s before reopening.
   - Check thin terrain under streaming afterwards.
7. Check the non-scriptable Workspace flags in Properties: `ExpandedTerrain`, `MeshStreamingAndImprovedLods`
   (leave on Default), `ParticlesUseDynamicWind`.
8. **Device tests.** In the Device Emulator and on one real mid-range phone, try in-game graphics levels 1, 4, 7 and
   10 for each scene in section 9. Check that the night is readable and the frame time is within budget.
9. Optional beta: File → Beta Features → "MaterialVariant Alpha Mode", only if you need the `Opaque` alpha mode
   [S8].

---

## 13. Prioritized look-dev tasks (biggest realism gain first)

| # | Task | Why (gain) | Effort |
|---|---|---|---|
| 1 | **LightingStyle → Realistic** (manual), then a first rebalance of `DayCycle.Looks`: EnvDiffuse and EnvSpecular to 1, flat ambient down, the ShiftTop A/B, night bloom threshold and brightness | Per-pixel PBR shading, local-light shadows and specular, ShadowSoftness. The whole game changes at once | 1 click + 1 h tuning |
| 2 | **Make PBR work**: re-export the GLBs with tangents; separate grayscale roughness and metal maps; verify OpenGL normals on test spheres; one SurfaceAppearance per part with shared IDs | Without tangents, normal maps may do nothing, and then all the new art looks flat | 0.5 day (art pipeline) |
| 3 | **Custom day skybox** for the valley and mountains (darker, terrain-coloured lower hemisphere), plus a night check (swap the sky at the hand-off if the engine's dimming fails) | It sets the IBL fill, reflections, the Atmosphere colours and water reflections | 0.5-1 day |
| 4 | **Terrain PBR variants**: overrides plus TerrainDetail, Organic pattern, StudsPerTile, colour re-tune. Consider Expanded Terrain for shades and wet banks | Terrain covers most of every frame | 1-2 days |
| 5 | **Wind and life**: `GlobalWind` plus client gusts; sway on undergrowth near the camera; leaf, pollen and dust particles; cloud drift | Removes the "frozen diorama" look cheaply | 0.5 day |
| 6 | **Hand-off-safe time of day**: measured dips, Clouds, DOF, water and wind tracks, the Roll Call/Fallen display tuned for readability | Hides the engine's light pop during the Roll Call and gives a coherent day arc | 0.5-1 day |
| 7 | **Eye adaptation and zones** (cave, canopy, underwater, plaza) | Caves and dense forest read as real light levels | 1 day |
| 8 | **Atmospheric depth**: mist sheets, god-ray beams at dawn and golden hour, waterfall spray | Depth and mood at the hero moments (the 7.4 Countdown, dawn 2) | 0.5-1 day |
| 9 | **Fire and ember lighting**: flicker, ember and smoke particles, emissive coals, the Beacon, distance-based shadow toggling | Night readability, plus focal points | 0.5 day |
| 10 | **Budget pass**: CastShadow cleanup, light and shadow caps, transparency audit, QualityLevel scaling, phone test | Keeps the realism shippable on mobile | 1 day |
| 11 | **Detail pass**: PBR decals (moss, mud, soot, wet), rocks sunk and moss-capped into the terrain, wet shorelines | Close-up believability in first person | 1-2 days |
| 12 | Optional: a few skinned hero trees, SLIM for the lobby island and mountains, a `MeshStreamingAndImprovedLods` test, 4K textures on heroes | Polish | as time allows |

---

## 14. Open questions and unverified items

- The sun-to-moon (dusk) and moon-to-sun (dawn) hand-off times at latitude 44 in our place. Community reports put
  them near 19.2 and 4.7 [S45].
- How `ColorShift_Top` blends (additive or multiply), and whether `ColorShift_Bottom` works on Realistic [S54].
- Whether cut-out foliage casts cut-out (dappled) shadows on Realistic.
- Whether terrain `MaterialColors` multiply a MaterialVariant's ColorMap. Whether terrain variants are excluded from
  texture streaming (the Terrain and TerrainDetail rows say "not yet" [S35]).
- Whether local lights light SurfaceAppearance meshes on Soft. A 2020 report says only on Future [S57], which is
  another reason to switch.
- Whether custom skyboxes are dimmed or hidden at night [S55].
- At which quality levels engine AO appears [S60]. What dynamic Clouds cost.
- Whether UV tiling outside 0..1 repeats on SurfaceAppearance world meshes.
- The current `ExpandedTerrain` state of the place, which scripts can't read.
- All budgets in section 7.3 and the numbers in section 9 are proposals, to tune by profiling and by eye.

---

## 15. Sources

| Tag | Source |
|---|---|
| S1 | Lighting class: https://create.roblox.com/docs/reference/engine/classes/Lighting |
| S2 | Global lighting guide: https://create.roblox.com/docs/environment/lighting |
| S3 | LightingStyle enum: https://create.roblox.com/docs/reference/engine/enums/LightingStyle |
| S4 | Unified Lighting announcement (beta 2025-01-21, fully live 2025-07-23): https://devforum.roblox.com/t/let-there-be-unified-light-unified-lighting-enters-studio-beta/3401512 |
| S5 | Light sources: https://create.roblox.com/docs/effects/light-sources |
| S6 | Future Is Bright Phase 3 (2020-11-19): https://devforum.roblox.com/t/future-is-bright-phase-3-released/878634 |
| S7 | Performance, improve: https://create.roblox.com/docs/performance-optimization/improve |
| S8 | PBR textures: https://create.roblox.com/docs/art/modeling/surface-appearance |
| S9 | SurfaceAppearance class: https://create.roblox.com/docs/reference/engine/classes/SurfaceAppearance |
| S10 | Texture specifications: https://create.roblox.com/docs/art/modeling/texture-specifications |
| S11 | Material references: https://create.roblox.com/docs/art/modeling/material-reference |
| S12 | MaterialVariant class: https://create.roblox.com/docs/reference/engine/classes/MaterialVariant |
| S13 | MaterialService class: https://create.roblox.com/docs/reference/engine/classes/MaterialService |
| S14 | Materials guide: https://create.roblox.com/docs/parts/materials |
| S15 | Custom terrain materials / Expanded Terrain: https://create.roblox.com/docs/parts/custom-terrain-materials |
| S16 | Environmental terrain guide: https://create.roblox.com/docs/parts/terrain |
| S17 | Terrain class: https://create.roblox.com/docs/reference/engine/classes/Terrain |
| S18 | Atmospheric effects: https://create.roblox.com/docs/environment/atmosphere |
| S19 | Skyboxes: https://create.roblox.com/docs/environment/skybox |
| S20 | Sky class: https://create.roblox.com/docs/reference/engine/classes/Sky |
| S21 | Dynamic clouds: https://create.roblox.com/docs/environment/clouds |
| S22 | Global wind: https://create.roblox.com/docs/environment/global-wind |
| S23 | Post-processing effects: https://create.roblox.com/docs/environment/post-processing-effects |
| S24 | ColorGradingEffect: https://create.roblox.com/docs/reference/engine/classes/ColorGradingEffect |
| S25 | QualityLevel enum: https://create.roblox.com/docs/reference/engine/enums/QualityLevel |
| S26 | RenderFidelity enum: https://create.roblox.com/docs/reference/engine/enums/RenderFidelity |
| S27 | MeshPart class: https://create.roblox.com/docs/reference/engine/classes/MeshPart |
| S28 | Enhance outdoor environments: https://create.roblox.com/docs/tutorials/use-case-tutorials/lighting/enhance-outdoor-environments |
| S29 | Enhance indoor environments: https://create.roblox.com/docs/tutorials/use-case-tutorials/lighting/enhance-indoor-environments |
| S30 | Customize global lighting: https://create.roblox.com/docs/tutorials/curriculums/core/building/customize-global-lighting |
| S31 | Optimize your game (environment art): https://create.roblox.com/docs/tutorials/curriculums/environmental-art/optimize-your-experience |
| S32 | Duvall Drive, develop a moving world: https://create.roblox.com/docs/resources/the-mystery-of-duvall-drive/develop-a-moving-world |
| S33 | Duvall Drive, materialize the world: https://create.roblox.com/docs/resources/the-mystery-of-duvall-drive/materialize-the-world |
| S34 | Duvall Drive, construct the house (IBL, albedo): https://create.roblox.com/docs/resources/the-mystery-of-duvall-drive/construct-the-house |
| S35 | Introducing Texture Streaming (2025-12-12, updated 2026-03-23): https://devforum.roblox.com/t/introducing-texture-streaming/4144855 |
| S36 | 4k Texture Rendering (2026-01-30): https://devforum.roblox.com/t/4k-texture-rendering/4316229 |
| S37 | Workspace class: https://create.roblox.com/docs/reference/engine/classes/Workspace |
| S38 | SLIM: https://create.roblox.com/docs/workspace/streaming/slim |
| S39 | Decal class (PBR maps): https://create.roblox.com/docs/reference/engine/classes/Decal |
| S40 | AlphaMode enum: https://create.roblox.com/docs/reference/engine/enums/AlphaMode |
| S41 | MaterialPattern enum: https://create.roblox.com/docs/reference/engine/enums/MaterialPattern |
| S42 | TonemapperPreset enum: https://create.roblox.com/docs/reference/engine/enums/TonemapperPreset |
| S43 | UserGameSettings: https://create.roblox.com/docs/reference/engine/classes/UserGameSettings |
| S44 | Underwater lighting improvements (2020): https://devforum.roblox.com/t/upcoming-underwater-lighting-improvements/865915 |
| S45 | Sun/moon hand-off reports: https://devforum.roblox.com/t/setting-lightingtimeofday-to-1940-causes-sudden-brightness-difference/2535047 and https://devforum.roblox.com/t/global-light-source-switches-between-sun-and-moon-at-incorrect-times/2171117 |
| S46 | Screen-door alpha at low quality (staff reply): https://devforum.roblox.com/t/inconsistent-surfaceappearance-alpha-on-lower-graphics-settings/1326592 |
| S47 | No two-sided lighting on foliage (2025-03-23): https://devforum.roblox.com/t/how-can-i-enable-two-sided-lighting-on-foliage/3563747 |
| S48 | Better Indoor Reflections: https://devforum.roblox.com/t/better-indoor-reflections-live-for-future-lighting/1365721 |
| S49 | WindShake: https://devforum.roblox.com/t/wind-shake-high-performance-wind-effect-for-leaves-and-foliage/1039806 and https://github.com/boatbomber/WindShake |
| S50 | Canopy Flow (skinned foliage wind, 2026): https://devforum.roblox.com/t/canopy-flow-realistic-wind-for-skinned-foliage/4693945 |
| S51 | Auto-exposure approaches: https://devforum.roblox.com/t/performant-auto-exposure-screen-space/3000200 and https://devforum.roblox.com/t/discontinued-active-lighting-adjustment-let-your-eyes-adjust-to-the-light-it-receives/612087 |
| S52 | Adobe Substance, The PBR Guide part 2: https://www.adobe.com/learn/substance-3d-designer/web/the-pbr-guide-part-2 |
| S53 | Wooded Creek realistic lighting (2019): https://devforum.roblox.com/t/wooded-creek-realistic-lighting/413948 |
| S54 | ColorShift_Bottom non-functional report: https://devforum.roblox.com/t/lightingcolorshiftbottom-non-functional-on-high-graphics-level-shadowmap-and-future/2340429 |
| S55 | Custom night skybox dimming: https://devforum.roblox.com/t/ability-to-set-a-custom-night-skybox/220401 |
| S56 | Future lighting performance (shadowed light counts): https://devforum.roblox.com/t/very-poor-performance-with-future-lighting-technology/1439704 |
| S57 | Local lights and SurfaceAppearance only on Future (2020): https://devforum.roblox.com/t/surfaceappearance-studio-beta/663449/306 |
| S58 | ReflectionService: https://create.roblox.com/docs/reference/engine/classes/ReflectionService |
| S59 | Camera underwater detection: https://devforum.roblox.com/t/how-to-detect-if-the-player-camera-is-underwater/907640 |
| S60 | Graphics slider / AO at level 10 (community): https://devforum.roblox.com/t/its-2023-please-give-us-discrete-graphics-options/2239284 |
