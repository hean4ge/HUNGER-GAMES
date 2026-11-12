# LAST STANDING

A first-person survival-arena game for Roblox: 24 contenders, one forest valley, the last one standing wins. This is original IP; see the naming rules in `docs/Roadmap.md` section 7.

The game is built in Roblox Studio (place 120572716460286). This repo holds its source, art pipeline and design docs.

## Start here
- [`docs/handoff/Status.md`](docs/handoff/Status.md): what's in the game now, what's verified, open issues and next steps.
- [`docs/Roadmap.md`](docs/Roadmap.md): the long-term plan, made from the design notes in [`docs/design/UserNotes.md`](docs/design/UserNotes.md).
- [`docs/design/PlayabilityPlan.md`](docs/design/PlayabilityPlan.md): making the game easy to play, intuitive and fun.
- [`docs/GameDesign.md`](docs/GameDesign.md): the game's technical spec (architecture, modules, remotes, world layout).

## Layout
| Folder | What's in it |
|---|---|
| `src/` | Every game script, exported from Studio in Rojo layout. `src/manifest.json` maps each file to its Studio path, with hashes. |
| `art/` | The Blender pipeline: generators in `art/blender`, manifests and asset ids in `art/manifests`, reference renders in `art/previews`. `art/README.md` explains it all. |
| `docs/` | The design docs, research (`docs/research`), handoff notes (`docs/handoff`) and the pillar designs (`docs/design`). |

Large render outputs are left out of git (see `.gitignore`); the review scripts in `art/blender` regenerate them.
