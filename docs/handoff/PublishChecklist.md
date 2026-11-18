# Publish checklist: 60 seconds per device

*From the [Playability plan](../design/PlayabilityPlan.md), QW15. Run it before every publish and again after every Roblox client update. A Roblox controls change once left players unable to move; this catches that kind of break in a minute.*

**In short**
- Before you publish, run the two Studio checks (about 2 minutes). Then play 60 seconds on each device you can reach: a PC, a phone, and a controller.
- On each device, go down the nine steps: move, look, sprint, jump, attack, open a crate, drink, eat, spectate.
- If any step fails, don't publish. Note the device, the step and what happened, and pass it on.
- The day after a publish, look at the onboarding funnel in the Creator Dashboard (step 3 below).
- **The first launch** has its own steps on Roblox's side: the age rating, the server size, who can play, private servers. They are in section 4, with who has to do each one.

---

## 1. Studio checks (about 2 minutes)

| # | Check | How | Pass |
|---|---|---|---|
| S1 | Every script compiles | Edit mode, command bar: `print(require(game.ServerStorage.Dev.SyntaxCheck).run())` | "SyntaxCheck OK" |
| S2 | Every action has keyboard, controller and touch input | Start a solo playtest. On the **server**: `require(game.ServerStorage.Dev.InputCheck).install()`. On the **client**: `print(require(game.ReplicatedStorage.DevInputCheck).run())`, once in the lobby and once in the arena. To see a failure on purpose: `.run({ unbind = { "Attack" } })`. When done, on the server: `require(game.ServerStorage.Dev.InputCheck).uninstall()` | "PASS Lobby" and "PASS Arena". The deliberate test prints "FAIL" |
| S3 | Map 1 is whole | Edit mode: `return require(game.ServerStorage.WorldGen.Map1.Audit:Clone()).run()` | 0 fail (on 18 November: 13 pass, 0 fail, 1 manual) |
| S4 | Two players can play a round (before a release, not before every publish) | Edit mode: `return require(game.ServerStorage.Dev.MPTest:Clone()).start({ batch = "B", clients = 2 })`, then read the result as [tools/mp_test/README.md](../../tools/mp_test/README.md) says. It needs about 9 GB of free memory | Every CHECK line passes |

Movement and jumping come from Roblox's own controls, not from our input code, so the input check can't see them. The device steps below cover them.

---

## 2. Each device (60 seconds each)

Use a published copy, or a Studio test with `Config.Studio.SoloTest` on, so you are alone in a practice round. Studio's device emulator (Test tab, Device) can stand in for a phone, but it isn't a real one: try a real phone at least once per release, ideally an inexpensive Android. **As of 18 November 2026 the game has never been tried on a real phone or with a real controller.**

| # | Step | Keyboard and mouse | Controller (Xbox / PlayStation) | Phone (touch) | Pass when |
|---|---|---|---|---|---|
| 1 | Move | W A S D | left stick | left thumbstick | You move within a second of spawning, in the lobby and in the arena |
| 2 | Look | mouse | right stick | drag on the right half | The view turns smoothly. In Settings, raise and lower *Look sensitivity*: the turn speed changes |
| 3 | Sprint | hold Shift (or Toggle / Auto, per Settings) | L3 (LS on Xbox): toggles by default | push the stick all the way (Auto is the phone default; RUN shows only in Toggle or Hold) | You speed up, the stamina bar appears, and running out says OUT OF BREATH |
| 4 | Jump | Space | A / Cross | jump button | A short hop. Holding the button doesn't bunny-hop |
| 5 | Attack | left click | RT / R2 | ATTACK | With fists, a punch. Clicking right after switching items still swings once the item is up |
| 6 | Open a crate | hold E at a crate at the Horn | hold X / Square | tap the prompt | The lid opens and the items spill. The opener sees *Take all* for 3 s. "+4 ARROWS" lines appear over the hotbar for what you took |
| 7 | Drink | look at water, E | X / Square | DRINK | The hint under the crosshair shows **this** device's button (Square on PlayStation). The Thirst bar rises. With an empty bottle the hint and button say FILL |
| 8 | Eat | hold left click with food | hold RT / R2 | hold EAT (the big button relabels) | The hint reads "HOLD [button] EAT · +12 HUNGER" for a new player. Hunger rises. At 95 or more it says YOU'RE FULL instead |
| 9 | Spectate | die (or wait for the round to end), then SPECTATE; Q / E to switch, Backspace to leave | LB / RB, B | the ‹ › buttons | The camera follows a contender, switches, and returns to you |

