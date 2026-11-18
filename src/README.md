# src: game scripts exported from Studio

Exported from place 120572716460286, read from the Studio Edit data model; the export never changes Studio.
First exported on 2026-11-12 (UTC) at place version 166, then brought up to version 199 (12 November) and version
258 (14 November: the beta release fixes), then version 302 (15 November: wave 2). Since 15 November scripts move
both ways with [tools/studio_sync](../tools/studio_sync/README.md): `sync.py push` sends files into Studio,
`sync.py pull` brings Studio's scripts back, and `sync.py status` says what differs. On 18 November, at place
version 404 (commit `e2226af`: Map 1, the lighting pass, the review fixes), all 116 script files equalled Studio.

## How the tree maps to Studio

- `src/<Service>/<A>/<B>/<Name><ext>` is the instance `<Service>.<A>.<B>.<Name>` (Rojo conventions).
- `.server.lua` is a Script, `.client.lua` a LocalScript, `.lua` a ModuleScript. A Script with RunContext
  Client would also be `.client.lua`; there are none.
- A script with script children is a folder: `<Name>/init.lua` (or `init.server.lua` / `init.client.lua`) holds
  the script itself, and its children sit next to it in the folder. Examples: `ServerStorage/WorldGen/Map1/Assets/`,
  `ServerStorage/Dev/MPTest/`.
- Every other folder is a non-script instance (a Folder, or a container such as `StarterPlayerScripts`).
- Each file holds the script's Source string exactly (UTF-8, LF line endings as in Studio).
- No two exported siblings share a name, so no `~2` suffixes were needed.
- There is no Rojo project file; each `src/<Service>` folder corresponds to that service.

[`manifest.json`](manifest.json) lists scripts with their Studio path, class, RunContext, file, byte length and
FNV-1a 32-bit hash. **It is out of date:** it still lists the 96 scripts of version 302 with that version's sizes and
hashes, and 20 files are missing from it (its notes name them). It needs regenerating after the next place save;
`tools/studio_sync` has no command for that. `sync.py` reads it only to map files to Studio paths, and finds the
unlisted files by the rules above.

## Contents

116 scripts, 3,723,694 bytes (place version 404, commit `e2226af`):

| Service | Scripts | Bytes |
| --- | ---: | ---: |
| StarterPlayer | 33 | 1,195,805 |
| ReplicatedStorage | 21 | 421,195 |
| ServerScriptService | 14 | 376,760 |
| ServerStorage | 48 | 1,729,934 |

No other service (Workspace, Lighting, SoundService, StarterGui, ReplicatedFirst and so on) contains scripts.

## New since version 302

- **Map 1** (18 November): `ReplicatedStorage/Shared/Map1Regions.lua`; `ReplicatedStorage/Shared/ArenaLayout.lua`
  is now the Map 1 layout; the builders in `ServerStorage/WorldGen/Map1/` (`Assets` with `Manifest`, `Audit`, `Data`,
  `Loot`, `Scatter`, `Terrain`, `Water`). The data they read comes from [tools/map1](../tools/map1).
- **The classic forest arena, vaulted:** `ServerStorage/Vault_ClassicForest/` holds its layout (`ArenaLayout_v2`),
  `TerrainGen`, `TerrainData`, `Populate`, `RealAssets`, `WaterPoints`, `WaterPointsBuilder`, `Settings` and a
  `README` module with the restore steps. Nothing in the game requires them.
- **Block arms:** `StarterPlayer/.../Controllers/ViewmodelController/Blocky.lua`.
- **Roblox Plus** (18 November): `ServerScriptService/Server/Services/PlusService.lua` (server) and
  `StarterPlayer/.../Controllers/PlusController.lua` (client): the opt-in ROBLOX PLUS button in the lobby, its
  panel, the member mark and the PRIVATE SERVER label. The loaders pick both up from their folders. The remote
  `ReplicatedStorage.Remotes.PlusSubscribe` is created by `PlusService` at start and is not in `Shared/Net.lua`.
- **The multiplayer test** (18 November): `ServerStorage/Dev/MPTest/` is `init.lua` (starts a test from Edit mode),
  `Driver.server.lua` (runs it on the test's server) and `Bot.client.lua` (given to every test client). It starts a
  server and 2 to 4 clients as separate Studio processes. The scripts sit in ServerStorage, where nothing runs, and
  the driver also checks for Studio and for the test's own arguments, so none of it runs in a live game. Its tools
  are in [tools/mp_test](../tools/mp_test/README.md): `readlog.py` (reads the checks from the test server's log),
  `shots.ps1` (saves each client window) and the README with the batches.
- **`ServerStorage/Dev/StudioSync.lua`:** the Studio half of `tools/studio_sync`.

## Skipped

- `ServerStorage.Archive_v1`: 20 archived old-version modules (437,690 bytes).
- `ServerStorage.MeshImports`, `ServerStorage.MeshAssets`, `ServerStorage.MeshAssets_Preview`: excluded
  (none of them contains scripts).
- `StarterPlayer.PlayerModule` (Roblox's stock player module): excluded, but this place doesn't have one, so the
  game uses Roblox's default at runtime.
- `CoreGui` and `Players`: Roblox-internal UI and runtime copies, not traversed.
- No script has Archivable set to false.
