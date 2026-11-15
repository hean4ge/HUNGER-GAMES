# studio_sync: the repo and Roblox Studio, kept identical

Scripts and data move between this repo and the place open in Studio as exact bytes. Nothing is retyped through an
editor, and every transfer is checked by size and FNV-1a hash on both sides.

From 15 November 2026 the files under `src/` are the source of truth. Edit them on disk, then push them into Studio.

## How it works

| Direction | Carrier | Studio side |
| --- | --- | --- |
| Disk to Studio | A pack: an `.rbxmx` of base64 chunks written into Studio's own content folder (`content/ls_import/`) | `game:GetObjects("rbxasset://ls_import/<pack>.rbxmx")` |
| Studio to disk | Lines printed to Studio's log file (`%LOCALAPPDATA%\Roblox\logs\*_Studio_*_last.log`) | `print` |

The Studio side is the module `ServerStorage.Dev.StudioSync` (`src/ServerStorage/Dev/StudioSync.lua`). No place
setting is changed and nothing is uploaded: HTTP stays off.

`.studio_sync/state.json` (not committed) records the fingerprint Studio last had for each script. A push refuses to
overwrite a script whose Studio copy no longer matches that record, so an edit made directly in Studio is never lost
without anyone noticing.

## Everyday use

Run the Python commands from the repo root. Run the Luau lines in Studio through `execute_luau`, in Edit mode.

**See what would be pushed**

```bash
python tools/studio_sync/sync.py status
```

**Push scripts into Studio** (files, folders or Studio paths; or `--changed` for everything that differs)

```bash
python tools/studio_sync/sync.py push src/ReplicatedStorage/Shared/Config.lua
```

It prints a pack name and the line to run in Studio:

```lua
return require(game.ServerStorage.Dev.StudioSync:Clone()).apply("p101500_ab12")
```

Then record the result:

```bash
python tools/studio_sync/sync.py confirm p101500_ab12
```

`apply` reports each script as updated, created, same, DRIFT or FAILED. DRIFT means Studio holds an edit the repo has
not seen. Pull that script, merge by hand, and push again. Use `push --force` (then `apply(pack, { force = true })`)
only when you have looked at what it overwrites.

**Pull scripts out of Studio**

```lua
return require(game.ServerStorage.Dev.StudioSync:Clone()).export("x1")  -- or export("x1", { "ServerStorage.Dev" })
```

```bash
python tools/studio_sync/sync.py pull x1            # report what differs from the repo
python tools/studio_sync/sync.py pull x1 --write    # write the differing files and record the fingerprints
```

**Send data files (height maps and the like)**

```bash
python tools/studio_sync/sync.py blob map1_data Height=path/to/height.bin Material=path/to/material.bin
```

```lua
local pack = require(game.ServerStorage.Dev.StudioSync:Clone()).open("map1_data")
local height = pack:blob("Height") -- a buffer holding the file's exact bytes
pack:close()
```

A 3 MB file loads and verifies in about 0.2 seconds.

## Rules

- Edit mode only. `apply` refuses to run during a playtest.
- One script is at most 199,000 bytes (Studio caps a Source at 200,000 characters). Split bigger data into blobs.
- Sources are UTF-8 with LF line endings and no BOM. `push` refuses anything else.
- Script names with a dot in them are not supported.
- A new file under `src/` maps to Studio by the rules in [src/README.md](../../src/README.md): `Name.lua` is a
  ModuleScript, `Name.client.lua` a LocalScript, `Name.server.lua` a Script, and `Name/init.lua` a script with children.
- Packs live in Studio's install folder and are lost when Studio updates. `sync.py clean` removes old ones.
- After a Studio update or reinstall, run `sync.py bootstrap` and the Luau lines it prints to put the module back.
- `src/manifest.json` is still the formal record of an export. Update it when a place version is saved.

## First-time setup

```bash
python tools/studio_sync/sync.py bootstrap
```

Then run the lines it prints in Studio once.