**Also look for, on every device**
- Pressing an empty hotbar slot makes it shake with a dry click, and you keep what you hold.
- G (D-pad down, the DROP button): a tap drops one, holding drops the stack. A line says what fell, for example "DROPPED ARROWS ×24".
- V (right-stick click, the ZOOM button): the view zooms in, the hands leave it, and it comes back when you let go or press again.
- Nothing on screen covers the crosshair while you draw the bow.
- On a phone: after you die crouched, you stand in the lobby with CROUCH unlit; after spectating, RUN stays hidden while Sprint is on Auto.
- No red errors in the Output window (Studio) or the developer console (F9 in a published game).

**First publish only: saving.** Studio never saves (its DataStore is off) and practice rounds add no stats, so saving first runs on a real server. No save or load call has ever run. With two players, before you tell anyone about the game: change a setting (for example the field of view), play one normal round, then both leave and rejoin. The setting is kept, and the lobby's record card shows the round. If it isn't, stop there and pass it on.

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

---

## 4. The first launch: Roblox's steps (as of 18 November 2026)

*Researched on 18 November 2026 from Roblox's own pages (creator docs last updated 10 and 17 November 2026, staff posts on the developer forum). Nobody opened the Creator Dashboard for this: the paths below are as Roblox's pages give them. Roblox changes these rules often, so re-read its pages before acting. Anything marked **unverified** could not be confirmed.*

**In short**
- **"All ages" is no longer a label you pick.** A newly released game can be played only by age-checked players aged 16 and over, their Trusted Friends, and children whose linked parent approves that game. It reaches younger players (Roblox Kids, 5-8, and Roblox Select, 9-15) only after it enters Roblox's Kids and Select catalogue.
- **Your decision (18 November): "No, 16+ for now".** So this launch is 4.1, public for age-checked 16+ players, with no fee paid. What all ages needs later is in 4.2.
- **A game with no rating can't be played by anyone.** The rating comes from a questionnaire that has to describe the game as it is; wrong answers can get the game and the account moderated. The truthful answers for this game are in 4.3.
- **Only you can do:** the checks on your Roblox account (4.1 step 1, 4.2 steps 1 to 3), sending the questionnaire, paying any fee, keeping Plus active, and choosing the private-server price.

### 4.1 This launch: public for age-checked 16+ players

| # | Step | Where | Who |
|---|---|---|---|
| 1 | **Your account is ready:** in good standing, at least 2 days old, age check done (facial age estimation or ID) | Roblox account settings | **You only** |
| 2 | **The build matches the answer sheet (4.3):** a defeated body topples and fades, nothing is left lying, no pain cries, no red hit effects, no blood, no wounds; the night has no gory imagery | A playtest of the build that will be published | Claude checks; you look. **On 18 November (afternoon) two points were not yet true in a saved version:** the fall-and-fade was built but not saved, and the HUD still flashed red on a hit ([Status.md](Status.md)) |
| 3 | **Name, description, genre, icon, thumbnail.** The title must not use another owner's brand: Roblox removes infringing or confusingly similar content. A draft description and three titles are in [StoreText.md](StoreText.md) | Creator Dashboard → the game → Publish settings → Game details. Icon and thumbnail: Studio's publish window | You, or Claude if the API key has `universe:write` (**unverified** that the key can set all of these) |
| 4 | **Server size 48.** The place read 60 on 18 November; a round takes 48 | Creator Dashboard → the game → Configurations → Places → the start place → Access → Maximum Visitor Count → Save Changes. Also from Studio: File → Experience Settings → Places → "..." → Configure Place. Restart servers afterwards. A script can't set it | You (or Claude through Studio's window) |
| 5 | **The rating.** Fill in the full questionnaire if the dashboard offers it, with the answers in 4.3. Read the Preview page before you press Send: it should say **Mild**. If it says Moderate, stop and pass it on. Note any regions it lists as unavailable. Allow a few days if your account is not age-verified as 18+ | Creator Dashboard → the game → Publish settings → Content ratings → Get a rating (an older Roblox page words it "Content rating" → Start) | **You only:** it is a statement made in your name. **Unverified:** which form a new game gets. One Roblox page says you answer only the first question and get a 16+ rating ("Content May Vary"); another says you fill in the whole form yourself. Follow what the dashboard offers |
| 6 | **Publish the saved place** | Studio: File → Publish → Continue (Roblox allows 5 never-released games a day) | Claude, as you asked ("do it yourself") |
| 7 | **The saving check with two players** (section 2, "First publish only"), before the game is public if a second account can be let in while it is private (**unverified** how the dashboard allows that); otherwise straight after step 8, before you tell anyone about the game | In the published game | You and a second account or a friend |
| 8 | **Make it public** | Creator Dashboard → the game → Publish settings → Manage Audience → Manage access → the Public tab. Leave "Friends" off so anyone on Roblox can join | You, or Claude with `universe:write` |
| 9 | **Paid private servers on.** Allow private servers ON, Requires Robux ON, set a price. Leave paid access OFF: it can't be combined with private servers. The game must already be public | Creator Dashboard → the game → Audience → Access Settings | **You:** the price is your call, and changing it later cancels every active private-server subscription (see 4.4) |
| 10 | **Send the questionnaire again if an answer changed** (step 9 changes "invited friends only" to Yes) | As step 5 | You |
| 11 | **The checks on a private server** in [Status.md](Status.md), then the funnel the day after (section 3) | In the game; Creator Dashboard | You, with Claude reading the results |

