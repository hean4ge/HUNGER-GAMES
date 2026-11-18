# mp_test: a real multiplayer test in Studio

Starts one server and 2 to 4 clients as separate Studio processes and plays scripted rounds between them. The test
code is `ServerStorage.Dev.MPTest` (`src/ServerStorage/Dev/MPTest/`): `init.lua` starts a test, `Driver.server.lua`
runs it on the test's server, `Bot.client.lua` is given to every test client. Nothing of it runs in a live game.

## Run a batch

In Studio, Edit mode (`execute_luau`):

```lua
return require(game.ServerStorage.Dev.MPTest:Clone()).start({ batch = "B", clients = 2 })
```

Batches: `A` combat, `B` reach, poses, loot, eating, border, kill, result, Roll Call, round two, `B2` poses and items,
`C` three clients (spectating, dusk Roll Call, a leaver), `D` a late joiner, `E` a leave during the Countdown,
`G` the fill rule (a third client joins during a 45-second lobby countdown).
The header of `init.lua` lists the arguments. The session ends itself and frees the `QA_Lock` it took.

## Read the result

```bash
python tools/mp_test/readlog.py 6 --newest --grep CHECK     # the checks of the newest run in the last 6 minutes
python tools/mp_test/readlog.py 6 --newest --out run.log    # every line (server truth and each client's report)
```

`wait_run.py <name> <start epoch>` waits for the run started at that time (the number `start` returns), saves the
server's lines, every process's whole log and prints the checks and whether the test processes have gone.

Since 18 November the bots also log by themselves: `BODY` (a defeated body on that screen, sampled for 4 s), `SEE-BOW`
(another player's bow pose), `RED[...]` (red on screen after a hit, a hurt, a death), `CHATWINDOW` (open or closed).
The test server runs with the live respawn wait of 4 s (`respawn`), and the PLUS mark checks use the Studio switch
`Workspace.PlusTestMember` on the test server only.

## Pictures

Start this before the batch; it saves every client window at the driver's `SHOT` lines into `tools/mp_test/shots/`:

```powershell
& tools\mp_test\shots.ps1 -Run runB
```

## Limits

- A server and two clients need about 9 GB of free memory; three clients about 12 GB.
- Test players are Player1, Player2, ... with UserIds -1, -2, ...; they wear the Studio user's avatar.
- DataStores are off in Studio, so saving is not covered. Real ping is not covered either.
- Unfocused test windows render at reduced quality; timings are coarse. They do not draw the Roll Call's sky points at
  all (0.72 studs, 170 studs away), and a test script cannot raise the quality (`settings()` needs a plugin). The
  `..._x3` pictures show the points made three times bigger by the test, where the game put them.
- Start the picture watcher at least 25 s after the last run ended, or it reads that run's log and stops at once.
