# Shop research: what comparable Roblox games sell, and a proposal for #ARENA 48 (19 Nov 2026)

Research only. No game file changed. Sources were read on 19 Nov 2026; the date in each row is the page's own date or "last updated" stamp. Third-party wikis and guides are not official, and Robux prices in them can be out of date or regional. Prices below are **default prices**: Managed Pricing and the Roblox Plus discount change what each player sees, so the game must read prices from Roblox (RandomItemRules §7).

## 0. In short

- **The owner's five reference screenshots look like Hypershot** (Frosted Studio). Its cases are Wooden, Bronze, Silver, Gold and Diamond at 5,000 / 10,000 / 20,000 / 30,000 / 40,000 Coins, and the reference shows Wooden at 5,000. It also has Coins plus Gems, a "Lucky" pass that raises case odds, kill effects, kill icons, banners, passive spins and a Diamond case (the reference daily reward shows "2x Passive Spins", "1,000 Gems" and "x1 Diamond"). This is a strong match, not proven: no source shows those exact screens. Hypershot had about 13K players on 17 Nov 2026, the 2nd biggest Roblox shooter after RIVALS (about 70K that day, peak 967K).
- **What the winners sell:** cosmetic-only power-free items (skins, wraps, charms, finishers/kill effects, emotes, banners, titles), sold three ways: direct (a daily or featured shop), a season pass with a free and a paid track, and random cases. Cases cost about 249 R$ each in RIVALS and are also openable with an earned currency (Skin Tickets). Passes cost 399 to 799 R$. Starter packs cost 49 R$.
- **The two things to decide first** (section 3.0):
  1. Can Gold be bought with Robux? Today it cannot (`Config.Economy.RobuxGold = false`), so the wheel and Strongboxes are not paid random items.
  2. Does the owner want a **paid luck boost** like the reference's clover? A luck boost bought with Robux is itself a paid random item modifier. It turns every case it touches into a regulated paid random item, whatever currency opens the case. That means odds shown live with the boost, PolicyService gating, a Yes on the questionnaire, and an earnable or direct-buy path for restricted players (UK under 18, Brazil, and others).
- **A trap found in the rules:** a pack that contains any random item is itself a paid random item (RandomItemRules §1, "Bundles"). So a **premium pass or starter pack that includes cases is a PRI** too. My proposal keeps cases on the free track only and puts fixed items on the paid track.
- **Conflict to settle:** the economy pillar (economy-cosmetics.md, charter rules 2 and 3) says "power is never for sale" and "nothing random is for sale". The owner now asks for cases and a paid luck boost. The cosmetics below never change stars, damage or anything in a fight, so rule 2 holds. Rule 3 holds only under Option A (section 3.0).

## 1. What comparable games sell, and how

### 1.1 The games (players on the dates shown)

| Game | Genre | Players | Money model, in one line |
|---|---|---|---|
| RIVALS (Nosniy Games) | 1v1 to 5v5 FPS duels | 70.3K on the shooter chart (bloxodes, about 17 Nov 2026); about 222K at a June 2026 snapshot; peak 967,342 | Keys (earned) buy weapons; skins come from 249 R$ cases or 10 Skin Tickets; Season Pass; daily shop of wraps, charms and finishers for Keys; 22+ bundles; ranked with ELO |
| Hypershot (Frosted Studio) | Arena FPS with abilities and passives | 12.8K to 13K (17 Nov 2026), 1.4B visits | Coins buy Wooden-to-Diamond cases; Gems buy abilities; passives come from spins earned by play; 10 game passes 49 to 975 R$, including "Lucky" (149 R$) for better case odds |
| BloxStrike | CS-style shooter | 5.7K | Cases opened with earned Credits; knife skins are cosmetic |
| Arsenal | Arcade FPS | 1.9K now (6.3B visits; it used to be a top game) | Cases for in-game Bucks or coins; a Flair crate with kill effects, announcers and emotes; a season pass |
| Murder Mystery 2 | Social-deduction knife and gun | about 199K (June 2026) | Event passes bought with event currency (25 to 30 tiers); a chroma variant at about 2% on the last tier; traded knife economy |
| Blade Ball | Melee-parry arena | not on the shooter chart | Sword and explosion (kill effect) crates for coins or Robux; premium crate 100 R$ a roll; a 480 R$ premium pass and 1,800 to 2,399 R$ "skip all levels" |
| BedWars | Team PvP | not on the shooter chart | 799 R$ battle pass with kill effects, win effects, lobby gadgets, emotes and titles; kits for 399 R$ or 10,000 BedCoins |
| Combat Warriors | Melee PvP | not found | Credits and Aether; skins, kill effects and enchants; one daily spin from level 10; spins and credits sold for Robux |
| One Tap, Deagle Arena, Sniper Arena, Knife Duels, Murder Duels | Small FPS and duel games | 4K to 8K each | Copies of the RIVALS model: cases, a daily shop, kill effects |

### 1.2 Currencies

- **Two currencies is the norm.** One is earned in play (Coins, Keys, Credits). A second, slower one buys the good things: Gems (Hypershot), Skin Tickets (RIVALS), Aether (Combat Warriors). Event currencies (Candy, Crystals, Pearls in RIVALS; Candies and Snow Tokens in MM2) appear for a few weeks, then convert into an event chest.
- In RIVALS, **Robux mostly buys the case or the item directly**, not the soft currency. Keys come from contracts, tasks, codes and bundles. That keeps the earned currency honest.