Expect only age-checked 16+ players at launch.

### 4.2 Later: all ages (Roblox Kids and Select)

The game reaches under-16s once **all six** of these are true:

1. Your account is in good standing, at least 2 days old and age-checked. **You only.**
2. Your account is verified: a government ID if you are 18 or over, facial age estimation if you are under 18. Roblox account settings. **You only.**
3. 2-step verification is on. Roblox account settings. **You only.**
4. The full questionnaire gives Minimal, Mild or Moderate. This game should get Mild (4.3). Mild and Minimal reach the same players. Moderate loses Roblox Kids (5-8).
5. **Either** an active Roblox Plus (or Premium) subscription held for 2 consecutive months, **or** a one-time, refundable fee of 1,000 Robux for the game. You chose not to pay the fee, so this waits for your second month of Plus in a row.
   - Where: Creator Hub → the game → Audience → Reach → Experience reach. "Refundable publishing fee" → Pay is there, and the banner on that tab says whether you qualify.
   - **Unverified:** how old your Plus subscription is, and whether it is one of the free 6-month grants Roblox gave to creators (those carry a fee waiver until 19 December 2026). Only that banner shows it. Studio read your account as not subscribed at midday on 18 November and as a member in the afternoon, so Studio doesn't settle it.
   - The fee or the subscription is checked only when you publish or update for all ages. If Plus lapses later, the game stays up.
   - **Unverified:** the refund terms. One Roblox page says the fee comes back automatically after 90 days; another says after the game keeps 25 highly engaged players for 60 days without moderation.
6. The game passes Roblox's evaluation: **250 unique plays by "highly engaged", age-checked 16+ players within 60 days.** Roblox checks hourly and reviews reports and gameplay for safety.
   - "Highly engaged" means account age, time in your game, and a minimum purchase anywhere on Roblox in the last 60 days. Roblox doesn't publish the amounts.
   - Progress shows on the same Audience → Reach tab.
   - Staying in the catalogue needs 25 highly engaged players over 60 days. **Unverified** in the current docs: this comes from a staff post of 16 July 2026.
   - There is an optional paid review instead of the 250-play wait, refundable, up to 48 hours. **Unverified** price: 50,000 Robux on a page updated 17 November, 100,000 in a June post.

After the game enters the catalogue, Roblox's reviewers assign regional (IARC) ratings; you review and accept them in Creator Hub (the deadline for Australia is 26 January 2027).

### 4.3 The answer sheet: truthful answers for this game

Answer for the most extreme thing a player can meet. The wording and option lists of the live form were not seen (**unverified**): these come from Roblox's description of it. Send the questionnaire again whenever an update changes an answer.

