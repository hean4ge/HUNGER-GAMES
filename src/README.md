# src: game scripts exported from Studio

Exported on 2026-11-12 (UTC) from place 120572716460286, place version 166, read from the Studio Edit
data model. Nothing in Studio was changed.

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
FNV-1a 32-bit hash. All 85 files were checked against Studio byte for byte.

## Contents

85 scripts, 2,283,538 bytes:

| Service | Scripts | Bytes |
| --- | ---: | ---: |
| StarterPlayer | 26 | 805,584 |
| ReplicatedStorage | 19 | 254,937 |
| ServerScriptService | 12 | 268,011 |
| ServerStorage | 28 | 955,006 |

No other service (Workspace, Lighting, SoundService, StarterGui, ReplicatedFirst and so on) contains scripts.

## Skipped

- `ServerStorage.Archive_v1`: 20 archived old-version modules (437,690 bytes).
- `ServerStorage.MeshImports`, `ServerStorage.MeshAssets`, `ServerStorage.MeshAssets_Preview`: excluded
  (none of them contains scripts).
- `StarterPlayer.PlayerModule` (Roblox's stock player module): excluded, but this place doesn't have one, so the
  game uses Roblox's default at runtime.
- `CoreGui` and `Players`: Roblox-internal UI and runtime copies, not traversed.
- No script has Archivable set to false.