### 1.3 Cases

| Game | Case | Price | Odds shown |
|---|---|---|---|
| Hypershot | Wooden / Bronze / Silver / Gold / Diamond | 5,000 / 10,000 / 20,000 / 30,000 / 40,000 Coins; Gold and Diamond also come in 49 to 799 R$ packs | Per rarity, split into weapon skin 90% and knife skin 10%, plus a "Collector's Edition" line (the owner's reference). The Lucky pass gives no number in the guide. The reference's clover (54 R$) does: "1 in 3 cases roll twice, keep best rarity" |
| RIVALS | Skin Case 1, 2, 3 (44 skins each); seasonal Spooky, Festive and Summer cases | 249 R$ or 10 Skin Tickets; 3 for 724 R$ (about 3% off) | Common, Rare and Legendary. The in-game viewer shows exact rates, for example 2.94% for each Legendary in Skin Case. Duplicates can happen. Some regions cannot open cases |
| RIVALS | Wrap Box (5 Keys), Charm Capsule (3 Keys), Finisher Pack (10 Keys) | Earned Keys | One random item from the pool |
| Blade Ball | Premium explosion crate | 100 R$ a roll (about 80% Rare, 20% Legendary); seasonal crates list each item, down to 0.01% | Per item |
| Arsenal | Cases | 600 / 900 / 1,200 Bucks (old guide) | Not found |

**Pity.** No source documents a pity system in these games. Our own Strongboxes already have one: a 4-star by the 8th box and a 5-star by the 40th (Rewards.lua).

**Luck boosts.** Hypershot sells one for 149 R$ with no published number. A DevForum thread calls "2x luck" stickers that hide the real percentages misleading. Roblox requires the numeric effect to be shown before purchase (RandomItemRules §2).

### 1.4 Season passes

| Game | Tiers | Price | Notes |
|---|---|---|---|
| RIVALS Season 4 (live 14 Nov 2026) | 70 | Season Bundle about 690 R$ (552 with Plus); Deluxe 750 R$ (600 with Plus) with +20 levels and extra cosmetics; single levels 99 R$ | Progress pauses 7 days after every 7 levels (at least 10 weeks to finish). Free track: 10 Skin Tickets, 3 wraps, a charm, a skin at tier 70. Paid track: skins at tiers 1, 35 and 70, more tickets and wraps. Earlier seasons ran 11 to 29 weeks. One article says a completed pass returns about 5 times its cost |
| BedWars | 50 levels (Season 11) | 799 R$ | Season 13: 36,000 BedCoins, a win effect, 2 kill effects, 2 lobby gadgets, 3 animated emotes and 21 image emotes |
| Blade Ball Winter Pass | not found | 480 R$ premium; 1,800 R$ to skip every level | Season 9 skip-all: 2,399 R$ |
| MM2 event passes | 25 to 30 | Event currency, 600 to 800 a tier | The last tier has a 1-in-50 chroma chance |
| Hypershot | Season 1 and a Halloween pass (both off sale) | not found | The owner's reference shows tier 50 of 50, "12 days left", and a **Rebirth**: "Rebirths 1/2/3/5/7/10 have unique serialised weapons, and again every 10 rebirths" |
| Baddies (not a shooter) | Halloween pass | not found | Rebirth after finishing the pass; the 5th rebirth gives an exclusive finisher |

### 1.5 Daily rewards and tasks

- RIVALS: Daily Tasks pay Keys. Login rewards reset with the daily shop, with a bigger prize every 7th day (sometimes Skin Tickets). A free Prize Wheel is earned through Daily Tasks, up to 5 a week (0.5% chance of a sniper skin; 4% chance of a Skin Ticket).
- Hypershot (the reference): a 7-day calendar from 5,000 Coins on day 1 up to 100,000 Coins on day 7, with passive spins, Gems and a Diamond case in between.
- Combat Warriors: daily rewards on launch, Daily Quests for Credits, one daily spin from level 10.

### 1.6 Ranks and leaderboards

- **RIVALS Ranked.** 10 placement duels first. Then Bronze 0, Silver 600, Gold 1,200, Platinum 1,800, Diamond 2,400, Onyx 3,000 and Nemesis 3,600 ELO, each split into I to III 200 ELO apart. **Archnemesis is the top 200 on the leaderboard.** From Onyx up, ELO decays by 100 a day after 7 idle days, down to a floor of 3,000. Glory, a ranked currency, is paid at season end and spent in a Ranked Shop (for example the "Impaled" finisher).
- Hypershot and Combat Warriors have leaderboards and a ranked mode (Combat Warriors' "RANKED" codes, July 2025). I found no thresholds for them.

### 1.7 Kill effects, kill icons, finishers, emotes, skins, wraps, trails

- **Kill effects (RIVALS "finishers").** Cosmetic only. Examples: Confetti and Chalked (Common), Frozen and Midas Touch (Rare), Disintegrate, Balloons and Bubble Ball (Legendary). They come from Finisher Packs (10 Keys), event chests, contracts, the season pass, the Ranked Shop and milestones (for example "5B Visits").
- **Kill icons.** Hypershot sells them in bundles (Pizza Party, 399 R$: a weapon, a banner, a kill effect and a kill icon).
- **Bundles that pair a kill effect with a banner** are Hypershot's main paid shape: Lucky 149 R$, 67 Bundle 80 R$, The Big Guns 975 R$.
- **Wraps** (one pattern for any weapon) and **charms** (a hanging trinket) are RIVALS's cheap, high-volume layer: 14 of each in the daily shop.
- **Emotes:** Hypershot's Emote Pack is 199 R$ for 4 emotes plus a banner. BedWars puts 3 animated and about 21 image emotes in a pass.
- **Bullet tracers and trails:** Hypershot Rainbow Bullets, 159 R$.
- **Titles:** Hypershot sells infinite title changes for 239 R$.

### 1.8 Typical Robux price points (defaults)

| Price | What it buys in these games |
|---|---|
| 5 to 25 R$ | A first-purchase item (our Gold Pouch is 5 R$); a RIVALS event wheel spin (25 R$) |
| 49 R$ | Starter pack (Hypershot) |
| 80 to 159 R$ | Small cosmetic bundle; luck pass (149); tracer pass (159); a premium crate roll (100) |
| 199 to 299 R$ | Emote pack (199); VIP (299); one RIVALS case (249) |
| 399 to 599 R$ | Themed bundle (399); a daily-shop Legendary in RIVALS (about 599); kits (399) |
| 690 to 799 R$ | Season pass (RIVALS about 690, BedWars 799); "essential weapons" pass (799) |
| 975 to 2,399 R$ | Whale bundles; "skip all levels" |

For scale: the standard DevEx rate is about $0.0038 per earned Robux (since 5 Sep 2025, third-party sources; Roblox's own page did not show the figure in my read). Creators keep 70 R$ of a 100 R$ sale.

### 1.9 What players and critics complain about

- **Slow unlock grind** (RIVALS's most common complaint).
- **"2x luck" with no real numbers** (DevForum). The rules now forbid it.
- **Duplicates from paid cases**, and the fact that buying the item directly (about 599 R$) is often cheaper than opening cases for it (about 2.4 cases).
- **Cases disabled in some countries.** Hypershot's own store text warns that bundle cases are not given in those countries.
- **Countdown passes and false scarcity.** Advocacy groups asked US regulators to look at Roblox's loot boxes, chance wheels and pressure design (Fortune, 20 May 2026). A University of Sydney study (17 May 2026) found gambling-like mechanics in many Roblox games. Roblox said paying users were 1.4% of 132M daily users in Q1 2026.
- **Pay-to-win.** RIVALS's success is credited partly to "no purchase gives a competitive edge". Hypershot sells weapons and a luck pass.

## 2. What fits #ARENA 48: a cosmetic catalogue (57 items)

**Fit rules**, from economy-cosmetics.md §6.3 (integrity), the owner's art direction and the Mild rating:
- Matte, semi-realistic, "Roblox with good graphics". Steel is warm-neutral.
- Same silhouette, size and hitbox as the base weapon. Every skin re-materials and re-textures the existing WeaponsV3 mesh. Epic and Legendary skins may add **detail geometry inside the base silhouette** (engraving, wraps, inlays), which is the "more polished at higher tier" the owner asked for.
- No light sources and no Neon in the arena. No near-black, no foliage camouflage, and nothing that copies a loot-rarity glow.
- Kill effects: no blood, nothing red sprayed, no body pieces, at most 1.5 s, seen only by the victim and spectators.
- **Cosmetic only.** Skins never change stars, damage or reach. A skin goes on whatever star level of that weapon you hold, and dropped weapons show plain.

Rarity uses five grades. **The names are an open question (section 4):** Common to Legendary is what players know and what the reference uses, but the game already uses Common to Legendary for loot colours and "Masterwork" for a Strongbox.

### 2.1 Weapon skins (20)

| # | Weapon | Name | Rarity | Look (for the Blender or texture artist) |
|---|---|---|---|---|
| 1 | Longsword | Blued Steel | Common | Blade heat-blued to a matte slate-blue; guard and pommel plain grey steel; dark-brown leather grip |
| 2 | Longsword | Riverstone | Uncommon | Low-contrast grey Damascus-wave texture on the blade; grip wrapped in slate-blue cord with visible crossings |
| 3 | Longsword | Temper Line | Rare | Straw-to-bronze-to-blue temper colours fading up from the guard (flat paint, no glow); brass collar at the ricasso |
| 4 | Longsword | Oakcrown | Epic | Quillons re-sculpted as stylised oak leaves within the old guard's footprint; matte brass inlay line along the fuller; oxblood leather grip with a brass wire twist |
| 5 | Longsword | Starfall | Legendary | Blade of dark-grey meteoric iron with a crosshatched Widmanstätten pattern; rough blue-grey stone set in the pommel; a faint sparkle only in Inspect and the lobby |
| 6 | Hatchet | Camp Orange | Common | Head painted safety-orange with chipped edges showing steel; plain hickory haft |
| 7 | Hatchet | Northwood | Uncommon | Oiled ash haft with three carved knotwork bands; darkened head with a bright honed edge bevel |
| 8 | Hatchet | Rime | Rare | Pale frosted-grey head with a crystalline rime texture along the edge and poll; haft wrapped in grey wool strip |
| 9 | Hatchet | Copperhead | Epic | Hammered copper head with verdigris green in the dents; braided leather bands and a copper butt cap |
| 10 | Twin-Bit Axe | Ironbark | Uncommon | Blackened-brown (not near-black) steel heads; haft with a bark-relief texture |
| 11 | Twin-Bit Axe | Sunforge Bronze | Epic | Cast-bronze heads with a low-relief sunburst on each cheek; two stitched leather bands on the haft |
| 12 | Twin-Bit Axe | Glacier | Legendary | Heads in milky blue-white frosted stone (matte); grey fur collar under the head; steel langets etched with frost-fern lines |
| 13 | Paired Blades | Twin Moons | Rare | Left blade pale silver, right blade gunmetal; each guard engraved with a moon phase (full and crescent) |
| 14 | Paired Blades | Jade Lacquer | Epic | Hilts in matte jade-green lacquer with flecks of gold leaf; blades with a soft satin finish and a single engraved line |
| 15 | Knife | Field Green | Common | Olive-drab handle scales and a stonewashed blade |
| 16 | Knife | Antler | Uncommon | Antler-texture handle with a brass bolster and a satin blade |
| 17 | Spear | Driftwood | Common | Bleached, grain-raised haft with rope lashing at the socket (Saltmarsh set) |
| 18 | Spear | Stormcaller | Legendary | Steel head with a forked lightning line inlaid in silver (not glowing); haft in blue-grey cord; brass storm-cloud ferrule |
| 19 | Bow | Hornbow | Rare | Limbs in cream-and-amber laminated horn stripes; leather grip; waxed string |
| 20 | Bow | Autumn Leaf | Epic | Limbs carved with overlapping maple leaves, stained amber to rust; a single leaf-shaped arrow rest |

Machete, Ring Blade, Leaf Dagger and Climb Pick get wraps at first and their own skins in season 2.

### 2.2 Wraps: one pattern for every weapon (3)

| # | Name | Rarity | Look |
|---|---|---|---|
| 21 | Checker Plate | Common | Steel parts take a diamond-plate texture; wood parts are unchanged |
| 22 | Cobalt Enamel | Uncommon | Steel parts in chipped matte cobalt-blue enamel, with steel showing at edges and corners |
| 23 | Sandstone | Rare | All non-edge surfaces in banded sandstone texture (ochre and buff); edges stay steel |

### 2.3 Throw, arrow and swing trails (5)

Same width, length and lifetime as today's trail. Never darker or harder to see than the default.

| # | Name | Rarity | Look |
|---|---|---|---|
| 24 | Resin | Common | Warm amber ribbon with a light core |
| 25 | Ash Ribbon | Uncommon | Pale grey ribbon that breaks into soft flakes at the tail |
| 26 | Leaf Flutter | Rare | A light-green ribbon that sheds 3 to 4 small leaf sprites |
| 27 | Ember Specks | Epic | A thin orange line that leaves tiny orange specks (not emissive at night) |
| 28 | Gold Dust | Legendary | A soft gold ribbon with a slow drift of gold motes |

### 2.4 Kill effects without blood (6)

These play on the defeated player for at most 1.5 s, then the body goes as it does today.

| # | Name | Rarity | Look |
|---|---|---|---|
| 29 | Ash Scatter | Common | The body greys and breaks into a cloud of pale ash that blows downwind |
| 30 | Leaf Swirl | Uncommon | A ring of autumn leaves spins up around the body and carries it away |
| 31 | Paper Confetti | Rare | A burst of matte paper confetti in the arena flag colours; the pieces flutter down |
| 32 | Feather Burst | Rare | A puff of grey and white feathers (no bird) that drifts down slowly |
| 33 | Frost Over | Epic | Frost creeps up from the feet, then the frosted figure softly dissolves into snowflakes |
| 34 | Recall Beam | Legendary | A pale column of light lifts the fallen player straight up and out of the arena, with a low chime. The lore reading is that the arena takes you out; it is the only effect allowed a brief light, and only for the victim's camera and spectators |

### 2.5 Kill icons: the badge in the kill feed and the defeat banner (5)

| # | Name | Rarity | Look (flat 2D badge, 256 px, matte colours) |
|---|---|---|---|
| 35 | Crossed Axes | Common | Two hatchets crossed in steel grey on a round leather-brown disc |
| 36 | Compass Star | Uncommon | An eight-point compass rose in brass |
| 37 | Wolf Head | Rare | A side-on wolf head in slate blue with a cream outline |
| 38 | Laurel | Epic | A gold laurel wreath around a "48" |
| 39 | Horned Helm | Legendary | A front-on horned helm in steel with a brass rim and a frosted outer ring (in place of the reference's skull, to stay Mild) |

### 2.6 Emotes (5): lobby, spectating and victory only

| # | Name | Rarity | Look (animation brief) |
|---|---|---|---|
| 40 | Whetstone | Common | Pull a stone from the belt, give the held weapon two strokes, check the edge |
| 41 | Blade Twirl | Uncommon | Spin the held weapon twice around the wrist and catch it point-down |
| 42 | Map Check | Uncommon | Unfold a paper map, turn it, nod, fold it away |
| 43 | Campfire Hands | Rare | Crouch and rub the hands over a small fire prop that fades in and out |
| 44 | Last One Standing | Epic | Plant the weapon in the ground, lean on its pommel and look out at the horizon |

### 2.7 Plinth and launch effects (4): finished before the plate locks

| # | Name | Rarity | Look |
|---|---|---|---|
| 45 | Steam Vent | Common | White steam jets from four slots at the plinth's base as it rises |
| 46 | Dust Ring | Uncommon | A ring of dust rolls outwards across the ground when the plate stops |
| 47 | Leaf Ring | Rare | Leaves spiral up around the player during the rise and settle around the plinth |
| 48 | Banner Unfurl | Epic | Your own leaderboard banner (section 2.9) drops from a pole behind you and furls back at the horn |

### 2.8 Train lobby cosmetics (4)

| # | Name | Rarity | Look |
|---|---|---|---|
| 49 | Travel Trunk | Common | A leather-and-brass steamer trunk beside your seat, with your name on a tag |
| 50 | Carriage Lantern | Uncommon | A small brass hurricane lantern on the window hook by your seat (a warm, not bright, flame) |
| 51 | Seat Pennant | Rare | A triangular felt pennant above your seat in your banner's colours |
| 52 | Steam Whistle | Epic | Once a round, pulls the train whistle with a puff of steam when you board |

### 2.9 Leaderboard banners (5)

| # | Name | Rarity / how | Look (a horizontal 3:1 card behind your name on the boards) |
|---|---|---|---|
| 53 | Linen | Free (default) | Plain off-white linen with a stitched border |
| 54 | Oak and Iron | Common | Oak planks with two iron straps and rivets |
| 55 | Mountain Dawn | Rare | A painted range of blue mountains under an apricot sky |
| 56 | Laurel Gold | Earned only: Champion rank | A gold laurel on deep green felt |
| 57 | Top 48 | Earned only: weekly top 48 | Dark slate (not near-black) with a brass "48" seal and the week number |

**Count:** 57 items (12 Common, 12 Uncommon, 13 Rare, 11 Epic, 6 Legendary, plus 3 banners that are free or earned only). The Blender work is mainly items 1 to 20 (re-materials and texture sets on the WeaponsV3 meshes, with in-silhouette detail meshes for Epic and Legendary), the 5 lobby props (49 to 52, plus the Whetstone and campfire props), and the banner and icon art. Kill effects, trails and launch effects are particle and VFX work in Studio.

## 3. Proposed structure (checked against RandomItemRules_2026-11-18.md)

### 3.0 The decision that comes first

| | **Option A: earned cases (my recommendation for the beta)** | **Option B: reference-like (paid luck, Gold for Robux)** |
|---|---|---|
| Gold for Robux | Stays OFF. No developer product, pack, pass or ad ever grants Gold, crates or spins | ON: Gold packs 5 to 799 R$ (already designed in Rewards.lua) |
| Cases | Opened with Gold only, so not a PRI. No PolicyService gate is needed, but the odds are shown anyway | Every crate, the wheel and the Strongboxes become PRIs, because Gold is now Robux-bought |
| Luck boost | **Earned, not sold**: a season-pass reward that lasts the season ("Lucky Charm" at premium tier 25) | Sold: "Lucky Charm" game pass. Its numeric effect is shown before purchase, and the odds update live while it is active |
| Robux earns from | Season pass, direct-buy shop, bundles of fixed items, Wardrobe Pass, private servers | All of A, plus Gold packs and the luck pass |
| Work and risk | Low. No questionnaire change. Every country and age can use everything | PolicyService on join (fail closed); hide or replace cases for restricted players; a direct-buy path at expected value; questionnaire Yes/Yes resubmitted with the publish; Player Emulator tests for UK, BR, BE, NL and AU. **The Strongboxes then sell weapon stars (power) for Robux-bought Gold**, which breaks charter rule 2, so Strongboxes must stay Gold-only, earned-only or be removed |

**Note on Option A:** if a paid luck boost ever exists, even when cases take only earned Gold, the boost is a Robux-bought probability modifier, so those cases are PRIs anyway (RandomItemRules §1). The clean version of Option A has no paid luck.

### 3.1 Cases ("Crates", so they are not confused with today's Strongboxes)

All prices are in Gold. A casual player earns about 550 Gold a day (economy-cosmetics.md §5.3). Contents are the catalogue items in section 2 of that rarity (skins, wraps, trails, kill effects, kill icons, emotes), each equally likely within its rarity. One statement at the top of the list is enough for the per-item odds (RandomItemRules §2).

| Crate | Gold | Common | Uncommon | Rare | Epic | Legendary | Pity (shown in numbers) |
|---|---|---|---|---|---|---|---|
| Timber Crate | 300 | 70% | 25% | 5% | 0% | 0% | none |
| Iron Crate | 750 | 45% | 35% | 15% | 4.5% | 0.5% | none |
| Bronze Crate | 1,500 | 20% | 40% | 28% | 10% | 2% | Epic or better certain by the 15th Bronze crate without one |
| Silver Crate | 3,000 | 0% | 35% | 40% | 20% | 5% | Epic or better by the 8th; Legendary by the 50th |
| Gold Crate | 6,000 | 0% | 0% | 50% | 38% | 12% | Legendary by the 20th |

- **Numbered Edition.** Any Legendary has a 10% chance to arrive numbered, showing its serial ("#0007") on Inspect. It looks the same otherwise. The reference's "Collector's Edition" shows 0%, which is a line that cannot be won and should not be copied. The numbered chance must appear in the odds list (Gold Crate: 1.2% numbered Legendary, 10.8% plain).
- **No-loss and duplicates.** The crate draws first from items in that rarity the player does not own, so the shown odds are the player's real odds. If they own every item of the rolled rarity, they get Gold back: Common 30%, Uncommon 40%, Rare 60%, Epic 100%, Legendary 150% of the crate's price. This is shown on the odds panel. It follows the rule that every outcome must give something, and that odds for once-only items must be per player.
- **The odds panel.** It opens with a worded "Odds" button (not just an (i)), as in the reference. All lines sum to 100%, with the rounding disclaimer when rounded. Pity counters show as "Epic or better in at most 6 more Bronze crates".
- **Quantity.** The reference's quantity selector (−, 1, +) is fine. Allow at most 10 at a time, with no bulk discount (a bulk discount reads as pressure).

**Luck boost, as numbers (both options).** "1 in 3 crates rolls twice and keeps the better rarity." For the Bronze Crate the shown table changes from 20 / 40 / 28 / 10 / 2 to **14.67 / 37.33 / 32.48 / 12.87 / 2.65%** (Common / Uncommon / Rare / Epic / Legendary). The formula: each rarity's chance-or-better p becomes (2/3)·p + (1/3)·(1 − (1 − p)²). The UI must compute and show the boosted table for each crate while the boost is active.

### 3.2 Season pass ("Season Track")

- **Season length:** 6 weeks (42 days), with the true end date shown and no restarting timers.
- **Tiers:** 50. Tier XP comes from rounds (taking part, placement, eliminations, minutes alive) and Daily Trials. Target: the free track is finished by a casual player (about 1 hour a day, about 5 rounds) in about 5 weeks, and a 30-minutes-a-day player finishes it in the season (the economy pillar's rule). No weekly pauses like RIVALS's.
- **Prices:** Premium 399 R$. Deluxe 799 R$ (Premium, +10 tiers and one Deluxe-only Epic skin). **No single-tier skips at launch** (RIVALS sells 99 R$ a tier; Blade Ball sells "skip all" at 1,800 to 2,399 R$). This is an open question for the owner.
- **Free track (25 rewards, every 2nd tier):** about 3,000 Gold in total, 4 Timber Crates, 2 Iron Crates, 1 Bronze Crate, Commons (2 skins, 1 wrap, 1 trail, 1 kill icon) and the season's banner at tier 50. Crates are fine here because the free track is not bought.
- **Premium track (50 rewards, every tier): fixed items only, no crates, no random items**, so the pass is not a PRI. Tier 1: an Epic skin straight away. Tier 25: the Lucky Charm for the season (Option A). Tier 50: the season's Legendary skin. In between: Rare and Uncommon skins, a trail, a kill effect, an emote, a plinth effect and a lobby item, plus about 1,500 Gold if Gold is not sold (Option A). Under Option B, Gold in a paid pass is simply Robux-bought Gold, which is allowed but makes the pass part of the paid-currency chain.
- **Encore (the reference's "Rebirth").** After tier 50, every further 2,500 XP is an Encore level that resets the free row and gives it again. Encores 1, 2, 3, 5, 7 and 10 (and every 10th after that) give a fixed numbered banner trim, and Encore 10 gives a numbered variant of the season's Legendary. No randomness.

### 3.3 Daily reward, 7 days (earned, never sold)

| Day | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| Reward | 150 Gold | Timber Crate | 300 Gold | 2 free wheel spins | Iron Crate | 500 Gold | Bronze Crate and a week stamp |

- **A missed day pauses the streak; it does not reset it.** The cycle repeats. Four stamps give the "Regular" banner trim. No timers in the player's face: just "Next reward in 18:21" on the board, as in the reference.
- Total value is about 950 Gold plus three crates a week, beside about 3,800 Gold a week a casual player already earns from rounds.
- Crates and spins here are earned with no Robux, so they are not PRIs. If Gold ever becomes buyable (Option B), they stay non-PRI because they are free, and the odds are shown anyway.
- **No rewarded ad gives a crate or a spin** (RandomItemRules §5; ad rewards must be fixed developer products).

### 3.4 Ranks: two ladders, one that only goes up and one that can go down

**Level (all players, never goes down: the "rank-up").** Levels 1 to 100 from XP. Each level gives 100 Gold. Every 10th level gives a title and a banner trim (Bronze at 10, Silver at 30, Gold at 60, Platinum at 100). At level 100 you can **Prestige**: back to level 1 with a star on your name (Prestige 1 to 10), keeping everything you own.

**Arena Rank (seasonal, from the 2nd season or once there are enough players).** Rank Points (RP) per round = placement points + 5 per elimination (up to 8) − an entry cost by rank. Only rounds with 8 or more real contenders count (the existing fair-play rule).

| Rank | RP from | Entry cost a round | Divisions |
|---|---|---|---|
| Rookie | 0 | 0 | I to III every 200 |
| Scrapper | 600 | 0 | I to III |
| Survivor | 1,200 | 5 | I to III |
| Contender | 2,000 | 10 | I to III |
| Veteran | 3,000 | 15 | I to III |
| Champion | 4,200 | 20 | I to III |
| Legend | 5,600 | 25 | none |
| **Top 48** | the 48 highest Legends on the season board | 25 | (like RIVALS's Archnemesis, the top 200) |

- Placement points: 1st 60, 2nd 45, 3rd 35, 4th–5th 25, 6th–10th 15, 11th–24th 5, 25th–48th 0.
- Soft reset at season end: down 2 ranks.
- No decay below Legend. Legend loses 50 RP a day after 7 idle days, down to 5,600.
- End-of-season rewards are fixed, never random: a rank banner trim and a kill icon frame (the Champion and above Laurel Gold banner, item 56).

### 3.5 Leaderboards (boards in the train lobby, plus a menu tab)

| Board | All-time | Weekly (resets Monday 00:00 UTC) | Season |
|---|---|---|---|
| Wins | yes | yes | |
| Eliminations | yes | yes | |
| Top-5 finishes | | yes | |
| Longest survival in one round | | yes | |
| Level and Prestige | yes | | |
| Arena Rank RP | | | yes |

- Each row shows the player's banner (section 2.9) and kill icon.
- The weekly top 48 on any board earns the "Top 48" banner (item 57) for the next week.
- Only rounds with 8 or more real contenders count, with the same flags for repeated kills in small lobbies as Gold.
- Build with OrderedDataStore, one store per board and per week key (for example `Wins_2026W47`). Read the top 50 every 60 to 120 s per server, not per player.

### 3.6 Robux price points (defaults; the UI always reads the live price)

| Product | Type | Default price | Option |
|---|---|---|---|
| Season pass Premium | Developer product per season | 399 R$ | A and B |
| Season pass Deluxe | Developer product per season | 799 R$ | A and B |
| Direct buy: Rare / Epic / Legendary item, featured shelf | Developer product | 99 / 199 / 399 R$ | A and B |
| Starter Kit (one time): 1 Epic skin, 1 kill icon, 1 banner, no crates | Developer product | 49 R$ | A and B |
| Themed bundle (a skin, a kill effect, a kill icon and a banner, fixed) | Developer product | 249 to 399 R$ | A and B |
| Wardrobe Pass: 8 loadout slots instead of 2, with EDIT, as in the reference | Game pass | 99 R$ | A and B |
| Supporter Crest | Game pass | 299 R$ | A and B |
| Private server | Monthly | about 100 R$ | A and B |
| Gold packs: Pouch to Vault | Developer product | 5 / 49 / 99 / 199 / 399 / 799 R$ | B only |
| Lucky Charm (permanent, "1 in 3 crates roll twice, keep the better", with numbers) | Game pass | 149 R$ (the reference shows 54 R$, perhaps per use) | B only |

**Rules check (RandomItemRules checklist):**
1. The Gold-for-Robux decision is section 3.0.
2. Odds before buying: section 3.1.
3. No losing slot: the duplicate refund, and no "Collector's 0%" line.
4. Luck and pity shown in numbers: section 3.1.
5. PolicyService only for Option B.
6. No trading.
7. Questionnaire change only for Option B.
8. Player Emulator tests only for Option B.
9. Free crates and spins are fine (section 3.3).
10. No ad gives a crate or a spin.
11. One receipt handler, already designed.
12. No hard-coded prices.
13. Cosmetics never change stats.
14. No casino art on crates or the wheel: plain wooden and metal boxes, no slot-machine or coin-shower art.

## 4. Questions for the owner

1. **Gold for Robux: Option A or Option B (section 3.0)?** Option A keeps every player in every country able to use crates and needs no compliance work. Option B copies the reference fully but locks crates for UK and Brazil minors and others, and adds work before launch.
2. **Should the luck boost be bought or earned?** Bought makes every crate a regulated paid random item. Earned (season pass tier 25) avoids that.
3. **Today's Strongboxes and wheel sell weapon stars (power) for Gold.** If Gold becomes buyable, should they stay, become earned-only, or be replaced by cosmetic crates?
4. **Rarity names:** Common to Legendary (familiar, as in the reference, but the same words as loot rarity), or our own grade names (Issue, Fine, Masterwork, Heirloom, Citadel from the economy pillar)?
5. **Which 3 weapons get skins first?** My order: Longsword, Hatchet, Bow (the most held). Which of the 20 skins do you like most and least?
6. **Kill effects:** Is Recall Beam (the arena lifts the fallen out) in tone? Do you want a skull kill icon like the reference, or keep the Horned Helm to stay safely Mild?
7. **Season pass:** 6 weeks and 50 tiers at 399 / 799 R$? Do you want tier skips for Robux (RIVALS 99 R$ a tier)?
8. **Encore:** Do you want numbered (serialised) rewards like the reference, at Encores 1, 2, 3, 5, 7 and 10?
9. **Arena Rank:** Ranked from launch, or Levels and Prestige first, with Arena Rank once rounds fill to 8 or more players reliably?
10. **Loadout slots:** 2 free and 8 with a 99 R$ Wardrobe Pass, or 4 free as in the reference?
11. **Passive abilities** (the reference's inspect screen): Hypershot gets them from spins earned by play. Do we want passives at all? They change fights, so by charter rule 2 they must be earned, never sold.
12. **Train lobby items and leaderboard banners:** worth building for launch, or later?

## Sources (read 19 Nov 2026)

| Source | Date | Used for |
|---|---|---|
| Owner references: %USERPROFILE%\OneDrive\Documents\LastStanding\References\owner\ui_ref_*_2026-11-19.* (5 files) | 2026-11-19 | Reference screens |
| [bloxodes: Hypershot](https://bloxodes.com/wiki/hypershot) | updated 2026-11-17 | Hypershot players, developer, passes |
| [Insider Gaming: Hypershot codes](https://insider-gaming.com/roblox-hypershot-codes/) | published 2025-11-25 | Case names and Coin prices |
| [Earnaldo: Hypershot gamepasses](https://earnaldo.com/blog/hypershot-best-gamepasses) | 2026-08-16 | Hypershot Robux prices, Lucky pass, regional case note |
| [bloxodes: Shooter genre stats](https://bloxodes.com/stats/games?genre=Shooter) | live, about 2026-11 (no date shown) | Player counts |
| [RoWatcher: most popular right now](https://rowatcher.com/news/the-most-popular-roblox-games-right-now-ranked-by-live-players) | June 2026 | RIVALS and MM2 players |
| [RoWatcher: RIVALS empire](https://rowatcher.com/news/rivals-how-roblox-s-top-shooter-built-a-nearly-million-player-empire) | after March 2026 (no date shown) | RIVALS peak, model, complaints |
| [bloxodes: RIVALS loot boxes](https://bloxodes.com/wiki/rivals/loot-boxes) | updated 2026-11-17 | Cases, packs, wheels |
| [bloxodes: RIVALS currencies](https://bloxodes.com/wiki/rivals/currencies) | updated 2026-11-17 | Currencies |
| [bloxodes: RIVALS finishers](https://bloxodes.com/wiki/rivals/finishers) | updated 2026-11-17 | Kill effects |
| [U7BUY: RIVALS skin cases](https://www.u7buy.com/blog/roblox-rivals-skin-cases-guide/) | 2026-11-16 | Case prices and odds |
| [U7BUY: RIVALS Season 4 pass](https://www.u7buy.com/blog/rivals-season-4-pass-guide/) | 2026-11-16 | Pass structure and prices |
| [Sportskeeda: RIVALS ranked](https://sportskeeda.com/roblox-news/rivals-ranked-guide), [allthings.how](https://allthings.how/roblox-rivals-ranked-mode-and-ranks-explained/), [bloxodes ranks](https://bloxodes.com/wiki/rivals/ranks) | 2025 to 2026 (search summaries) | Rank thresholds |
| [u7buy RIVALS shop guide](https://www.u7buy.com/blog/rivals-shop-guide-2/) (via search) | 2026 | Daily shop, login rewards |
| [Gfinity: Blade Ball Rainbow Explosion](https://www.gfinityesports.com/omg/blade-ball-rainbow-explosion); [Sportskeeda: Blade Ball Winter Pass](https://www.sportskeeda.com/roblox-news/blade-ball-winter-pass-all-rewards-premium-price) (via search) | undated / 2024 to 2025 | Blade Ball crate and pass |
| [Sportskeeda: BedWars Season 13](https://www.sportskeeda.com/roblox-news/bedwars-season-13-update-patch-notes); [itemku](https://www.itemku.com/en/g/bedwars-roblox/battle-pass) (via search) | 2025-04-18 | BedWars pass |
| [rblxguide: MM2 battle pass](https://rblxguide.com/games/murder-mystery-2/updates/mm2-battle-pass-guide) (via search) | 2025 to 2026 | MM2 passes |
| [Pocket Gamer: Combat Warriors codes](https://www.pocketgamer.com/roblox/combat-warriors-codes) and others (via search) | 2025 to 2026 | Combat Warriors currencies |
| [Supercheats: Arsenal cases](https://www.supercheats.com/roblox-arsenal-walkthrough-guide/what-are-cases); [DevForum Arsenal changelog](https://devforum.roblox.com/t/arsenal-brickbattle-update-change-log/223577) (via search) | old (2018 to 2019) | Arsenal |
| [bloxodes: BloxStrike cases](https://bloxodes.com/wiki/bloxstrike/cases) (via search) | updated 2026-10-30 | BloxStrike |
| [DevForum: paying for random items](https://devforum.roblox.com/t/guidelines-around-users-paying-for-random-virtual-items/307189?page=7) (via search) | undated | "2x luck" complaint |
| [Fortune: complaint on Roblox design](https://fortune.com/2026/05/20/exclusive-advocacy-groups-file-complaint-roblox-manipulative-design/); [University of Sydney](https://www.sydney.edu.au/news-opinion/news/2026/05/17/inside-the-pay-to-play-world-of-roblox-targeting-children-.html) (via search) | 2026-05-20 / 2026-05-17 | Criticism |
| [RoWatcher: DevEx rate 2026](https://rowatcher.com/news/the-real-roblox-devex-rate-in-2026-it-s-not-0-0035) (via search) | 2026 | DevEx |
| RandomItemRules_2026-11-18.md, economy-cosmetics.md, src/ReplicatedStorage/Shared/Rewards.lua and Config.lua (this repo) | 2026-11-18 / 11-11 / live | Rules and today's numbers |

**Not verified:** Hypershot as the reference's source (a strong match, not proven); Hypershot's case odds, rebirth and daily calendar (seen only in the owner's screenshots); RIVALS's exact current pass price (sources give 690, 799 and 400 R$ for different seasons); BedWars and Blade Ball current seasons; any game's pity system; the DevEx rate on Roblox's own page.