| Question | Answer | What makes it true |
|---|---|---|
| App type | Game | |
| Violence | Yes | Fists, blades, a mace, spears, a bow and thrown knives, used on other players' avatars and on training dummies |
| Who is the target | Humans | Human-looking avatars count |
| How players meet it | Direct violence, plus references | Hits, arrows and thrown knives; the Roll Call names the fallen |
| How often, and the camera | Often and close up; also often and far away | The arena is first person; spectators watch in third person |
| Art style | Animated | Blocky Roblox avatars. If characters or injuries ever look real, this answer changes |
| Character reactions | Unrealistic | True only while a defeated body topples and fades with no pain reaction, no wound and nothing left lying |
| Setting | Your judgement: an imaginary arena with real-world kinds of hand weapons | Roblox's docs class "imaginary places" as fantastical and "real-world locations and weapons" as realistic. If unsure, pick the more mature option and read the Preview |
| Blood | No | There is none |
| Gore | No | There is none |
| Fear | Yes: "Scary", not "Horrifying" | Tense music, a heartbeat at low health, the night, the Roll Call's static. "Not often" if the form means only the night; "often" if it counts the night's share of a round |
| Sexual content, suggestive themes, dating | No | |
| Gambling (playable or shown) | No | |
| Strong language | None | |
| Alcohol, tobacco, drugs | No | Food, water, herbs, bandages and a med kit only |
| Crude humour | No | |
| Digital purchases | **Unverified.** The game sells no passes and no products. It does have the Roblox Plus subscribe button, and will have paid private servers | If the question's wording covers a subscription prompt or private servers, answer Yes. Check the Preview |
| Cash-convertible rewards, NFTs, paid random items, paid item trading | No | |
| Players can communicate | Yes | Roblox's own text chat and emotes |
| Blocking, reporting, chat moderation | Yes to all three | Roblox provides them, and its docs say to answer yes |
| Interactions limited to invited friends | Yes once private servers are on; No until then | |
| Precise location sharing | No | |
| Prohibited content (hate symbols, terrorism, criminal techniques and so on) | No | |
| Roblox's own questions: social hangout, free-form creation, sensitive issues, content from other experiences, AI interaction, media sharing, a continuous media feed | No to all | |

**The label this should give: Mild** (repeated mild violence, no blood, mild fear). That is Claude's reading of Roblox's definitions of 10 November 2026; Roblox doesn't publish how answers map to labels, so the Preview page is the only proof (**unverified** until then). Minimal isn't reachable for a fighting game and wouldn't widen the audience.

**What would push it up to Moderate,** and lock out Roblox Kids: a realistic body left lying, pain cries, wounds or realistic-looking injuries, blood, a slow-motion kill view, or disfigured imagery at night. Two things in the game today to keep in mind when you answer: arrows and thrown knives stay stuck in a living body for up to 30 seconds, and the HUD's red flash on a hit (still in on 18 November).

### 4.4 Roblox Plus and private servers

- **What pays:** (a) 250 Robux a month for a new subscriber's first three paid months when they subscribe through the game's own button; (b) up to 100 Robux a month for each Plus member who spends at least 60 minutes in 30 days in a paid private server they own, if it is among their top five. Roblox pays for members' discounts itself.
- **The private-server price.** Roblox's worked example pays the creator 70 % of the price, capped at 100 Robux: a 100 Robux server pays 70, a 50 Robux server pays 35. About 143 Robux or more would reach the cap; that figure is arithmetic from the example, not a stated rule (**unverified**), and players who aren't members pay that price every month. Free private servers earn nothing. No minimum or maximum price is stated (**unverified**).
- **Where the earnings show:** Creator Hub → Creations → the game → Monetization → Roblox Plus.
- **Test the button once the game is published:** with an account that isn't subscribed, press ROBLOX PLUS, then SUBSCRIBE; Roblox's own window opens. If you can, try a child test account too. In Studio the window never appears.
- **Unverified, and so built conservatively:** Roblox states no rule on where or how often the subscribe window may be shown, no age or region limit on it, and nothing on how it behaves for Roblox Kids or Select accounts. The game never opens it by itself.
- **Don't** play in your own private server on other accounts to earn the payout: Roblox says it discounts activity that isn't genuine.

### 4.5 Roblox's pages these steps come from

- Content ratings: `create.roblox.com/docs/production/promotion/content-ratings` (updated 17 Nov 2026)
- Content maturity and compliance: `create.roblox.com/docs/production/promotion/content-maturity` (10 Nov 2026)
- Roblox Kids and Select: `create.roblox.com/docs/production/publishing/kids-and-select` (17 Nov 2026)
- Create and publish games and places: `create.roblox.com/docs/production/publishing/publish-games-and-places` (17 Nov 2026)
- Roblox Plus: `create.roblox.com/docs/production/monetization/roblox-plus` (17 Nov 2026); Private servers: `.../monetization/private-servers`
- Developer forum: "Introducing Roblox Plus" (10 Apr 2026, edited 12 Nov 2026); "Highly engaged player threshold drops to 250" (19 Aug 2026)

Roblox's Help Centre articles could not be opened and were not read.
