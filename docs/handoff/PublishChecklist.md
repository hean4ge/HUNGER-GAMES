# Publish checklist: 60 seconds per device

*From the [Playability plan](../design/PlayabilityPlan.md), QW15. Run it before every publish and again after every Roblox client update. A Roblox controls change once left players unable to move; this catches that kind of break in a minute.*

**In short**
- Before you publish, run the two Studio checks (about 2 minutes). Then play 60 seconds on each device you can reach: a PC, a phone, and a controller.
- On each device, go down the nine steps: move, look, sprint, jump, attack, open a crate, drink, eat, spectate.
- If any step fails, don't publish. Note the device, the step and what happened, and pass it on.
- The day after a publish, look at the onboarding funnel in the Creator Dashboard (step 3 below).

---

## 1. Studio checks (about 2 minutes)

| # | Check | How | Pass |
|---|---|---|---|
| S1 | Every script compiles | Edit mode, command bar: `print(require(game.ServerStorage.Dev.SyntaxCheck).run())` | "SyntaxCheck OK" |
| S2 | Every action has keyboard, controller and touch input | Start a solo playtest. On the **server**: `require(game.ServerStorage.Dev.InputCheck).install()`. On the **client**: `print(require(game.ReplicatedStorage.DevInputCheck).run())`, once in the lobby and once in the arena. To see a failure on purpose: `.run({ unbind = { "Attack" } })`. When done, on the server: `require(game.ServerStorage.Dev.InputCheck).uninstall()` | "PASS Lobby" and "PASS Arena". The deliberate test prints "FAIL" |

Movement and jumping come from Roblox's own controls, not from our input code, so the input check can't see them. The device steps below cover them.

---

## 2. Each device (60 seconds each)

Use a published copy, or a Studio test with `Config.Studio.SoloTest` on, so you are alone in a practice round. Studio's device emulator (Test tab, Device) can stand in for a phone, but it isn't a real one: try a real phone at least once per release, ideally an inexpensive Android.

| # | Step | Keyboard and mouse | Controller (Xbox / PlayStation) | Phone (touch) | Pass when |
|---|---|---|---|---|---|
| 1 | Move | W A S D | left stick | left thumbstick | You move within a second of spawning, in the lobby and in the arena |
| 2 | Look | mouse | right stick | drag on the right half | The view turns smoothly. In Settings, raise and lower *Look sensitivity*: the turn speed changes |
| 3 | Sprint | hold Shift (or Toggle / Auto, per Settings) | L3 (LS on Xbox): toggles by default | push the stick all the way (Auto is the phone default; RUN shows only in Toggle or Hold) | You speed up, the stamina bar appears, and running out says OUT OF BREATH |
| 4 | Jump | Space | A / Cross | jump button | A short hop. Holding the button doesn't bunny-hop |
| 5 | Attack | left click | RT / R2 | ATTACK | With fists, a punch. Clicking right after switching items still swings once the item is up |
| 6 | Open a crate | hold E at a crate at the Spire | hold X / Square | tap the prompt | The lid opens and the items spill. The opener sees *Take all* for 3 s. "+4 ARROWS" lines appear over the hotbar for what you took |
| 7 | Drink | look at water, E | X / Square | DRINK | The hint under the crosshair shows **this** device's button (Square on PlayStation). The Thirst bar rises. With an empty bottle the hint and button say FILL |
| 8 | Eat | hold left click with food | hold RT / R2 | hold EAT (the big button relabels) | The hint reads "HOLD [button] EAT · +12 HUNGER" for a new player. Hunger rises. At 95 or more it says YOU'RE FULL instead |
| 9 | Spectate | die (or wait for the round to end), then SPECTATE; Q / E to switch, Backspace to leave | LB / RB, B | the ‹ › buttons | The camera follows a contender, switches, and returns to you |

**Also look for, on every device**
- Pressing an empty hotbar slot makes it shake with a dry click, and you keep what you hold.
- G (D-pad down, the DROP button): a tap drops one, holding drops the stack. A line says what fell, for example "DROPPED ARROWS ×24".
- Nothing on screen covers the crosshair while you draw the bow.
- No red errors in the Output window (Studio) or the developer console (F9 in a published game).

**When something fails**, write down the device and its model, the step, what you pressed and what happened, then pass it to the lead before publishing.

---

## 3. The day after a publish: the onboarding funnel

The game logs Roblox's onboarding funnel (`OnboardingService`). It only counts in published games; in Studio each step is printed to the Output instead, as `[Onboarding] Name: 3 OnPlate`.

Creator Dashboard → your experience → Analytics → Funnels → Onboarding. The ten steps are:

| Step | Name | What it means |
|---|---|---|
| 1 | Joined | joined the game |
| 2 | Moved | moved within 10 s of first spawning |
| 3 | OnPlate | was put on a launch plate |
| 4 | LeftPlate | got more than 10 studs from the plate after the horn |
| 5 | OpenedCrate | opened a supply crate |
| 6 | EquippedItem | held an item |
| 7 | AteOrDrank | ate or drank (a bottle, or a sip from water) |
| 8 | SurvivedRollCall1 | was alive at the round's first Roll Call |
| 9 | FinishedRound | was in a round when it ended |
| 10 | OnPlateRound2 | was on a launch plate again after finishing a round |

**What to look for**
- A big drop between 1 and 2 means players can't move. Treat it as an emergency: run section 2 at once.
- A big drop between 2 and 3 means players leave in the lobby before a round starts (the wait).
- Fix the largest early drop first. The plan's section 6 test with friends tells you why it happens.
