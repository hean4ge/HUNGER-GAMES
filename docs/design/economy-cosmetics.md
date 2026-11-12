# Gold, Robux, store and cosmetics

> Pillar file for the [Roadmap](../Roadmap.md) · key `economy-cosmetics` · written by the economy designer, lightly edited by the lead designer so names match across pillars. Phase numbers inside this file are the pillar's own; the Roadmap's phases are the build order.

**Lead notes (where the Roadmap reconciles this pillar with the others)**

- **Roadmap phases.** This pillar's Phase 1 ("Wallet and Armoury") is Roadmap Phase 6a. Its Phase 2 ("Cosmetic depth") is 6b, an art track that runs alongside Phases 7–9 only if someone else makes the art (for one developer it adds 6–8 weeks). Its Phase 3 lands in Phase 9 (the Gauntlet Pass) and in 6b (Canopies, since Patron capsules exist from Phase 3). The profile itself is built earlier, in Roadmap Phase 5.
- **One profile:** `Profiles_v2`, key `u_<UserId>`, session-locked, owned by an extended `DataService`. The Modes, Loot and Story fields go into the same profile.
- **"EFFECT DROPS (ENCHANTMENTS)" are the Loot pillar's Citadel modifications** (your own plan says so). Tempers stay as the cosmetic effect layer, and Temper unlocks come from hidden caches, so the Lure stays the Wardens' only bait drop.
- **No paid rerolls:** Daily Trials keep one free reroll a day (the Modes pillar's rule), so the 5 R$ shelf is the Gold Pouch and the Signal Flare.
- **Private Games pay no XP or Gold** (the Modes pillar's rule), replacing the quarter-Gold rule in §5.2.
- **One lobby plan:** NE the Armoury, SE the Outfitter (with the Gold and pass counter), SW the Archive, NW the Gate.
- **Renamed for consistency:** Daily Trials, Season challenges and Achievements (the Modes pillar's names), hidden caches (was "Warden caches"), Patron capsules (was "Patron drops"), Trial Reroll.
- **Lead review:** the Spire's restock is **the Offering** (was the Feast) and the death signal is **the Knell**. The cosmetic grade Trinket is now **Charm**. Trial rerolls are never sold, for Robux or for Gold. No Prospector Pass at launch; revisit after a month of economy data. A cosmetic is never harder to see or trace than the plain version (§6.3, rule 8), and the Citadel look is the lore's brass, smoked glass and iron grey.

---

*Checklist sections 5 (Economy and monetisation) and 6 (Cosmetics). I checked this read-only against the live place, the build reports and Roblox's creator docs on 11 November 2026.*

**In short.** Gold is the game's one soft currency. You earn it by playing, and you can also buy it with Robux. Gold and Robux change only how you look. They never change how you fight, how you survive or what you can see, and nothing random is ever for sale. Every cosmetic is designed twice: once for our first-person view and once for third person. Cosmetics are sold in a lobby store (four pavilions plus a STORE screen). The store runs on a new player profile that is locked to one server at a time and grants each Robux purchase exactly once. **First slice:** earn Gold in a round, spend it on a bow finish, buy Gold with Robux, and see all of it survive a rejoin.

## 1. What exists today

| Area | Status | What the code shows |
|---|---|---|
| Player data | Partly built | `DataService` saves Wins, TotalKills, RoundsPlayed and Settings to DataStore `PlayerStats_v1` (key `Player_<UserId>`). Stats are saved as deltas through `UpdateAsync`, with retries, a 120 s autosave and `BindToClose`, and it writes `Version = 1`. There is **no session lock, no wallet, no ownership and no purchase history**. Stats are mirrored to Player attributes for the lobby record card. |
| Gold | Not started | "Gold" exists only as a UI colour (`Theme.Colors.Gold` 226,186,110) for victory and rank text. |
| Robux, passes, store | Not started | No script uses `MarketplaceService`, `ProcessReceipt`, `PolicyService`, `TeleportService`, `MemoryStoreService` or `AnalyticsService`. All 22 RemoteEvents are gameplay. StarterGui has HUD, HUDFX, Lobby, Overlay, Menu and Spectate, but no store. |
| Item looks | Hook ready | `Shared.ItemModels.build(itemId, variant)` builds every item model: the first-person one (`ViewmodelController.Rig:setItem` → `"view"`), the held model others see (`InventoryService.attachModel` → `"world"`, welded to the right hand as `EquippedModel`), arrows, and the hotbar icons. `WorldGen.ItemAssets` tags each mesh part with a `Role` attribute. Today's meshes have no textures (material and colour come from the Manifest). The textured ItemsReal set is a Part 2 job. |
| First-person arms | Fixed look | `Rig` (another team rebuilt it while this review ran) has dark Fabric sleeves (`SLEEVE` 47,51,57), a `CUFF` (70,64,56) and fists in the character's skin colour (`setSkin`). |
| Trails | Default only | `ProjectileController` gives every arrow a faint off-white `Trail` (0.16 s lifetime, LightEmission 0.25). It builds each shot from `ProjectileFired`, which carries the shooter's UserId. |
| Attack and kill hooks | Ready | `CombatController.action` (Swing, Strike, Release, ThrowRelease…). The `CombatAction` remote goes to other clients, but nothing uses it yet. Also `HitConfirm.killed` and `PlayerService.died`. |
| Avatars | Own avatar | `PlayerService.doLoad` loads each character from the player's own `HumanoidDescription`. Body scales are forced to standard today, and the Part 2 plan removes that. `CharacterVisuals` shows your torso and legs in first person. `FallenSnapshots` builds the Roll Call busts from `GetAppliedDescription()` and strips trails, beams, particles and highlights. |
| Animations | Partly built | `Animate` keeps the emote wheel (`PlayEmote`): 7 stock Roblox emotes, only when you stand still on the ground. It also accepts Animation objects. It ignores avatar animation packs on purpose: "everyone moves the same, realistic way". |
| Big moments | Shared, not personal | `LaunchController` plays the plate rise (whir, clunk, under-light, dust) for plates within 140 studs. At Ending, `NotificationController` shows a 2D victory screen and the round summary. `RoundService.endRound` knows placements and kills. It counts a Win only if the round lasted 15 s or the winner has a kill, and never in practice. |
| Drops | No parachutes | Offering crates fall 55 studs in 1.1 s with an ember light (`LootService.dropCrateIn`). Patron capsules don't exist yet. |
| Lobby | Room for a store | `Populate.Lobby` builds a courtyard with a fire dais, four pavilions (NE, SE, SW, NW, 63 studs out), eight banners, two notice boards with SurfaceGuis, and an overlook to the west. |
| Conventions | Ready | `Net` uses RemoteEvents plus a token-bucket `rateLimit`. `Main` loads any extra service after its ORDER list. Loot rarity (Common to Legendary) colours the hotbar and ground items, so cosmetics need their own grade names. F and B are unbound, and DPadLeft/Right are used only inside the settings menu. |

**Bottom line:** none of this pillar exists yet beyond the stock emotes, and nothing bought can be saved yet. The good news: every place a cosmetic must touch already goes through a single function, so the work is additive.

## 2. From the notes to our names

| The notes say | Our name |
|---|---|
| "IN GAME CURRENCY - GOLDS", "BUY CURRENCY WITH ROBUX" | **Gold**, **Gold packs** |
| "SMALL PACKAGE ETC", "Small / Medium / Large Gold packages" | **Pouch, Purse, Satchel, Coffer, Chest, Vault** |
| "GAME ENHANCEMENTS - SMALL MONEY 5 ROBUX E.G" | **Pocket buys**: Gold Pouch, Signal Flare |
| "PREMIUM GAMEMODE", "Premium Arena" | **The Wardens' Gauntlet** (Gauntlet Pass) |
| "Premium game passes" | **Gauntlet Pass, Supporter Crest, Wardrobe Pass** (no Prospector Pass at launch) |
| "Private Games" | **Private servers** with a host panel |
| "BUY VISUAL EFFECTS FOR ITEMS", "Weapon skins" | **Finishes** |
| "EFFECT DROPS (ENCHANTMENTS)" | the Loot pillar's **Citadel modifications**; **Tempers** unlock from hidden caches |
| "TRAILS ETC", "Special weapon trails" | **Trails** |
| "Weapon elimination effects" | **Elimination effects** |
| "Character entrance effects" | **Entrances** on the launch plates |
| "Unique Cornucopia spawn animations" | **Showcase banner** on the Spire |
| "Special parachute effects" | **Canopies** on Patron capsules |
| "Victory animations", "Victory celebrations" | **Celebrations**, the winner camera, the **Laureate plinth** |
| "District-themed clothing", "Capitol-themed outfits", "Character cosmetic packages" | **Province outfits** and **Citadel couture** |

## 3. The charter (every feature in this pillar follows it)

1. **Two currencies:** Gold (earned in play, or bought with Robux) and Robux.
2. **Power is never for sale.** Anything that changes fighting, surviving, moving, loot or information is earned in play. It is never sold for Robux or Gold. That covers skills, character abilities, the Loot pillar's Citadel modifications, Patron capsules and Favour. The user's own plan says the same: keep cosmetics "separate from equipment that determines competitive performance".
3. **Nothing random is for sale.** No crates, spins or random rolls for Gold or Robux. So no odds tables and no regional blocking are needed. Random rewards appear only where they are earned (hidden caches, 6.2).
4. **The parity envelope.** A cosmetic may change colour, material, pattern and animation. It may not change size, silhouette, hitbox, brightness, light, loudness, or what other players can learn about you, and it never makes you or your shots harder to see (6.3).
5. **An honest store.**
   - Prices are fetched from Roblox at runtime.
   - No fake sales and no restarting timers.
   - No purchase prompt without a click.
   - The death screen never advertises.
   - Gold spends need a confirmation.
6. **The server decides.** It grants, spends and equips. Each Robux purchase is granted exactly once, keyed by its PurchaseId.
7. **Our own world.** Province and Citadel looks are original designs (6.5).

## 4. Platform rules we build to (checked 11 Nov 2026)

| Rule | What we do | Source |
|---|---|---|
| Developer products: one `ProcessReceipt` callback per game. Return `PurchaseGranted` only after the grant; `NotProcessedYet` retries on the next join. Never grant from `PromptProductPurchaseFinished`. Keep your own purchase history. Minimum price is 1 R$. | One handler in `StoreService`, with PurchaseIds stored in the profile (8.4). | https://create.roblox.com/docs/production/monetization/developer-products |
| Passes are one-time and meant for lasting privileges, not consumables. Check `UserOwnsGamePassAsync` on join and handle `PromptGamePassPurchaseFinished`. | Four passes, all lasting privileges (5.7). | https://create.roblox.com/docs/production/monetization/game-passes |
| Paid random items cover anything random bought with Robux, or with currency bought with Robux. They must show every outcome and its odds before purchase, and must be blocked for users whom `PolicyService` restricts. Randomness earned in play needs neither. | We sell nothing random (charter 3). | https://create.roblox.com/docs/production/monetization/paid-random-items |
| Discounts must be real and not used to rush people. No false scarcity, no wrong or restarting timers, no "act now" wording, nothing pushy toward minors. | Store wording rules (7.3). | https://create.roblox.com/docs/production/monetization |
| Managed pricing (regional prices at 30–100% of the default, plus price tests) is on by default for new games. Don't hard-code prices. Fetch them with `GetProductInfoAsync` or `GetDeveloperProductsAsync`. Use `GetUsersPriceLevelsAsync` to protect gifts. | Every Robux price in this section is a default price; the UI always asks Roblox. | https://create.roblox.com/docs/production/monetization/managed-pricing · https://create.roblox.com/docs/production/monetization/regional-pricing |
| Private servers are free or a monthly Robux fee. Since 24 Sep 2026, Roblox Plus members get one free private server per game. Creators earn up to 100 R$ for each Plus member who spends 60+ minutes a month in their server. Paid private servers can't be combined with paid access, and under-13s may be blocked by their settings. | Paid private servers. The round loop stays in one place, so owners stay in their server (5.9). | https://create.roblox.com/docs/production/monetization/private-servers · https://devforum.roblox.com/t/changes-to-roblox-plus-private-server-limits/4739922 |
| Roblox Plus is Roblox's 2026 member subscription. Roblox pays the member discount, so creators earn the same per sale. Plus sign-ups through our prompt pay a bonus. | Nothing to build now; maybe a sign-up card later (5.10). | https://create.roblox.com/docs/production/monetization/roblox-plus |
| Subscriptions cost from 49 R$ (or one of five local-currency tiers). Benefits must be delivered for the whole term and be the same on all platforms. | Optional, later (5.10). | https://create.roblox.com/docs/production/monetization/subscriptions |
| Content maturity: Moderate is the most a Roblox Select (ages 9–15) game may carry. A new game reaches age-checked 16+ first and opens to Select after the all-ages requirements and a 250-play evaluation. We expect Moderate (no blood) and confirm it by submitting the questionnaire before ragdolls ship. | Children are in the audience: no pressure tactics and no blood-like effects. | https://create.roblox.com/docs/production/promotion/content-maturity · https://create.roblox.com/docs/production/publishing/kids-and-select |
| Data stores allow 4 MB per key and about 60 + 40 × players requests a minute per server. The official pattern keeps a session lock in the key's metadata and records PurchaseIds before granting. | 8.3–8.4. | https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing · https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits |
| `AnalyticsService:LogEconomyEvent` logs currency sources and sinks. It works only from the server, in published games. | Every Gold source and sink is logged (8.6). | https://create.roblox.com/docs/production/analytics/economy-events |
| Rewarded video ads: the reward must be a non-random developer product, granted when the ad finishes (Roblox recommends one worth 3–10 R$). The game needs an average of 2,000 unique visitors a month, among other rules (open question 10). | The Gold Pouch is ready to be an ad reward (5.10). | https://create.roblox.com/docs/production/promotion/rewarded-video-ads |

## 5. The economy

### 5.1 Earning Gold

| Source | Gold | Rule |
|---|---|---|
| Taking part | 10 | You started the round and weren't AFK (you moved 30+ studs or acted in the first 60 s) |
| Placement | 1st 100 · 2nd 70 · 3rd 55 · 4th–5th 40 · 6th–10th 25 · 11th–16th 15 · 17th–24th 5 | From `RoundService.endRound`. Survivors at the time limit share 1st, as today |
| Eliminations | 15 each, up to 8 a round | From `PlayerService.died` kill credit, including its 15 s window for environmental deaths |
| Winning | +50 | Same rule as the Wins stat: 15 s or a kill, never in practice |
| First round / first win of the day | +50 / +100 | Days run on UTC |
| Daily Trials (3) | 40 · 60 · 80 | The Modes pillar sets them. One free reroll a day |
| Season challenges (weekly) | 250 · 300 · 400 | Modes pillar |
| Achievements | 100–1,000, once each | Modes pillar |
| Hidden caches (hidden supplies) | 25–60, one cache per player per round | Sealed tins in hard places: the cave chamber, the waterfall shelf, the watchtower. They give Gold only, never items. World art places the markers |
| Story chapters | 200 on the first clear | Story pillar |
| Events | e.g. a Jubilee weekend at +50% round Gold | Real dates, announced in advance |
| Practice rounds | 0 | — |

### 5.2 Fair-play limits

- **Lobby size.** Full placement and elimination Gold needs 8 or more real (not AFK) contenders. 4–7 contenders pay half; fewer than 4 pay only the taking-part Gold. This stops two friends trading wins in an empty server.
- **Private servers.** A quarter of the taking-part Gold, at most 200 a day, and no progress on objectives or feats. The owner can switch rewards off entirely. *Lead note (Roadmap): Private Games pay no XP or Gold at all (the Modes pillar's rule).*
- **Repeat kills.** In lobbies under 8, no elimination Gold for a third kill on the same player in one UTC day.
- **Soft cap.** After 3,000 round Gold in a UTC day, round Gold halves. Bots hit this cap; people almost never do.
- **Tuning.** Every number lives in `Config.Economy` and is tuned from the analytics in 8.6.

### 5.3 What a player earns

| Player | Rounds a day | Gold a day |
|---|---|---|
| Casual: an hour a day, mid-table | about 5 | about 550 (190 from rounds, 180 from objectives, 50 first round, about 130 from weekly missions) |
| Committed: three hours, often top 5 | about 15 | about 2,000 |

A casual player can afford an Issue item every day and a Citadel piece in about two weeks.

### 5.4 Spending Gold: grades and prices

Cosmetic grades are deliberately not the loot rarities. Their grade marks are small metal swatches, not the loot colours.

| Grade | Gold | Casual days | Typical item |
|---|---|---|---|
| Charm | 250 | ½ | a Showcase banner, a gesture |
| Issue | 500 | 1 | a recoloured finish, a basic emote |
| Fine | 1,000 | 2 | a material finish, an arrow trail |
| Masterwork | 2,000 | 4 | a textured finish, an entrance, a canopy |
| Heirloom | 4,000 | 7 | a finish with a Temper, an outfit, a celebration |
| Citadel | 8,000 | 15 | a set piece with its own animation |

Other ways to spend Gold: from Phase 3, restoring a finish that has aged with use. Trial rerolls are never sold, for Robux or for Gold. Titles that claim an achievement are earned, never sold.

### 5.5 Gold packs (Developer Products)

| Pack | Default price | Gold | Bonus | Matches |
|---|---|---|---|---|
| Gold Pouch | 5 R$ | 50 | — | the "5 Robux" item |
| Purse | 49 R$ | 500 | — | one Issue item |
| Satchel | 99 R$ | 1,000 + 50 | +5% | one Fine item |
| Coffer | 199 R$ | 2,000 + 200 | +10% | one Masterwork item |
| Chest | 399 R$ | 4,000 + 600 | +15% | one Heirloom item |
| Vault | 799 R$ | 8,000 + 1,600 | +20% | one Citadel piece |

- That works out to about 10 Gold per Robux, or 12 in the Vault. Roblox regionalises the prices, and the UI shows whatever Roblox returns.
- Each pack equals one grade. So "Buy with Robux" on an item (Phase 2) buys the matching pack and spends it on the item straight away. You are never left a few Gold short; the only leftover is the bonus.
- Nothing above 799 R$ at launch. The Chest and Vault go on sale once about 30 items exist to spend them on.
- **Contender's Kit** (149 R$, Phase 2) is a one-time Developer Product: 1,500 Gold, an Issue bow finish and a gesture. It stays on sale until you buy it, with no timer.

### 5.6 The "5 Robux" pocket buys

The user's note: "GAME ENHANCEMENTS - SMALL MONEY 5 ROBUX E.G". Here "enhancements" means conveniences and flourishes. None of them touches the arena.

| Item | Price | What it does |
|---|---|---|
| Gold Pouch | 5 R$ | 50 Gold. Also the right shape for a rewarded-ad reward later |
| Signal Flare | 5 R$ | Fires a coloured flare over the lobby island for everyone; one per server every 30 s |

Each 5 R$ sale earns very little. These items exist to make a first purchase easy, so we keep them to two.

*Lead note (Roadmap): the Trial Reroll is not sold. Daily Trials keep one free reroll a day (the Modes pillar's rule), so the 5 R$ shelf is the Gold Pouch and the Signal Flare.*

### 5.7 Game passes

| Pass | Default price | Grants | Why it isn't pay-to-win |
|---|---|---|---|
| Gauntlet Pass | 499 R$ | The Wardens' Gauntlet (5.8) | New places to play, with the same rules and the same Gold |
| Supporter Crest | 299 R$ | An exclusive Citadel brass finish set and outfit, a crest on your Showcase banner, the lobby title "Supporter" | Looks only |
| Prospector Pass (not at launch) | 249 R$ | +20% Gold from rounds (not from objectives or purchases) | Gold buys only looks (charter 2) |
| Wardrobe Pass | 99 R$ | 8 saved loadouts instead of 2, plus "shuffle my favourites each round" | Convenience |

*Lead note (Roadmap): no Prospector Pass at launch; revisit after a month of economy data.*

The server checks ownership with `UserOwnsGamePassAsync` (wrapped in pcall) on join, and handles new purchases through `PromptGamePassPurchaseFinished`. Ownership is cached for the session, but Roblox stays the source of truth.

### 5.8 Premium access: the Wardens' Gauntlet

The user's note: "PREMIUM GAMEMODE". The user's plan: "Premium Arena — Additional maps, experiences and challenges", with "additional experiences rather than exclusive competitive advantages".

- **What it is.** A premium rotation of extra arenas and curated Warden-challenge rounds, built by the Modes pillar. The free game keeps the Warden events the user asked for ("EVERY COUPLE OF MINUTES A NEW CHALLENGE ARISES"), and the Jubilee Games stay free too.
- **The gate.** The NW lobby pavilion. The server checks the pass before queueing you and again in the destination. Teleport data is never trusted: the source server writes the party list on the server side.
- **Bring a friend.** Each pass holder can bring up to 3 friends per round. That fills 24-player rounds and is the best advert for the pass.
- **Open weekend.** Once a month everyone can play, announced with real dates.
- **Same Gold, same cosmetics, no exclusive power.**

### 5.9 Private servers ("Private Games")

- **Price.** Paid private servers at about 100 R$ a month; Roblox regionalises the price. Roblox Plus members get one free per game, and we're paid for their time in it. Set the price once before launch: changing a private-server price cancels every active subscription.
- **Host panel.** The owner sets:
  - round length
  - border timing
  - loot density
  - Splices and Warden events, on or off
  - minimum players
  - training dummies
  - a "no rewards" switch

  The Modes pillar owns these rules.
- **Rewards.** As in 5.2.
- **Keep owners in their server.** Today the whole loop runs in one place. If premium arenas become separate places, sending private-server owners there cuts their Plus payout time.

### 5.10 Later, if wanted

- **A subscription** that bundles the Gauntlet with a monthly cosmetic.
- **Rewarded video ads** that grant a Gold Pouch, a few times a day.
- **A season reward track.** If we build one, a player on 30 minutes a day must be able to finish it, and its items return to the store a season later.
- **Gifting,** protected by price levels.
- **A Roblox Plus sign-up card.**
- **No trading, ever.**

## 6. Cosmetics

### 6.1 The families, in first and third person

| Family | You (first person) | Everyone else (third person) | Code hook and limits |
|---|---|---|---|
| **Finishes** (weapon and item skins) | The item in your hands wears your finish. `Rig:setItem` → `ItemModels.build(id, "view", finish)` restyles each mesh part by its `Role`: material, MaterialVariant and colour, plus SurfaceAppearance once ItemsReal lands. Press F to inspect. | `InventoryService.attachModel` builds the held model with the holder's finish, and your hotbar icon shows it. A dropped or looted weapon is always the plain model, so loot looks the same to everyone. | Hooks: `ItemModels.build`, `Role` from `ItemAssets`. Same mesh and silhouette; no Neon or glow. |
| **Tempers** (an effect layer) | A small effect near the spine or pommel, at most 8 particles, kept clear of the crosshair. It hides whenever the item hides, so Rig's `setHidden` must also switch emitters. | At most 16 particles, culled beyond 60 studs. Quiet in the arena (no glow, off at night); full strength in the lobby, while inspecting and at the victory. | `ItemModels.build` adds emitters from `Assets.Cosmetics`. Never a light source. |
| **Trails** | Your arrows and thrown knives draw your trail: today's arrow `Trail` with a new colour or texture. A melee swing trail shows only in the Strike window and lasts at most 0.12 s, so it doesn't smear when you turn. | Everyone sees your projectile's trail; `ProjectileController` looks it up by shooter. The swing trail on your weapon's Tip waits for the third-person attack poses from the combat physics work (Roadmap Phase 1) (nothing uses `CombatAction` yet). | Width, length, lifetime and transparency stay as today's arrow trail; only colour and texture change, and never to anything harder to see than today's off-white trail. Movement trails only in the lobby. |
| **Elimination effects** | Plays at the victim when you land the killing blow: scattering ash, rising embers, swirling leaves, or broadcast static with the Cleft sigil. | The victim (in the death camera) and spectators see it. Other living contenders don't, so it gives nothing away. | Hooks: `HitConfirm.killed`, `PlayerService.died`. No blood or red spray, 1.5 s at most, no sound beyond the Knell. |
| **Entrances** (launch plates) | Steam from your tube, a Province banner unfurling behind you, sparks as the plate locks. | Everyone within 140 studs, on the shared rise timeline. | Hook: `LaunchController`. Over when the plate locks, before the horn. |
| **Showcase banner** (our Spire-arrival effect) | Your banner (crest, pose, title) on the Spire's broadcast panels during the Countdown. | The same for everyone; also on the lobby notice boards and the spectate card. | Needs the Spire's broadcast panels (Roadmap Phase 1 set dressing). Nothing fires when you actually reach the Spire in play, because that would tell everyone where you are. |
| **Canopies** | The canopy and flare smoke on Patron capsules sent to you. | Everyone. | Hook: the Arena events pillar's Patron capsules (not built yet). One size, a bright base colour, pattern only; no camouflage canopies. Offering crates keep the Wardens' canopy. Never silver, chrome, white or metallic: silver sponsor parachutes are a source signature. |
| **Outfits** (Province and Citadel) | Your torso and legs (`CharacterVisuals`), plus matching sleeves, cuffs and gloves on your first-person arms (a new `Rig:setSleeves`). | The full avatar, applied when the character loads (`PlayerService.doLoad`). It also shows in the Roll Call busts. | Your own Roblox avatar is the default. Arena-safe palette: no foliage camouflage, no near-black. Never changes body scale or hitbox. |
| **Emotes and gestures** | The camera goes third person while you emote in the lobby. | Everyone. | Hook: `Animate.PlayEmote`. Lobby, spectating and victory: any emote. Arena: gestures only (wave, point, beckon, hand on heart), and only while standing still. |
| **Inspect** | F, DPadRight or a long press on the slot turns the held item in your hands. | Optionally, a short third-person pose. | Hook: `ViewmodelController.Poses`. Not while drawing, swinging or using an item. |
| **Celebrations** | The winner's camera cuts to third person. | Everyone sees a 4–6 s winner camera at Ending, under the victory title: a pose plus an effect (Citadel fireworks, banners from the Spire, the Spire beacon). Then today's summary. Afterwards the lobby's Laureate plinth shows the last winner. | Hooks: `RoundService.endRound`, `NotificationController`, `CameraController`. Ending phase only. |
| **Titles and banners** | — | The lobby nametag and the spectate card. | Titles that claim an achievement are earned, never sold. |

### 6.2 The launch set (about 50 items over Phases 1–2)

| Look | Finishes | Other pieces |
|---|---|---|
| **Ironreach** (iron and steel) | Blued steel with rivets | Foundry coat and leather apron; "spark lock" entrance; Ember Temper |
| **Timberline** (timber) | Carved-ash bow, oiled-haft spear | Waxed-canvas forester outfit; leaf-swirl elimination; resin-amber trail (pine texture on a light core) |
| **Saltmarsh** (salt and fishing) | Bleached driftwood, rope wraps | Oilskin coat; Brine Temper (salt crystals); slate-blue canopy |
| **Graincross** (grain) | Brass fittings, engraved sheaves | Linen harvest outfit; straw-gold trail; banner entrance |
| **Coalbank** (coal) | Blackened steel with brass rivets | Miner's outfit with a lamp; ash-scatter elimination; pale ash trail |
| **The Citadel** | Brass, smoked glass and iron-grey enamel (story-world §3.3) | Tailored iron-grey ceremonial coat with brass rank rings; fireworks celebration; broadcast-static elimination; ochre silk canopy |

The set also has 8 emotes and gestures, 4 Tempers (Ember, Frost, Ash, Brine), banners and titles.

**Temper drops (the user's "EFFECT DROPS"):**
- Once a round, the Wardens may drop a sealed reliquary tin at a random cache spot, marked by a flare.
- The first contender to open it unlocks a Temper they don't own, or 200 Gold if they own them all.
- Earned only and identical in every mode. The odds are listed in the Locker even though the rules don't require it.
- It works as a lure, so it needs coordinating with the Arena events pillar.

*Lead note (Roadmap): the Lure stays the Wardens' only bait drop, so Temper unlocks come from hidden caches instead: a cache sometimes holds a Temper you don't own in place of Gold. Earned only, never sold.*

The gameplay "modifications" from the user's plan (durability, camouflage, arrow types) stay with the Loot pillar (Citadel modifications). They must look physical (a wrapped grip, coloured fletching), never like a cosmetic glow.

### 6.3 Integrity checklist (every cosmetic passes before it ships)

1. Same silhouette, size and hitbox as the plain version.
2. No light source, never brighter than the plain version, and nothing glows in the arena at night.
3. Colours stay inside the arena-safe palette: no foliage camouflage, no near-black, nothing that copies a loot-rarity glow.
4. No added sound louder than the default.
5. It shows nothing others couldn't already see.
6. It finishes before it could matter: entrances end at the plate lock, celebrations happen only at Ending.
7. Reviewed in every biome of every map, including premium maps, at 07:30, 14:30, 19:00 and 22:00, in first and third person, on PC and on a mid-range phone.
8. Never harder to see or trace than the plain version. Trails, capsule smoke, canopies, finishes and outfits keep at least the default's contrast in every biome of every map, including the Gauntlet's winter and coastal arenas, by day, at dusk and at night. No near-white worn items on snow maps, no green, brown or dark-grey arrow trails, and capsule smoke at least as visible as the default orange.

### 6.4 Performance

- **Budget.** The look-dev budget is 25–30 active particle emitters near the camera in total (LookDevPlaybook 7.3). Cosmetics get at most 6 of them within 60 studs, and at most 120 live particles.
- **Setting.** "Cosmetic effects: All / Mine / Off" goes in SettingsController and is saved with the other settings. Below graphics level 4, other players' Tempers are off.
- **No per-frame instances.** Emitters are pooled, the way AudioController pools its voices.

### 6.5 Original-IP guardrails

- Province and Citadel looks are our own designs, and names come from the glossary.
- No salute gestures, bird pins or emblems, burning costumes, parade chariots, or interview gowns that echo the source films.
- The Citadel style is the lore's charcoal wool, brass, smoked glass and iron rings, kept mid-grey for the arena-safe palette: not flamboyant wigs and make-up, and not white uniforms.

## 7. The store and the lobby

### 7.1 The lobby

| Place | What's there |
|---|---|
| NE pavilion: **the Armoury** | Weapon racks with the week's featured finishes under lantern light. An inspect table where your selected weapon turns in a spotlight. Prompt: "Browse finishes". |
| SE pavilion: **the Outfitter** | Mannequins in Province outfits, and a mirror showing your own avatar in the selection. The server builds the mannequin, and your client dresses it. |
| SW pavilion: **the Exchange** | Gold packs, passes, private servers. |
| NW pavilion | The Gauntlet gate (Modes pillar). |
| Central dais: **the Laureate plinth** | The last winner as a statue in their outfit and celebration pose, with a plaque ("LAST STANDING · name · 7 eliminations"). It's built the same way as the Roll Call snapshots. |
| Notice boards | "Orders of the Day" (Daily Trials) and the week's Laureates. |
| Lobby screen | A Gold chip beside the record card, and a STORE button beside SETTINGS (B, DPadLeft or a touch button). |

*Lead note (Roadmap): one lobby plan for every pillar: NE the Armoury, SE the Outfitter (with the Gold and pass counter), SW the Archive (story chapters and Archive Games), NW the Gate (Endless Arena, the Jubilee Games, the Wardens' Gauntlet, Private Games). The fire dais shows Showcase stand-ins during Intermission and the Laureate statue between rounds.*

### 7.2 The STORE screen (`StarterGui.Store`, built by `UIBuilder`, run by a new `StoreController`)

```
STORE  Featured | Weapons | Effects | Outfits | Moments | Locker | Gold | Passes     (o) 2,340 Gold [+]  [X]
+---------------+-------------------------------------+----------------------------------+
| Bow           | [3D card] [3D card] [3D card]       |  large 3D preview (drag to turn) |
| Sword         | [3D card] [3D card] [3D card]       |  [ On its own | In your hands ]  |
| Knife ...     | [3D card] [3D card] [3D card]       |  Coalbank Blackened - Sword      |
| [ ] Owned     |                                     |  Masterwork                      |
|               |                                     |  [ Buy - 2,000 Gold ]            |
|               |                                     |  [ Buy with Robux ]              |
+---------------+-------------------------------------+----------------------------------+
```

- **Cards** show a live 3D view (`ItemModels.renderIcon` with the finish), the name, the grade mark, and the price or OWNED / EQUIPPED.
- **Preview.**
  - "In your hands" draws the real viewmodel `Rig` holding the item inside a ViewportFrame, so you see exactly what first person will show.
  - Moments play on a small plate or a mannequin.
  - Outfits play in the Outfitter mirror.
- **Buying.**
  - Gold opens our own confirmation: "Spend 2,000 Gold on Coalbank Blackened (Sword)? 340 Gold left."
  - Robux opens Roblox's prompt, only after a click.
  - Prices come from `GetProductInfoAsync`.
  - From Phase 2, a Gold purchase can be returned within 10 minutes.
- **Locker.** Equip per slot and per weapon. If you're in a round, changes apply from the next round.
- **Featured shelf.** Rotates weekly, shows the true end date, and items come back later.
- **Devices.**
  - Gamepad: LB/RB switch tabs, the D-pad moves through the grid, A buys, X previews, B goes back.
  - Touch: two columns, 44 px targets.
  - Phone: the preview sits on top.
- **Where it opens.** Only outside the arena: in the lobby, after death, or while spectating.

### 7.3 Words and prompts

- Buttons say "View item", "See price", "Buy", "Equip".
- Never "Last chance" or "Act now", and no "was/now" prices that aren't real.
- No pop-ups. A purchase prompt opens only after a click.
- The death screen shows what you earned, never what you could buy.

## 8. The player profile

### 8.1 Schema (v2)

```lua
-- DataStore "Profiles_v2", key "u_<UserId>", session-locked, under 30 KB
{
  v = 2, created = 0, importedV1 = false,
  stats    = { wins = 0, kills = 0, rounds = 0, top5 = 0, secondsAlive = 0 },
  settings = { --[[ today's keys ]] cosmeticFx = "All" },
  wallet   = { gold = 0, earned = 0, bought = 0, spent = 0 },     -- lifetime totals
  owned    = { ["fin.bow.timberline"] = 0 },                      -- id -> time acquired
  equipped = { finish = { bow = "fin.bow.timberline" }, temper = {}, trail = false, swing = false,
               elimination = false, entrance = false, banner = false, canopy = false, outfit = false,
               celebration = false, emotes = { false, false, false, false } },   -- false, never nil holes
  loadouts = {},                                                   -- Wardrobe Pass
  daily    = { day = 0, objectives = {}, rerolls = 0, firstRound = false, firstWin = false, roundGold = 0 },
  weekly   = { week = 0, missions = {} },
  feats = {}, caches = {}, oneTime = {},                           -- achievements, found caches, kits
  intents  = {},                                                   -- Phase 2: [productId] = { item, at }
  receipts = { ids = {}, order = {} },                             -- last 200 PurchaseIds: { t, product, robux }
  ledger   = {},                                                   -- last 100: { t, kind, amount, balance, ref }
}
```

### 8.2 Versions and migration

- **Versions.** `v` is the schema version, and migrations run in order on load. A server that finds a newer `v` than it knows opens the profile read-only and asks the player to rejoin, so an old server never downgrades data.
- **New store.** The profile moves to `Profiles_v2`, key `u_<UserId>`. On its first load it copies Wins, TotalKills, RoundsPlayed and Settings from `PlayerStats_v1` once, then sets `importedV1`.
- **Release.** Ship it with a server restart, so no old server writes v1 afterwards. v1 stays as a read-only backup.
- **No caller changes.** `DataService.increment`, `get` and `setSettings` keep working, so RoundService and the settings menu don't change.

### 8.3 Session lock and saving

- **The lock.** Use either ProfileStore (an open-source, MIT-licensed session-locking library) or Roblox's reference wrapper:
  - The lock id sits in the key's metadata, written by the same `UpdateAsync` that reads the data.
  - Autosave refreshes the lock; leaving or `BindToClose` releases it.
  - Requests queue per key and retry with exponential backoff and jitter.
- **When another server holds it.** Show "Loading your profile…" and retry for up to about 30 s. Never play on a profile this server doesn't hold, and purchases wait for the lock.
- **Saving.** Autosave every 60–120 s, with a random offset per player. Save at once after a Robux grant or a Gold spend over 1,000.
- **Erasure requests.** Attach the player's UserId to the key so Roblox's data-erasure requests find it.
- **Size.** Under 30 KB (the limit is 4 MB), well inside the request budget.

### 8.4 Robux purchases and passes

`StoreService` holds the game's only `ProcessReceipt`:

1. Is the buyer in this server? If not, return `NotProcessedYet`.
2. Check the receipt: PlayerId, ProductId, and that its status is Open. Grant only Open receipts (current developer-products doc).
3. Wait up to 15 s for their profile, and stop if they leave. If it doesn't load, return `NotProcessedYet`.
4. Is this PurchaseId already recorded? If it's saved, return `PurchaseGranted`; if not saved yet, `NotProcessedYet`.
5. Look up the product in `Shared.StoreCatalog`. If it's unknown, log it and return `NotProcessedYet`.
6. Grant in memory: Gold, a pending "Buy with Robux" item (Phase 2), or a one-time bundle. If the player already owns the item, give its Gold value instead.
7. Record the PurchaseId (the last 200 are kept), the Robux actually paid, and a ledger line.
8. Save now. On success return `PurchaseGranted`; on failure, `NotProcessedYet`.

- **Bought outside the game.** Listed Gold packs can also be bought outside the game, in the Store tab of the experience's page. Step 1's `NotProcessedYet` holds those grants until the buyer's next join.
- **In Studio without API access:** grant for the session only, return `PurchaseGranted` and warn once. Studio test purchases are free.
- **Passes:** check `UserOwnsGamePassAsync` on join and handle `PromptGamePassPurchaseFinished`, caching ownership for the session.
- **"Buy with Robux" (Phase 2):** the server saves an intent (product → item) before showing Roblox's prompt. The receipt uses that intent, or simply leaves the Gold in the wallet if there's none.

### 8.5 Anti-exploit

- **The client sends intents only:** `StoreRequest { requestId, op, itemId }` and `EquipCosmetic { slot, id }`. Never prices or amounts.
- **The server checks every request:**
  - the item exists and is sold for Gold
  - the player doesn't already own it and has enough Gold
  - the player is outside the arena
  - only one transaction per player runs at a time
  - `Net.rateLimit` allows 4 a second, burst 8
  - a repeated requestId is ignored
- **Gold comes only from events the server saw itself:** placements, kill credit, objective triggers.
- **Equips** are checked against ownership and frozen from Countdown to Ending.
- **Balances** use whole numbers and never go negative. A ledger of the last 100 changes helps support.
- **Flags for review:** more than 6,000 Gold earned in a day, or repeated kills on one player in small lobbies.
- **No trading,** and teleport data is never trusted.
- **Cosmetic choices** replicate as a small public `Player.Cosmetics` attribute. A cheater can fake only their own screen.

### 8.6 Analytics and tuning

- Every Gold source and sink calls `AnalyticsService:LogEconomyEvent`, with transaction types IAP, Gameplay, Shop and Onboarding and the cosmetic id as the item SKU. That feeds Roblox's Economy dashboard.
- Custom events track the store funnel: opened, previewed, bought.
- All numbers live in `Config.Economy` and `Shared.StoreCatalog`. Review them weekly for the first month.

## 9. Code plan

| Where | Change |
|---|---|
| `Services.DataService` (extend) | Profile v2: session lock, schema, the v1 import, and the wallet / ownership / equip API (`whenLoaded`, `getGold`, `grantGold(player, n, source, ref)`, `trySpendGold`, `owns`, `grantCosmetic`, `setEquipped`, `saveNow`), plus receipts and the ledger. Keeps `increment`, `get` and `setSettings`. |
| `EconomyService` (new) | Round rewards from `RoundService.endRound` / `roundEnded` and `PlayerService.died`, the fair-play limits, daily bonuses, caches. Sends each player their reward breakdown through `ProfileUpdate`. |
| `StoreService` (new) | The only `ProcessReceipt`; passes; `StoreRequest` / `StoreResult`; intents; analytics. |
| `CosmeticsService` (new) | Equips, the `Player.Cosmetics` attribute, outfits on load (through a `PlayerService` hook), `CosmeticEvent` for eliminations and celebrations. |
| `Shared.Cosmetics`, `Shared.StoreCatalog`, `Config.Economy` (new) | The catalogue (id, slot, grade, Gold price, assets, first- and third-person effect profiles), product and pass ids, and every economy number. |
| `Shared.ItemModels` (extend) | `build(itemId, variant, finishId?)` and `renderIcon(viewport, itemId, finishId?)`. |
| `ViewmodelController`, `Rig`, `Poses` (extend) | Pass your finish; add `setSleeves`; switch Temper emitters in `setHidden`; add the Inspect pose. |
| `InventoryService.attachModel`, `HUDController` (extend) | Build the held model with the holder's finish; show the finish on the hotbar icon. |
| `ProjectileController`, `CombatController` (extend) | The trail by shooter; the swing trail in the Strike window. |
| `LaunchController`, `NotificationController`, `CameraController` (extend) | Entrances; the rewards line; the winner camera and celebrations. |
| `PlayerService.doLoad` (extend) | Apply the equipped outfit to the description copy before the character loads. |
| `LobbyController`, `UIBuilder`, `StoreController` (new) | The Gold chip, the STORE button, `StarterGui.Store`. |
| `WorldGen.CosmeticAssets` (new), `Populate.Lobby` (extend) | Builds `ReplicatedStorage.Assets.Cosmetics` so it can be rebuilt any time; pavilion interiors; the Laureate plinth. |
| `Remotes`, `Net.Names`, GameDesign sections 8–10 | The `StoreRequest`, `StoreResult`, `EquipCosmetic`, `ProfileUpdate` and `CosmeticEvent` remotes; the `Cosmetics` attribute. |

## 10. Phases

| Phase | Ships | Depends on | Size |
|---|---|---|---|
| **1 — Wallet and Armoury** (the first slice) | Profile v2, Gold from rounds, the Gold Pouch, Purse, Satchel and Coffer, the Gold store, 6 finishes, 3 arrow trails, STORE v0, the Armoury | — | L (about 2 weeks) |
| **2 — Cosmetic depth** | Tempers (their unlocks come from hidden caches), swing trails, elimination effects, entrances, the Showcase banner, outfits and sleeves, emotes and Inspect, celebrations and the Laureate plinth, "Buy with Robux", the Contender's Kit, the Chest and Vault, the Signal Flare, two passes (the Supporter Crest and the Wardrobe Pass), private servers | The third-person attack poses from the combat physics work (Roadmap Phase 1); the Modes pillar's Daily Trials; world art's Spire panels; the ItemsReal meshes keeping their `Role` names | XL (6–8 weeks, mostly art) |
| **3 — Premium and live** | The Gauntlet Pass and its gate, canopies, events, Patina (finishes that age with use, earned in play), and optionally a subscription, ads and a season track | The Modes pillar's premium arenas; the Arena events pillar's Patron capsules | L |

## 11. First slice: Wallet and Armoury (L, about 2 weeks)

1. **DataService profile v2:**
   - The `Profiles_v2` store with a session lock and the v2 schema.
   - A one-time import from `PlayerStats_v1`.
   - The wallet, ownership and equip API; today's API keeps working.
2. **EconomyService:**
   - Gold for taking part, placement, eliminations and the win, with the fair-play limits.
   - A "+N Gold" breakdown on the death and victory screens.
   - The Gold chip in the lobby.
3. **StoreService:**
   - One `ProcessReceipt` and four Developer Products: Gold Pouch 5 R$, Purse 49 R$, Satchel 99 R$, Coffer 199 R$.
   - Gold purchases and equips through the new remotes, with rate limits and economy analytics.
4. **Cosmetics v0:**
   - Six finishes:
     - bow: Timberline Ash (Fine), Citadel Brass (Masterwork)
     - sword: Coalbank Blackened (Fine), Ironreach Blued (Masterwork)
     - knife: Saltmarsh Driftwood and Graincross Brass (both Issue)
   - Three arrow trails: Resin, Ember, Citadel Brass.
   - Each finish is a per-`Role` material, MaterialVariant and colour, so it survives the ItemsReal mesh swap.
   - Wired into `ItemModels`, `Rig:setItem`, `InventoryService.attachModel`, the hotbar icons and `ProjectileController`. Dropped weapons stay plain.
5. **STORE v0:**
   - Weapons, Trails, Gold and Locker tabs, with 3D previews including "In your hands".
   - Prices from Roblox and the Gold confirmation.
   - The STORE button (B, DPadLeft, touch) and a prompt in the Armoury.

**Done when:**
- A round's Gold shows on the death or victory screen and is still there after a rejoin.
- A bow finish bought with Gold appears in first person on any bow you pick up. A second player sees it in your hand, and a dropped bow is plain.
- A Studio test purchase of the Purse grants 500 Gold exactly once, even when the handler runs twice with the same PurchaseId.
- A purchase made while the profile is still loading waits, then lands.
- Two servers can't hold the same profile.
- No Robux price is hard-coded.
- The phone, gamepad and PC layouts pass the existing UI layout check.

**Not in the slice:** Tempers, outfits, moments, passes, "Buy with Robux", private servers, premium.

---

## Checklist items in this pillar

Status, size and Roadmap phase match the master checklist in the [Roadmap](../Roadmap.md).

### 28. “Gold currency”

- **Our name:** Gold
- **Status:** Not started · **Size:** L · **Roadmap phase:** 6a
- **Pillar phase:** Phase 1 — Wallet and Armoury (first slice)
- **From the notes:** Raw notes: “IN GAME CURRENCY - GOLDS”. Plan 7.1–7.2: Gold is “earned through gameplay and used for ordinary purchases”, from wins, missions, daily objectives, achievements, hidden supplies, campaign chapters and special events. Our name: Gold, the one soft currency. It's earned from rounds (taking part, placement, eliminations, the win), Daily Trials, Season challenges, Achievements, hidden caches, story chapters and events, and spent only on cosmetics and small conveniences. It's kept in a session-locked profile with a ledger.
- **Evidence:** script_grep “Gold” finds only Theme.Colors.Gold (226,186,110), used as a text colour in NotificationController and UIBuilder. DataService saves only Wins, TotalKills, RoundsPlayed and Settings to DataStore PlayerStats_v1 (key Player_<UserId>): UpdateAsync deltas, a 120 s autosave, BindToClose, Version = 1, no session lock. Hooks to build on: RoundService.endRound (placements, kills, the 15 s or a kill walkover rule) and PlayerService.died (kill credit).

### 29. “Buying Gold with Robux”

- **Our name:** Gold packs (StoreService)
- **Status:** Not started · **Size:** M · **Roadmap phase:** 6a
- **Pillar phase:** Phase 1 — Wallet and Armoury (first slice)
- **From the notes:** Raw notes: “BUY CURRENCY WITH ROBUX”. Our name: Gold packs, sold as Developer Products. A new StoreService grants them through one ProcessReceipt that never grants twice. PurchaseIds are stored in the profile and saved before PurchaseGranted is returned.
- **Evidence:** No script uses MarketplaceService, ProcessReceipt or PolicyService. The 22 RemoteEvents in ReplicatedStorage.Remotes are all gameplay, and StarterGui has no store GUI.

### 30. “Small purchase packages”

- **Our name:** Purse and Satchel (plus the Contender's Kit)
- **Status:** Not started · **Size:** S · **Roadmap phase:** 6a
- **Pillar phase:** Phase 1 — Wallet and Armoury (the Kit in Phase 2)
- **From the notes:** Raw notes: “TYPES OF EXPENSES / SMALL PACKAGE ETC”; plan 7.3 “Small Gold packages”. Our names: the Purse (49 R$, 500 Gold) and the Satchel (99 R$, 1,000 + 50 Gold). Later, a one-time Contender's Kit (149 R$: 1,500 Gold, a bow finish and a gesture).
- **Evidence:** No developer products or MarketplaceService anywhere in the place, and no Gold to grant.

### 31. “Medium and large packages”

- **Our name:** Coffer, Chest and Vault
- **Status:** Not started · **Size:** S · **Roadmap phase:** 6a → 6b
- **Pillar phase:** Phase 1 (the Coffer); Phase 2 (the Chest and Vault, once about 30 items are on sale)
- **From the notes:** Plan 7.3 “Medium Gold packages” and “Large Gold packages”. Our names: the Coffer (199 R$, 2,000 + 200), the Chest (399 R$, 4,000 + 600) and the Vault (799 R$, 8,000 + 1,600). Each pack equals one cosmetic grade, so buying an item with Robux never leaves the player short. Nothing above 799 R$ at launch.
- **Evidence:** No developer products and no currency exist (see Gold currency).

### 32. “5 Robux microtransactions”

- **Our name:** Pocket buys: Gold Pouch and Signal Flare (the Trial Reroll is not sold)
- **Status:** Not started · **Size:** S (pillar estimate: M) · **Roadmap phase:** 6a → 6b
- **Pillar phase:** Phase 1 (the Gold Pouch); Phase 2 (the Signal Flare)
- **From the notes:** Raw notes: “GAME ENHANCEMENTS - SMALL MONEY 5 ROBUX E.G”. Our name: pocket buys at 5 R$. The Gold Pouch gives 50 Gold and can later double as a rewarded-ad reward. The Signal Flare fires a coloured flare over the lobby. The Trial Reroll is free once a day; the lead dropped the paid reroll. Here “enhancements” means conveniences and flourishes, never arena boosts.
- **Evidence:** No developer products exist. Daily Trials don't exist yet; they belong to the Modes pillar.

### 33. “Premium game access”

- **Our name:** The Wardens' Gauntlet (Gauntlet Pass)
- **Status:** Not started · **Size:** M · **Roadmap phase:** 9
- **Pillar phase:** Phase 3 — Premium and live (needs the premium arenas)
- **From the notes:** Raw notes: “PREMIUM GAMEMODE”; plan 8: “Premium Arena — Additional maps, experiences and challenges”, offering “additional experiences rather than exclusive competitive advantages”. Our name: the Wardens' Gauntlet, a premium rotation of extra arenas and curated Warden-challenge rounds. The Modes pillar builds the content; the Gauntlet Pass (499 R$) unlocks it. Each holder can bring up to 3 friends, there's a monthly open weekend, and the Gold and rules are the same. Warden events and the Jubilee Games stay free.
- **Evidence:** There is one place and one round loop (RoundService). The only other mode is Practice (GameState.Practice when a single contender starts, i.e. Studio solo). No TeleportService, passes or reserved servers anywhere.

### 34. “Game passes”

- **Our name:** Gauntlet Pass, Supporter Crest and Wardrobe Pass (no Prospector Pass at launch; revisit after a month of economy data)
- **Status:** Not started · **Size:** M · **Roadmap phase:** 6b → 9
- **Pillar phase:** Phase 2 — Cosmetic depth (the Gauntlet Pass in Phase 3)
- **From the notes:** Plan 7.3 “Premium game passes”. Our names: the Gauntlet Pass 499 R$ (premium arenas), the Supporter Crest 299 R$ (an exclusive Citadel brass set, a crest and a title) and the Wardrobe Pass 99 R$ (8 saved loadouts and a shuffle of favourites). The Prospector Pass 249 R$ (+20% round Gold) is not offered at launch. All are lasting privileges; none touches combat or survival.
- **Evidence:** No script uses UserOwnsGamePassAsync or PromptGamePassPurchaseFinished.

### 35. “Visual effects for items”

- **Our name:** Finishes and Tempers
- **Status:** Not started · **Size:** L · **Roadmap phase:** 6a → 6b
- **Pillar phase:** Phase 1 (Finishes); Phase 2 (Tempers, with Temper unlocks in hidden caches)
- **From the notes:** Raw notes: “BUY VISUAL EFFECTS FOR ITEMS”; plan 6: “Cosmetic modifications — Weapon appearances, visual trails and effects”. Our names: Finishes (per-part material and colour, later textures, for weapons and items) and Tempers (a quiet effect layer: Ember, Frost, Ash, Brine). Temper unlocks come from hidden caches (earned only, never sold). Gameplay modifications stay with the Loot pillar (Citadel modifications).
- **Evidence:** The hooks exist. Shared.ItemModels.build(itemId, variant) is the one builder for the first-person item (ViewmodelController.Rig:setItem → "view"), the held model others see (InventoryService.attachModel → "world"), arrows and icons. WorldGen.ItemAssets puts a Role attribute on every mesh part. Today's meshes have no textures (material and colour come from the Manifest).

### 36. “Weapon effects”

- **Our name:** Elimination effects
- **Status:** Not started · **Size:** M · **Roadmap phase:** 6b
- **Pillar phase:** Phase 2 — Cosmetic depth
- **From the notes:** Plan 7.4 “Weapon elimination effects”. Our name: Elimination effects (scattering ash, rising embers, swirling leaves, broadcast static with the Cleft sigil), seen only by the killer, the victim and spectators. Also strike-spark colours and kill-marker styles.
- **Evidence:** Only the default impact particles (ProjectileController.impactEffect) and the HUD hit and kill markers from HitConfirm exist. The triggers are ready: HitConfirm.killed on the client and PlayerService.died on the server.

### 37. “Trails”

- **Our name:** Trails
- **Status:** Not started · **Size:** M · **Roadmap phase:** 6a → 6b
- **Pillar phase:** Phase 1 (arrow trails); Phase 2 (swing trails)
- **From the notes:** Raw notes: “TRAILS ETC”; plan 7.3/7.4 “Trails”, “Special weapon trails”. Our name: Trails, for arrows and thrown weapons, melee swings, and movement (lobby only). A trail can change colour and texture, never size or brightness.
- **Evidence:** A default trail exists: ProjectileController gives every arrow a faint off-white Trail (Lifetime 0.16 s, LightEmission 0.25). It builds shots from ProjectileFired, which names the shooter, so swapping the trail per shooter is a small change. Swing hooks: CombatController.action (Strike). Nothing uses the CombatAction remote in third person yet.

### 38. “Character skins”

- **Our name:** Province outfits and Citadel couture
- **Status:** Not started · **Size:** XL · **Roadmap phase:** 6b
- **Pillar phase:** Phase 2 — Cosmetic depth
- **From the notes:** Plan 7.3 “Character cosmetic packages”; 7.4 “District-themed clothing” and “Capitol-themed outfits”. Our names: Province outfits (Ironreach, Timberline, Saltmarsh, Graincross, Coalbank) and Citadel couture, with matching first-person sleeves, cuffs and gloves. The player's own Roblox avatar stays the default.
- **Evidence:** PlayerService.doLoad loads each character from the player's own HumanoidDescription; scales are normalised now, and Part 2 removes that. The first-person arms use fixed colours in ViewmodelController.Rig (SLEEVE 47,51,57; CUFF 70,64,56; fists via setSkin). CharacterVisuals shows your torso and legs in first person. FallenSnapshots builds the Roll Call busts from GetAppliedDescription, so outfits will show there.

### 39. “Animations”

- **Our name:** Emotes, gestures and Inspect
- **Status:** Partly built · **Size:** M · **Roadmap phase:** 6b
- **Pillar phase:** Phase 2 — Cosmetic depth
- **From the notes:** Plan 7.3 “Victory animations”; checklist “Animations”. Our names: Emotes and gestures (any in the lobby, gestures only in the arena), an Inspect animation for finishes, and victory poses. No locomotion packs: everyone keeps moving the same realistic way.
- **Evidence:** StarterCharacterScripts.Animate keeps the emote wheel through a PlayEmote BindableFunction: 7 stock Roblox emotes, only when grounded and still, and it accepts Animation objects. It deliberately ignores avatar animation packs. Nothing is owned or unlockable, and there is no Inspect.

### 40. “Victory effects”

- **Our name:** Celebrations, Entrances and the Showcase banner
- **Status:** Not started · **Size:** L · **Roadmap phase:** 6b
- **Pillar phase:** Phase 2 — Cosmetic depth
- **From the notes:** Plan 7.4 “Victory celebrations”, “Character entrance effects”, “Unique Cornucopia spawn animations”. Our names: Celebrations (a winner camera at Ending with a pose and an effect), Entrances on the launch plates, the Showcase banner on the Spire's panels during the Countdown, and the Laureate plinth in the lobby.
- **Evidence:** Ending shows a 2D victory screen (NotificationController, with a special version for the winner) and the RoundSummary table; RoundService.endRound knows the winner and placements. LaunchController plays the same whir, clunk, light and dust for every plate within 140 studs, with nothing per player. The Spire has no display surfaces: only the NoticeBoard and Props builders create SurfaceGuis.

### 41. “Parachute effects”

- **Our name:** Canopies
- **Status:** Not started · **Size:** M · **Roadmap phase:** 6b
- **Pillar phase:** Phase 3 — Premium and live (after Patron capsules)
- **From the notes:** Plan 7.4 “Special parachute effects”. Our name: Canopies (plus the flare-smoke colour) on Patron capsules sent to you: one size, a bright base colour, pattern only, never silver, chrome, white or metallic. Offering crates keep the Wardens' canopy.
- **Evidence:** No script has a parachute. Offering crates fall 55 studs in 1.1 s with an ember PointLight (LootService.dropCrateIn). Patron capsules don't exist yet; they belong to the Arena events pillar.

## Open questions

1. In the arena, should contenders wear their own avatar or chosen outfit (recommended, and what Roblox players expect)? Or a standard-issue arena uniform with personal accents? That's truer to the genre and fairest, and outfits would then show only in the lobby, the Showcase, the launch, the victory and the Roll Call. *(Settled by your earlier call: players keep their own Roblox avatars, at normal proportions.)*
2. Should every cosmetic be earnable with Gold (recommended)? Or do you want some Robux-only exclusives, such as the Supporter Crest set or occasional Citadel couture bundles?
3. Premium mode: a one-time Gauntlet Pass at about 499 R$ (recommended), a monthly subscription, or both? And can you confirm that the Jubilee Games and Warden events stay free for everyone? *(Roadmap: decision 5.)*
4. Should we include the Prospector Pass (+20% Gold from rounds)? It never touches combat, but some players see Gold boosts as paying to progress. *(Settled by the lead: no Prospector Pass at launch; revisit after a month of economy data.)*
5. Which 5-Robux items do you want: just the Gold Pouch, or the Signal Flare and the Trial Reroll as well? *(Settled in part: the Gold Pouch and the Signal Flare; no paid reroll.)*
6. Gold value and pack ladder: about 10 Gold per Robux, packs at 5 / 49 / 99 / 199 / 399 / 799 R$, and nothing bigger at launch. Is that the right top end?
7. Your 'effect drops': is it OK to make them earned-only Temper drops (a rare tin the Wardens drop in the arena)? That means the game never sells random items, so no loot boxes. *(Settled: effect drops are the Loot pillar's Citadel modifications; Temper unlocks come from hidden caches.)*
8. Private servers: what monthly price (we suggest about 100 R$)? And should private rounds pay any Gold (we suggest a quarter of the taking-part Gold, at most 200 a day, and no objective progress)? *(Settled in part: private rounds pay no Gold; the price is still open.)*
9. Story mode: should arcs and playable characters ever be sold as premium content, or only unlocked by playing? Their abilities are never sold either way. *(Roadmap: decision 6.)*
10. Rewarded video ads: yes or no? Players would watch an ad for a Gold Pouch a few times a day. Roblox decides at runtime which players can see ads (`GetAdAvailabilityNowAsync`). The game must be public and unrestricted, with an approved maturity questionnaire, no free-form creation and an average of 2,000 unique visitors a month. The reward must be a non-random developer product granted right after the ad; the Gold Pouch fits.
11. Names: are Gold, Finishes, Tempers, the Wardens' Gauntlet, the Supporter Crest, the pack names (Pouch to Vault) and the cosmetic grades (Issue to Citadel) right, or would you like others? *(Anything can be renamed later.)*

## Risks

- Money bugs: a wrong session lock or receipt handler can duplicate or lose purchases. That means refunds, angry players, and Roblox flagging the game's ProcessReceipt. Use a proven lock (ProfileStore or Roblox's reference wrapper), store PurchaseIds and save before PurchaseGranted. Run the duplicate-receipt, server-kill and two-server tests before any product goes live.
- Data migration: moving off PlayerStats_v1 could lose or double stats if an old server keeps writing. Import once and flag it, release with a server restart, and keep v1 read-only as a backup.
- Other teams are editing the same code right now. The viewmodel Rig was rebuilt while this review ran, and Part 2 changes how PlayerService loads avatars and swaps the item meshes. Keep our hooks small and additive, and ask whoever integrates ItemsReal to keep the Role names that finishes depend on.
- Pay-to-win drift: camouflage outfits, weapons that glow at night, longer, louder or harder-to-see trails, or Gold that buys Talents or Patron capsules would break fairness and the user's own rule. The charter and the integrity checklist are the gate, and every cosmetic gets reviewed in all biomes by day and by night.
- A premium mode splits a 24-player game. Launch the Gauntlet only when there are enough players to fill both, and use bring-a-friend and open weekends.
- Young players: a Moderate game can reach ages 9 to 15 through Roblox Select once it passes Roblox's all-ages evaluation. Pressure tactics, fake sales or paid random items would break Roblox's rules and the brief. The store wording rules and selling nothing random remove the biggest risks.
- Economy balance: if rewards are too generous, Gold inflates and nobody buys; if too stingy, players feel forced to pay. Farming in small or private lobbies, and bots, are the main leaks. Manage it with the Config.Economy settings, the caps and the Economy dashboard, reviewed weekly.
- Managed pricing changes Robux prices by region and over time, so any Robux number typed into the UI will be wrong. Fetch prices from Roblox at runtime and run Roblox's Dynamic Price Check.
- Performance: up to 24 players' effects, seen in first person on phones. Keep to the emitter budget, cull by distance, add the All / Mine / Off setting, and switch other players' effects off on low graphics.
- Art workload: outfits with layered clothing and textured finishes are the slowest part, and every upload needs moderation. Start with material-and-colour finishes and particle Tempers, and upload each asset once and reuse its id.
- Original IP: Province and Citadel costumes or celebrations could drift toward the films' look. Review the art against the hard-rule list before upload.
- If the Gauntlet lives in a separate place, private-server owners get teleported out, which cuts the Roblox Plus private-server payout. Prefer hosting it in the same place, or accept the loss knowingly.
- First-person effects move with the camera: the viewmodel parts are anchored and moved with BulkMoveTo every frame, so long trails smear across the screen on fast turns. Keep swing trails to the strike window with lifetimes under 0.12 s, and test them with fast mouse turns.
