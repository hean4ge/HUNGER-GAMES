# src: game scripts exported from Studio

Exported from place 120572716460286, read from the Studio Edit data model; the export never changes Studio.
First exported on 2026-11-12 (UTC) at place version 166, then brought up to version 199 (12 November) and version
258 (14 November: the beta release fixes), then version 302 (15 November: wave 2, a working state that has
not been reviewed yet). Each update re-checks every file against a fresh Studio listing.

## How the tree maps to Studio

- `src/<Service>/<A>/<B>/<Name><ext>` is the instance `<Service>.<A>.<B>.<Name>` (Rojo conventions).
- `.server.lua` is a Script, `.client.lua` a LocalScript, `.lua` a ModuleScript. A Script with RunContext
  Client would also be `.client.lua`; there are none.
- A script with script children is a folder: `<Name>/init.lua` (or `init.server.lua` / `init.client.lua`) holds
  the script itself, and its children sit next to it in the folder. Examples: `ServerStorage/WorldGen/TerrainData/`,
  `ServerStorage/WorldGen/Populate/`.
- Every other folder is a non-script instance (a Folder, or a container such as `StarterPlayerScripts`).
- Each file holds the script's Source string exactly (UTF-8, LF line endings as in Studio).
- No two exported siblings share a name, so no `~2` suffixes were needed.
- There is no Rojo project file; each `src/<Service>` folder corresponds to that service.

[`manifest.json`](manifest.json) lists every script with its Studio path, class, RunContext, file, byte length and
FNV-1a 32-bit hash. All 96 files were checked against Studio byte for byte.

## Contents

96 scripts, 2,715,757 bytes (place version 302):

| Service | Scripts | Bytes |
| --- | ---: | ---: |
| StarterPlayer | 31 | 1,074,586 |
| ReplicatedStorage | 20 | 277,910 |
| ServerScriptService | 13 | 329,496 |
| ServerStorage | 32 | 1,033,765 |

No other service (Workspace, Lighting, SoundService, StarterGui, ReplicatedFirst and so on) contains scripts.

## Skipped

- `ServerStorage.Archive_v1`: 20 archived old-version modules (437,690 bytes).
- `ServerStorage.MeshImports`, `ServerStorage.MeshAssets`, `ServerStorage.MeshAssets_Preview`: excluded
  (none of them contains scripts).
- `StarterPlayer.PlayerModule` (Roblox's stock player module): excluded, but this place doesn't have one, so the
  game uses Roblox's default at runtime.
- `CoreGui` and `Players`: Roblox-internal UI and runtime copies, not traversed.
- No script has Archivable set to false.
