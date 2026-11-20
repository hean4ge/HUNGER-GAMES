# Card menus and the shop: "Quiet cards" (20 Nov 2026)

Design only. No game file changed. This page turns every menu where a player **chooses, owns, earns or buys** something into visual cards and slots, in our own look, and settles the catalogue, the cases, the luck boost, the Season Track, the daily reward, ranks and leaderboards for season one.

Read with: `ShopResearch_2026-11-19.md` (games, prices, the 57 items), `RandomItemRules_2026-11-18.md` (Roblox's rules), `Weapons_v2.md` (Gold, wheel, Strongboxes, Armoury), `Combat_v3.md` (skills, Loadout, trails), `ui/StyleA_Quiet/README.md`, `Shared/Theme.lua`, `Shared/QuietUI.lua`.

## 0. In short

- **The owner's point, universally:** a picture of the thing, an edge that says its grade, a short name, one clear action, and a visible state. No more rows of words. Their five references (weapon inspect, saved loadouts, battle pass, 7-day reward, CASES shop) give the **layouts**; our palette, fonts and matte surfaces give the **look**.
- **One kit, "Quiet cards"** (section 1): panel, card, tile, slot, grade edge, seven states, five button kinds, tabs, side list, stepper, bars, countdown, odds list. Softer dark panels (Shade at 80%), cards at 86%, no gloss, no bevel, no glow, no candy colours. The in-round HUD stays Quiet and gets no cards.
- **Grades are new words and new colours:** Plain, Crafted, Prized, Storied, Fabled (+ Honour for earned-only things). They never reuse the loot words (Common to Legendary), the loot glint colours, or the star finish names (Worn, Sound, Fine, Superior, Masterwork). **Weapons show stars, never a coloured edge.**
- **Every screen rebuilt** (section 2), with a mock-up each: Loadout, Edit (kit, skills, trails), weapon inspect, CASES (buy, open, Strongbox), daily reward, Season Track, ranks with the rank-up moment, leaderboards, plus the component sheet.
- **Catalogue for season one** (section 3): 59 cosmetics + 20 trails + the Lucky Acorn, each with grade, source and a one-line look. Five Gold crates (Timber 300 to Crown 6,000) with odds summing to 100%, pity, no-loss duplicates and a Gold shelf so nobody has to gamble.
- **Money:** everything works on earned Gold today. Every Robux path (Gold packs, premium Season Track, paid luck, direct buys, starter kit, extra loadout slots) is designed in full and **OFF** behind `Config.Shop` switches with empty product ids (section 3.10). The premium track never contains Gold, crates or luck, so switching it on never turns the crates into paid random items.
- **Pictures** (section 4): 71 flat icons for the icons agent, and which things use a live 3D view instead.

## 0.1 Mock-ups (1920 x 1080, rendered with Edge, every one looked at)

All in `C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave17\design-shop\` (HTML sources beside them; `cards.css` and `icons.js` are the shared kit). Copy them to `docs/design/ui/QuietCards/` if the owner keeps the direction.

| # | Picture | Matches the owner's reference |
|---|---|---|
| 1 | `m01_system.png` | the kit: grades, states, buttons, tabs, stepper, bars, sizes, phone layout |
| 2 | `m02_loadout.png` | **saved loadouts** (4 cards, 2 big tiles + 5 small tiles, EDIT) |
| 3 | `m03b_kits.png`, `m03_skills.png` | the "abilities" tiles, as picker cards |
| 4 | `m04_inspect.png` | **weapon inspect** (3D weapon, Passive Abilities -> Traits, Kill Effect and Kill Icon slots) |
| 5 | `m05_trails.png` | cards with a moving preview |
| 6 | `m06_cases_buy.png`, `m06b_cases_open.png`, `m06c_strongbox.png` | **CASES** (BUY / OPEN tabs, tier side list, quantity, price, odds by grade, luck) |
| 7 | `m07_daily.png` | **DAILY REWARD** (7 cards, claimed / claimable / locked, countdown) |
| 8 | `m08_season.png` | **Battlepass** (tier bar, free and premium rows, CLAIM, days left, Rebirth -> Encore) |
| 9 | `m09_ranks.png` | rank ladder and the rank-up moment |
| 10 | `m10_boards.png` | leaderboards as a menu |

Stand-ins in the pictures: the weapon and crate drawings are flat SVG stand-ins for the **live 3D view** the game draws in a ViewportFrame; the grey avatar stands for the player's own avatar; names and numbers are invented; the background is a blurred Blender render of the Lounge car.

---

## 1. The kit: "Quiet cards"

### 1.1 Where cards are used, and where they are not

| Cards | Never cards |
|---|---|
| Every menu in the train: Loadout and Edit, Armoury and inspect, CASES, Season Track, Daily reward, Ranks, Leaderboards, the train menu hub | The in-round HUD (vitals, hotbar, compass, kill feed, prompts) stays Quiet, as in `StyleA_Quiet`. Two small additions only: the kill icon (16 design px) beside a name in the kill feed, and on the defeat strip |
| The prize reveal at the steel case (a card rises with the item) | The physical boards stay paper-on-wood SurfaceGuis (results, leaderboards). They gain item pictures (kill icon, best weapon tile, banner behind the name), drawn on paper, not as dark cards |

No menu opens in the arena. Menus open only in the train and the Training Centre.

### 1.2 Surfaces (new `Theme.Card` table; `Theme.Transparency.Panel` stays 1 for the HUD)

| Token | Value | Use |
|---|---|---|
| `Card.Panel` | Shade `#0D1012` lifted to `#111417`, BackgroundTransparency **0.20** | the screen panel; UICorner 12 |
| `Card.Card` | `#202529`, transparency **0.14** | a card; UICorner 10, UIStroke 1.5 px Ink at 0.82 transparency |
| `Card.Well` | `#08090C`, transparency **0.45**, plus a soft lighter centre (a 2-stop UIGradient of the same colour, ±0.10 transparency) | the picture well inside a tile |
| `Card.Hair` | Ink at 0.88 transparency | 1 px rules |
| World behind a menu | `Lighting` BlurEffect Size 12 and Exposure −0.15, eased 0.25 s, removed on close | keeps the train visible but quiet |

Matte only: no gloss strips, no bevels, no outer glow, no drop shadow beyond one soft 18 px shade under the panel. Corners: tile 6, card 10, panel 12 design px.

### 1.3 Grades (cosmetics only)

| Grade | Colour | Edge on a tile | Order |
|---|---|---|---|
| Plain | stone `#A39D90` | 1.5 px edge at 70% + 4 px bottom bar | 1 |
| Crafted | copper `#B87A52` | same, 75% | 2 |
| Prized | verdigris `#5E9E8E` | same, 80% | 3 |
| Storied | mulberry `#9E5C78` (label text `#C58AA3` for contrast) | same, 85% | 4 |
| Fabled | moonstone `#C9D3E0` | full edge + an inner second hairline (double edge); in the lobby and Inspect only, one slow light sweep across the tile every 6 s | 5 |
| Honour | parchment `#E8D9B0` | full edge; earned-only things (season banner, Top 48, trims); never in a crate, never sold | — |

Why these: the loot glints use grey, green, blue, purple and orange with the words Common to Legendary; stars use Worn, Sound, Fine, Superior, **Masterwork** (also a Strongbox's name). None of those words or hues is reused. The grade name is always written on the tile, so colour is never the only signal (colour-blind safe). **Weapons and Strongbox prizes show stars** (Ink, 4★ and 5★ in Sun, as Weapons_v2 §2.4) and never a grade edge.

### 1.4 Parts

| Part | What it is (Roblox) | Notes |
|---|---|---|
| **Tile** | Frame + UICorner 6 + UIStroke (grade) + Well + picture (ViewportFrame or ImageLabel) + name (Montserrat SemiBold, bottom-left, Shade stroke) + grade label (12 px caps, top-left) + 4 px grade bar | the atom; square for items, 2.5:1 for weapons |
| **Slot** | an empty tile with a dashed 1.5 px Ink-30% edge and a faint "+" or the slot's own icon | "Kill effect", "Skin", loadout slots |
| **Card** | Card surface holding a picture well, a name, a 2-line text (max 52 characters), a fact line (cooldown, price) and one button | pickers, rewards, crates |
| **Button** | Primary: Ink fill, Shade text. Secondary: 1.5 px Ink outline. **Sun** fill: CLAIM / OPEN only. Off: Ink 8% fill, faint text. Price button: the coin icon + RobotoMono number | one primary per card, max one Sun button on a screen |
| **Tabs** | text tabs, the current one outlined in Ink, a Sun count badge for things waiting (OPEN 3) | LB / RB on a gamepad |
| **Side list** | a column of 76 px cards (picture + name + price) | CASES tiers; a 72 px strip of tiles on a phone |
| **Stepper** | − value + (40 px squares) | 1 to 10, no bulk discount |
| **Progress bar** | 6 px (10 to 12 px for a tier bar), track Ink 16%, fill Ink (Sun when a reward is ready) | XP, tiers, ranks, hold-to-buy |
| **Countdown** | RobotoMono `18:21:32`, Ink; never red, never flashing | daily, season days left, weekly reset |
| **Odds list** | one row per grade or star: name in its colour, a bar at its true share, the % in RobotoMono; "Total 100%"; a worded **Odds details** button | section 3.4 |

### 1.5 States (every tile and card)

| State | Look |
|---|---|
| Owned | a small Ink disc with a tick, top-right |
| Equipped / Chosen | an Ink tag "EQUIPPED" or "CHOSEN", top-right |
| Selected | a 2.5 px Ink outline 3 px outside the tile |
| New | a 9 px Sun dot, top-left, until hovered once |
| Claimable | Sun edge + the Sun CLAIM button |
| Locked | the picture at 32% and greyed, a padlock icon, the unlock rule in one line ("Level 20 · Scout") |
| Gamepad focus | the Selected outline plus a 7 px Ink-12% halo |

### 1.6 Sizes (design px; 1080p is ×1.25 through `Theme.scaleFor`)

| | Phone (short side ≤ 500) | Tablet | PC 1280×720 design | TV (ten-foot) |
|---|---|---|---|---|
| Item tile | 72 | 88 | 96 | 112 |
| Picker card | 150 × 200 | 176 × 230 | 196 × 256 | 220 × 290 |
| Small tile (skill, trail) | 56 | 64 | 72 | 84 |
| Touch or focus target | ≥ 44 | ≥ 48 | — | ≥ 56 |
| Words / names | 14 / 16 | 15 / 17 | 15 / 18 | 18 / 22 |
| Panel | full screen inside the safe area | 92% × 92% | 1200 × 653 centred | 90% safe area |

Phones: side lists become a strip of tiles across the top; the odds list stays beside BUY (it may never be behind a scroll); grids scroll vertically; one shared line under the grid shows what was touched (no hover on touch). See the phone frame in `m01_system.png`.

### 1.7 Input

| | Mouse and keys | Gamepad | Touch |
|---|---|---|---|
| Move | hover | D-pad / left stick across the grid (`GuiService.SelectedObject`, our ring as `SelectionImageObject`) | tap |
| Choose / main action | click | A | tap |
| Second action (EDIT, Inspect) | click the button | X | the button |
| Odds details, "use on all" | click | Y | the button |
| Tabs | click | LB / RB | tap |
| Back / close | Esc | B | ✕ top-right (44 px) |
| Buy with Gold | BUY, then the button turns to **Hold to confirm** and fills over 0.6 s | hold A | hold |

Robux purchases (when switched on) confirm in Roblox's own prompt; we add no extra confirm.

### 1.8 Builders: one module

`Shared/QuietCards.lua` (new) builds every part from `Theme.Card`: `tile(def)`, `slot(def)`, `card(def)`, `button(kind, text)`, `tabs(list)`, `sideList(items)`, `stepper(min, max)`, `bar(kind)`, `countdown(endUnix)`, `oddsList(rows)`, `itemView(id, variant)` (a ViewportFrame with the item from `ItemModels.build`, a fixed three-point matte light, slow 12°/s turn on hover only). Controllers never style by hand.

Performance: at most 24 live ViewportFrames on screen; tiles beyond the scroll view show their icon image instead; 3D tiles render once and stay still unless hovered (no per-frame turning of 24 models).

---

## 2. The screens

### 2.0 The train menu hub (no mock-up; it is a grid of six big cards)

A small menu key square top-left in the train (`M`; gamepad Select/View, since Roblox keeps Start; touch: a 44 px button under Roblox's own). It opens six cards: **Loadout · Cases · Season · Daily · Ranks · Settings**, each with its icon and one live fact (Daily: "Claim day 3", Season: "Tier 23", Cases: "3 to open"). A Sun dot on the hub button when something is claimable. Physical places still open their screen directly: the Loadout rack (E), the steel case counter by the wheel (E: Cases), the boards (E: Leaderboards).

### 2.1 Loadout (`m02_loadout.png`) — replaces Combat_v3 §3.2's text rows

- Left half: your own avatar at the rack, live (as Combat_v3: the camera eases 0.4 s; drag to turn).
- Right: **saved loadout cards**, like the reference. Each card: a name ("1 Horn runner", editable), **two big tiles** (the kit as its parcel laid out, the BRING weapon as a live 3D view with its stars), and **five small tiles**: weapon skill, general skill, Swing trail, Arrow trail, Throw trail. Beside each card: **EDIT**. Tapping a card selects it (Ink outline, "SELECTED" in Sun).
- **Slots:** 2 at start, slot 3 at level 10 (Runner), slot 4 at level 20 (Scout). A locked card shows the rule. Robux "Wardrobe Pass" for 8 slots is designed and off.
- Locks at the call to launch: the cards dim to 50% and "LOCKS IN 0:42" in Sun (trails still change). The summary line in the train stays (Combat_v3), now with the five small icons instead of words.
- One save, as Combat_v3: `LoadoutSet` gains `slot` (1 to 4) and the saved loadouts list.

### 2.2 Edit: Kit · Bring · Skills · Trails · Look (`m03b_kits.png`, `m03_skills.png`, `m05_trails.png`)

A full panel with five tabs; SAVE / CANCEL bottom-right; Gold top-right.

- **Kit:** five tall cards (picture of the parcel, name, one line, the three to four items as small tiles with counts, "Suggests: Bow"). CHOSEN tag on the current one.
- **Bring:** the Armoury's owned weapons as weapon tiles (live 3D, stars), plus "Kit weapon". Locked tiles for weapons not owned, with "Strongbox or Armoury 800".
- **Skills:** two rows of picker cards: **Weapon skill (Specialty)** — 7 cards, family under the name; **General skill** — 6 cards. Each card: icon, name, two-line effect, cooldown with the ring glyph. Text never runs past two lines (52 characters).
- **Trails:** three slot cards across the top (SWING · ARROW · THROW, the chosen trail's name), then the 20 trails as cards with a **moving preview** (a ViewportFrame draws the trail sweeping left to right every 1.2 s), name, grade, and OWNED / EQUIPPED / price. The right column is the detail card: big preview on your avatar (loops), description, price, **BUY · hold**. Trails stay bought by name with Gold (Combat_v3 §4.3), never in crates.
- **Look:** a weapon strip (your weapons), then for the chosen weapon: Skin, Kill effect, Kill icon slots (the inspect screen's right column), plus Banner and Emote slots (one each, account-wide).

### 2.3 Weapon inspect (`m04_inspect.png`) — the reference's screen

- The weapon large, **live 3D** (drag or right stick to turn), in its equipped skin at your star level.
- Top-left: name, stars (4★ and 5★ in Sun) with the finish name ("Superior · 4★"), and three line bars: damage, swing every, reach (numbers from `Stars`).
- Right column: **Kill effect**, **Kill icon**, **Skin** as large slots with their name and grade, like the reference. They apply when this weapon wins a fight; Y = use on all weapons.
- Bottom-left: **Skin** row (every skin of this weapon: owned, locked with source).
- Bottom-right: **Traits** — the reference's "Passive Abilities!" tiles, filled with what each weapon **already does** (Weapons_v2 §1.2), never new power: Hunting Knife "Unseen 40" and "Quiet swish"; Machete "Second in the arc 60%"; Hatchet "Heavy throw 45" and "Splits firewood"; Spear "Long reach" and "Big throw 60"; Twin-Bit Axe "Armour-breaker" and "Spinning throw"; Ring Blade "Flat throw"; Climbing Pick "Climb ×1.2"; bows "Draw to 60/40 studs on target"; plus the family's **skill** tile (R). Passives are not added to the game.
- Bottom bar: BACK, and the Armoury action as a price button: "Raise to 5★ · 6,000" (Weapons_v2 §4.2), or "Buy 3★ · 800" for an unowned weapon.

### 2.4 CASES: the wheel, Strongboxes, the Armoury and the crates (`m06_cases_buy.png`, `m06b_cases_open.png`, `m06c_strongbox.png`)

One screen, the reference's layout. Opens from the hub or at the steel case counter beside the wheel.

- **Tabs:** BUY · OPEN (Sun badge: unopened crates).
- **Side list**, two groups: *Cosmetic crates* (Timber, Ironbound, Steel, Silverleaf, Crown) and *Weapons (stars)* (Prize Wheel, Strongbox, Masterwork Strongbox, Armoury).
- **Buy card:** the box in 3D, its name and one line, **Quantity** stepper (1 to 10), price, BUY (hold to confirm).
- **Odds card** under it: one row per grade (crates) or per star (Strongboxes, wheel), true-share bars, % and Total 100%, the **Odds details** button (full per-item list), then four plain lines: equal chance within a grade, **pity in numbers** ("Storied or better within 11 more Steel crates"), Numbered chance, duplicates.
- **Right column, crates:** the **Luck** card (Lucky Acorn: charges, what one charge does, a switch "Use a charge on this crate"; when on, the odds card shows a second column "With Acorn") and the **Shelf** card (buy a named item outright).
- **Right column, weapons:** "Your Armoury" (owned weapons with stars) and OPEN THE ARMOURY. Strongbox odds: 3★ 72 · 4★ 24 · 5★ 4%. Acorns never work on weapons.
- **Prize Wheel** in the list shows "free today" or "150"; choosing it shows the wheel's six segments as an odds list and a button **Go to the wheel** (the physical wheel in the train stays the place you spin, Weapons_v2 §5.5).
- **OPEN tab:** crates you hold (from the daily reward and the Season Track) as cards with ×count and OPEN. Opening plays the **reveal card**: the crate's lid lifts in the well, then the item rises in a large tile with its grade colour washing the background softly (no rays, no confetti), "NEW", name in Light 46, grade and type, one line, PREVIEW and **EQUIP** (on the weapon you inspected last, or account-wide). If an Acorn was used: "Rolled twice: Crafted and Storied, kept Storied." Strongboxes and wheel prizes keep their physical reveal at the steel case (others in the car watch).
- **Restricted players** (only when a Robux switch makes crates paid random items): the BUY button of every crate is replaced by "Not available in your region · earn crates from the daily reward and the Season Track"; the Shelf and OPEN stay (section 3.10).

### 2.5 Daily reward (`m07_daily.png`)

Seven day cards in a row: picture, amount, CLAIMED (dim + tick) / **CLAIM** (Sun, only today) / locked (padlock). Above: "Next reward in 18:21:32 · a missed day pauses your streak, it never resets it". Top-right: the week stamps (4 → "Regular" banner trim). It opens by itself once, the first time you reach the train each UTC day with a reward waiting (never after a round, never in a round); otherwise from the hub.

### 2.6 Season Track (`m08_season.png`) — the reference's battle pass

- Tier bar: "Tier 23", the XP bar with "620 / 1,000 XP to tier 24", how XP is earned, and "19 days left" (the true end date on hover).
- Two rows on one track of numbered nodes: **Free** (every tier) and **Premium** (every tier). Claimed (dim + tick), claimable (Sun edge, CLAIM inside the card), locked. Scroll sideways (wheel, drag, LB/RB jump 5 tiers).
- **Encore** card on the right, the reference's "Rebirth", worded our way (section 3.6).
- While `Config.Shop.SeasonPremium` is off, the premium row and its button are **hidden**, not teased; the free row centres.

### 2.7 Ranks (`m09_ranks.png`) and the rank-up moment

- Tabs: **Level** · Arena Rank (later) · Leaderboards.
- Left: You — big emblem, rank name in Light, level, XP bar, the next rank's rewards as tiles, and the Prestige rule.
- Middle: the ladder of ten rank cards (emblem, name, level and XP, reward line); past ranks dim, yours outlined.
- **The rank-up moment:** never in a round. When you come back to the train after the round that crossed a band: the screen dims slightly, the new emblem turns in (0.6 s), a low brass bell (the wheel's bell, quieter), "RANK UP" in Sun, the rank name in Light 60, its reward tiles appear one by one with NEW dots, one button **Equip <item>**; after 3 s or a press it folds into the hub button's dot. Others in the car see a small emblem flash over your seat for 2 s. A plain level-up (no new band) shows only one quiet line on the summary strip: "Level 24 · +100 Gold".

### 2.8 Leaderboards (`m10_boards.png`)

- Left: the six boards as cards (Wins, Eliminations, Top 5 finishes, Longest survival, Level, Arena Rank later). Top: **This week / All time** tabs, reset time and "updated every 2 min".
- Rows: place, the player's **banner** as the row's backing with their name on it, their kill icon, the value. Top three in full Ink, **your row** outlined in Sun and pinned at the bottom when you are off the page.
- **In the train:** three wooden boards in the Lounge car beside the results board (Wins this week, Eliminations this week, Level all time), the same Paper style as the results board (StyleA §10): top 10 with banner strips and kill icons. E on a board opens this menu on that board.

---

## 3. The catalogue and the systems

### 3.1 Season one: "The First Ride" (6 weeks)

Rules for every item (from ShopResearch §2 and the art direction): cosmetic only; same silhouette, size and hitbox as the base weapon; skins re-material the WeaponsV3 mesh, Storied and Fabled may add detail **inside** the silhouette; matte, "Roblox with good graphics"; no Neon in the arena, no near-black, no foliage camouflage; kill effects at most 1.5 s, seen by the victim and spectators, **no blood, nothing red sprayed, no body pieces**.

Sources: **C** = in the crates of its grade · **Shelf** = buyable by name for Gold (section 3.5) · **F#/P#** = Season Track free / premium tier · **R** = rank reward · **D** = daily reward · **Trail shop** = bought by name.

**Weapon skins (26: every weapon has at least one)**

| # | Weapon | Name | Grade | Source | Look (Blender / texture) |
|---|---|---|---|---|---|
| 1 | Longsword | Blued Steel | Plain | C, Shelf | Blade heat-blued to matte slate-blue; plain grey guard and pommel; dark-brown leather grip |
| 2 | Longsword | Riverstone | Crafted | C, Shelf | Low-contrast grey Damascus-wave blade; grip in slate-blue cord with visible crossings |
| 3 | Longsword | Temper Line | Prized | C, Shelf | Straw-to-bronze-to-blue temper bands up from the guard (flat paint); brass collar at the ricasso |
| 4 | Longsword | Oakcrown | Storied | C, Shelf | Quillons sculpted as oak leaves inside the old guard's footprint; brass inlay line in the fuller; oxblood grip with brass wire |
| 5 | Longsword | Starfall | Fabled | **P50** (season exclusive; crates from season 2) | Dark-grey meteoric iron blade with a crosshatched Widmanstätten pattern; rough blue-grey stone in the pommel |
| 6 | Hatchet | Camp Orange | Plain | **F2** | Head in safety orange with chipped edges showing steel; plain hickory haft |
| 7 | Hatchet | Northwood | Crafted | C, Shelf | Oiled ash haft with three carved knotwork bands; darkened head, bright honed bevel |
| 8 | Hatchet | Rime | Prized | C, Shelf | Pale frosted-grey head with a crystalline rime texture on edge and poll; grey wool strip on the haft |
| 9 | Hatchet | Copperhead | Storied | C, Shelf | Hammered copper head with verdigris in the dents; braided leather bands; copper butt cap |
| 10 | Twin-Bit Axe | Ironbark | Crafted | C, Shelf | Blackened-brown (not near-black) heads; haft with a bark-relief texture |
| 11 | Twin-Bit Axe | Sunforge Bronze | Storied | **P1** | Cast-bronze heads with a low-relief sunburst on each cheek; two stitched leather bands |
| 12 | Twin-Bit Axe | Glacier | Fabled | C, Shelf | Heads in milky blue-white frosted stone (matte); grey fur collar; langets etched with frost ferns |
| 13 | Paired Blades | Twin Moons | Prized | C, Shelf | Left blade pale silver, right gunmetal; each guard engraved with a moon phase |
| 14 | Paired Blades | Jade Lacquer | Storied | C, Shelf | Hilts in matte jade lacquer with gold-leaf flecks; satin blades with one engraved line |
| 15 | Hunting Knife | Field Green | Plain | C, Shelf | Olive-drab scales, stonewashed blade |
| 16 | Hunting Knife | Antler | Crafted | C, Shelf | Antler-texture handle, brass bolster, satin blade |
| 17 | Spear | Driftwood | Plain | C, Shelf | Bleached, grain-raised haft; rope lashing at the socket |
| 18 | Spear | Stormcaller | Fabled | C, Shelf | Steel head with a forked lightning line inlaid in silver (not glowing); blue-grey cord; brass storm-cloud ferrule |
| 19 | Recurve Bow | Hornbow | Prized | **P21** | Limbs in cream-and-amber laminated horn stripes; leather grip; waxed string |
| 20 | Recurve Bow | Autumn Leaf | Storied | C, Shelf | Limbs carved with overlapping maple leaves stained amber to rust; leaf-shaped arrow rest |
| 21 | Machete | Brass Spine | Crafted | C, Shelf | A brass-capped spine strip along the blade's back; grip wrapped in tan cord |
| 22 | Ring Blade | Moonring | Prized | C, Shelf | Satin hoop with a thin engraved crescent band on both faces; pale grey cord grip |
| 23 | Climbing Pick | Glacier Guide | Crafted | C, Shelf | Head in chipped blue-grey enamel; pale birch haft; red-brown (not red) leather wrist loop |
| 24 | Short Bow | Birchbark | Plain | C, Shelf | Limbs wrapped in pale birch bark with dark lenticel flecks |
| 25 | Leaf Dagger | Verdigris | Prized | C, Shelf | Leaf blade with a soft copper-green patina, darker in the veins |
| 26 | Throwing Knives | Bone Grip | Plain | C, Shelf | Pale bone-coloured handles, satin blades (no stars, skin still applies) |

**Wraps (3; one pattern for every weapon)**

| # | Name | Grade | Source | Look |
|---|---|---|---|---|
| 27 | Checker Plate | Plain | C, Shelf | Steel parts take a diamond-plate texture; wood unchanged |
| 28 | Cobalt Enamel | Crafted | **F25** | Steel parts in chipped matte cobalt enamel, steel showing at edges |
| 29 | Sandstone | Prized | C, Shelf | Non-edge surfaces in banded ochre and buff sandstone; edges stay steel |

**Kill effects (9; clean: light, petals, dust, a flag, a bell; ≤ 1.5 s)**

| # | Name | Grade | Source | Look (VFX in Studio) |
|---|---|---|---|---|
| 30 | Ash Scatter | Plain | C, Shelf | The figure greys and breaks into pale ash that blows downwind |
| 31 | Petal Fall | Crafted | C, Shelf | Pale cream petals drift down in a slow spiral around the figure |
| 32 | Leaf Swirl | Crafted | C, Shelf | A ring of autumn leaves spins up and carries the figure away |
| 33 | Paper Confetti | Prized | C, Shelf | A burst of matte paper confetti in the arena flag colours |
| 34 | Feather Burst | Prized | **P24** | A puff of grey and white feathers drifting down |
| 35 | Bell Toll | Prized | **P25** | A small brass bell rings once above the figure; a soft ring of dust rolls out |
| 36 | Flag Drop | Storied | C, Shelf | A small cloth arena pennant plants beside the figure and flutters, then folds away |
| 37 | Frost Over | Storied | C, Shelf | Frost creeps up from the feet; the frosted figure dissolves into snowflakes |
| 38 | Recall Beam | Fabled | C, Shelf | A pale column of light lifts the fallen player out of the arena with a low chime (the one effect allowed a brief light; victim's camera and spectators only) |

**Kill icons (5; flat 2D badge in the kill feed, defeat strip, boards)**

| # | Name | Grade | Source | Look |
|---|---|---|---|---|
| 39 | Crossed Axes | Plain | C, Shelf, **R Tracker** | Two hatchets crossed in steel grey on a leather-brown disc |
| 40 | Compass Star | Crafted | **P22**, **R Ranger** | Eight-point compass rose in brass |
| 41 | Wolf Head | Prized | C, Shelf | Side-on wolf head in slate blue with a cream outline |
| 42 | Laurel | Storied | **P26** | Gold laurel around a "48" |
| 43 | Horned Helm | Fabled | C, Shelf | Front-on horned helm in steel, brass rim, frosted outer ring (in place of the reference's skull) |

**Banners and trims (7; a 3:1 card behind your name on boards and loading)**

| # | Name | Grade | Source | Look |
|---|---|---|---|---|
| 44 | Linen | — | everyone | Off-white linen, stitched border |
| 45 | Oak and Iron | Plain | C, Shelf, **R Runner** | Oak planks, two iron straps and rivets |
| 46 | Mountain Dawn | Prized | C, Shelf, **R Paragon** | Blue mountains under an apricot sky |
| 47 | The First Ride | Honour | **F50** | The red train crossing a trestle in silhouette on a cream ground, "S1" stamp |
| 48 | Top 48 | Honour | weekly top 48 on any board | Dark slate with a brass "48" seal and the week number |
| 49 | Regular (trim) | Honour | 4 daily-reward stamps | A brass rail along the banner's lower edge |
| 50 | Rank trims (Warden, Sentinel, Paragon frame) | Honour | **R** | Thin rails in steel, silver, then a moonstone frame |

**Emotes (5; lobby, spectating and victory only; cheap with the Blender clip pipeline, so in season one)**

| # | Name | Grade | Source | Animation brief |
|---|---|---|---|---|
| 51 | Whetstone | Plain | C, Shelf | Pull a stone from the belt, two strokes on the held weapon, check the edge |
| 52 | Blade Twirl | Crafted | C, Shelf | Spin the held weapon twice around the wrist, catch it point-down |
| 53 | Map Check | Crafted | **P23** | Unfold a paper map, turn it, nod, fold it away |
| 54 | Campfire Hands | Prized | C, Shelf | Crouch and rub the hands over a small fire prop that fades in and out |
| 55 | Last One Standing | Storied | C, Shelf, **R Vanguard** | Plant the weapon, lean on the pommel, look out at the horizon |

**Launch effects (4; finish before the plate locks)**

| # | Name | Grade | Source | Look |
|---|---|---|---|---|
| 56 | Steam Vent | Plain | C, Shelf | White steam jets from four slots at the plinth's base |
| 57 | Dust Ring | Crafted | C, Shelf, **R Pathfinder** | A ring of dust rolls out when the plate stops |
| 58 | Leaf Ring | Prized | C, Shelf | Leaves spiral up during the rise and settle |
| 59 | Banner Unfurl | Storied | C, Shelf | Your banner drops from a pole behind you and furls at the horn |

**Trails (20, Trail shop, never in crates).** Combat_v3 §4.2's 18, re-graded: Free → no grade (Draught, Dust), Common 300 → Crafted (Thistledown, Neon Thread, Hardline, Haze Line), Rare 800 → Prized (Leafwake, Ember Drift, Kindle, Frostbreath, Pulse, Glowworm), Epic 1,800 → Storied (Forked Light, Shardfall, Wishing Stars, Nebula), Legendary 4,000 → Fabled (Comet, Molten). Plus two season trails: **Resin** (Plain, F10: a warm amber ribbon with a light core) and **Gold Dust** (Fabled, P45: a soft gold ribbon with a slow drift of motes).

**Not in season one:** the four train-lobby props (trunk, lantern, pennant, whistle) move to season two; wraps for more weapons as needed.

**Crate pools (items with source C):** Plain 11 · Crafted 10 · Prized 11 · Storied 8 · Fabled 4 = 44. Season-exclusive items (P1, P50, F-row items) join the crates the season after.

### 3.2 Crates (Gold only)

Names avoid "Gold Crate" (Gold is the currency) and the star words.

| Crate | Gold | Plain | Crafted | Prized | Storied | Fabled | Total | Pity (per player, shown) |
|---|---|---|---|---|---|---|---|---|
| Timber | 300 | 70% | 25% | 5% | — | — | 100% | none |
| Ironbound | 750 | 45% | 35% | 15% | 4.5% | 0.5% | 100% | none |
| Steel | 1,500 | 20% | 40% | 28% | 10% | 2% | 100% | Storied or better by the 15th Steel crate without one |
| Silverleaf | 3,000 | — | 35% | 40% | 20% | 5% | 100% | Storied+ by the 8th; Fabled by the 50th |
| Crown | 6,000 | — | — | 50% | 38% | 12% | 100% | Fabled by the 20th |

- A grade the crate cannot give is **not listed** (no 0% lines; nothing like the reference's "Collector's Edition 0%").
- **Within a grade every item is equally likely, and you only draw items you do not own.** So the shown odds are each player's real odds (RandomItemRules §2, once-only items). Odds details lists every item with its own % for that player (Steel, Fabled with 4 unowned: 0.5% each).
- **Duplicates:** only when you own the whole grade: Gold back at Plain 30%, Crafted 40%, Prized 60%, Storied 100%, Fabled 150% of the crate's price. Shown on the odds card.
- **Numbered:** a Fabled item has a 1 in 10 chance to arrive numbered ("#0007" on Inspect, same look). Its own line in Odds details (Crown: Fabled numbered 1.2%, plain 10.8%).
- Quantity 1 to 10, no bulk discount. Opening 10 shows ten reveal cards in a grid, best last.
- Crates also come free from the daily reward, the free Season Track and ranks.

### 3.3 The luck boost

**Earned now: the Lucky Acorn** (Honour-like consumable, never sold).

- **One charge: this crate rolls twice and keeps the better grade.** Toggle on the luck card before BUY or OPEN. Not for Strongboxes or the wheel (weapons).
- From: daily reward day 6 (1), ranks (2 to 3 at bands), free Season Track (4 across the season). Holds up to 10.
- The odds card shows the boosted column live (better-of-two: each grade's "this or better" chance p becomes 1 − (1 − p)²):

| Crate | Plain | Crafted | Prized | Storied | Fabled |
|---|---|---|---|---|---|
| Timber + Acorn | 49% | 41.25% | 9.75% | — | — |
| Ironbound + Acorn | 20.25% | 43.75% | 26.25% | 8.75% | 1% |
| Steel + Acorn | 4% | 32% | 41.44% | 18.6% | 3.96% |
| Silverleaf + Acorn | — | 12.25% | 44% | 34% | 9.75% |
| Crown + Acorn | — | — | 25% | 52.44% | 22.56% |

Each row sums to 100%. Pity still counts each crate once.

**Robux version (designed, OFF: `Config.Shop.RobuxLuck = false`, `LuckPassId` empty): "Lucky Charm" game pass, designed 149 R$.**
- **Every 3rd crate you open rolls twice and keeps the better grade** (a counter, not a 1-in-3 chance, so there is no randomness on top of randomness, and the card can say "Your next crate is lucky"). The odds card shows the lucky table for that crate (the Acorn table above) and the normal table otherwise. An Acorn on a lucky crate does nothing extra (the card says so).
- Switching it on makes the crates **paid random items** for buyers (a Robux-bought probability modifier, RandomItemRules §1): PolicyService gate on the pass's purchase, odds shown live, questionnaire Yes/Yes, Player Emulator tests. That is why it stays off unless the owner chooses it after the lead's one-line warning.

### 3.4 Odds shown (every random thing)

| Thing | Shown before paying | Where |
|---|---|---|
| Crates | per grade + per item (Odds details), pity, duplicates, numbered, Acorn column | CASES odds card |
| Strongbox / Masterwork | 3★/4★/5★ (72/24/4 and —/85/15), pity "4★ within 5, 5★ within 23" | CASES odds card + the brass plaque by the case |
| Prize Wheel | 40 Gold 30 · 80 Gold 22 · 200 Gold 8 · 3★ 28 · 4★ 10 · 5★ 2 | CASES + the plaque; the wheel's segments drawn at true size |

### 3.5 The Shelf (no gambling needed)

Every crate item can also be bought by name for Gold: **Plain 400 · Crafted 900 · Prized 2,000 · Storied 4,500 · Fabled 12,000.** The Shelf shows **6 items a day** (a deterministic UTC-date rotation, the same in every server; every crate item appears at least once in 14 days), so there is a reason to look each day. Items already owned never show. Weapons have their own sure path: the Armoury.

### 3.6 Season Track

- **Season 1 "The First Ride": 42 days**, 50 tiers, the true end date shown, no restarting timers, no weekly pauses.
- **XP per round:** taking part 100 · placement 1st 200, 2nd 150, 3rd 120, 4th–5th 90, 6th–10th 60, 11th–24th 30, 25th–48th 10 · each elimination 20 (max 8) · 5 a minute alive (max 100) · win +100. **Daily Trials:** 3 a day, 200 XP each (for example "Open two crates at the Horn", "Drink from a stream", "Finish in the top 10"). Same fair-play rule as Gold (8+ real contenders for full XP; practice and private servers 0).
- **1,000 XP a tier, flat.** A casual player (5 rounds and the trials, about 1,850 XP a day) finishes in about 27 days; 30 minutes a day (about 1,225) finishes in 41. The same XP also fills your Level (3.8).
- **Free row (every tier, 50 rewards):** Gold 100 to 300 on 35 tiers (about 4,000 in all), 4 Timber, 2 Ironbound and 1 Steel crate, 4 Lucky Acorns, Camp Orange (F2), Resin trail (F10), Cobalt Enamel wrap (F25), The First Ride banner (F50).
- **Premium row (every tier, designed 399 R$, OFF):** **fixed items only, never Gold, crates or Acorns**, so buying it never makes Gold or luck buyable and never makes the crates paid random items. Sunforge Bronze at P1, Hornbow P21, Compass Star P22, Map Check P23, Feather Burst P24, Bell Toll P25, Laurel P26, Gold Dust trail P45, Starfall P50; the other 41 tiers are season titles (a word under your name on the boards: "Night Rider", "Stoker", "Brakeman", "Conductor"...), banner trims and "Night" recolours of the season's skins. **Deluxe** (designed 799 R$, OFF): Premium + 10 tiers + one Deluxe-only Storied skin. No single-tier skips.
- **Encore** (the reference's Rebirth): after tier 50, every 2,500 XP replays the free row's Gold and Acorn tiers. Encores 1, 2, 3, 5, 7 and 10 add a numbered banner trim; Encore 10 gives a numbered "Night" Starfall. Nothing random.
- Unclaimed rewards are claimed for you when the season ends (no loss).

### 3.7 Daily reward

| Day | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| Reward | 150 Gold | Timber Crate | 300 Gold | 2 free wheel spins | Ironbound Crate | Lucky Acorn + 300 Gold | Steel Crate + a stamp |

- Days run on UTC; claimable from the train only. **A missed day pauses the streak; it never resets it.** The week repeats. 4 stamps give the Regular trim.
- Earned, never sold, never from an ad (RandomItemRules §5). About 750 Gold, three crates, two spins and an Acorn a week.

### 3.8 Ranks

**Level (everyone, from launch; never goes down).** Level n → n+1 costs **400 + 40·n XP**. Each level pays **100 Gold**. Every 10 levels a new rank, with an emblem and rewards:

| Rank | From level | Total XP | Rewards at the band |
|---|---|---|---|
| Recruit | 1 | 0 | — |
| Runner | 10 | 5,400 | Loadout slot 3 · Oak and Iron banner |
| Scout | 20 | 15,200 | Loadout slot 4 · 2 Lucky Acorns |
| Tracker | 30 | 29,000 | Crossed Axes kill icon · Steel Crate |
| Pathfinder | 40 | 46,800 | Dust Ring launch effect · 2 Acorns |
| Ranger | 50 | 68,600 | Compass Star kill icon · Silverleaf Crate |
| Warden | 60 | 94,400 | Warden trim · 3 Acorns |
| Vanguard | 70 | 124,200 | Last One Standing emote |
| Sentinel | 80 | 158,000 | Sentinel trim · Crown Crate |
| Paragon | 90 | 195,800 | Paragon frame · Mountain Dawn banner |
| Prestige | 100 | 237,600 | back to level 1 with a star by your name (1 to 10), keeping everything |

About 4 months to level 100 for a casual player. No decay. Names avoid the films' words (no "Tribute", "District").

**Arena Rank (seasonal, later: `Config.Ranks.Arena = false` until rounds fill to 8+ real contenders reliably).** As ShopResearch §3.4: Rookie 0, Scrapper 600, Survivor 1,200, Contender 2,000, Veteran 3,000, Champion 4,200, Legend 5,600, Top 48 (the 48 best Legends); RP = placement points + 5 per elimination (max 8) − entry cost; soft reset 2 ranks a season; Legend decays 50 RP a day after 7 idle days, floor 5,600; end-of-season rewards fixed (rank trim, Champion+ "Laurel Gold" banner). The names do not collide with the Level names.

### 3.9 Leaderboards

| Board | Value | All time key | Weekly key (ISO week, Monday 00:00 UTC) |
|---|---|---|---|
| Wins | rounds won | `LB_Wins_All` | `LB_Wins_W2026-47` |
| Eliminations | defeats dealt | `LB_Elims_All` | `LB_Elims_W2026-47` |
| Top 5 finishes | count | — | `LB_Top5_W2026-47` |
| Longest survival | best seconds alive in one round (kept as a max) | — | `LB_Survive_W2026-47` |
| Level | prestige × 1000 + level | `LB_Level_All` | — |
| Arena Rank (later) | RP | — | `LB_RP_S1` (season) |

- **Writes:** at round end only, one `IncrementAsync` (or `UpdateAsync` keeping the max for survival) per board per player, spread over 10 s. Only rounds with 8+ real contenders count.
- **Reads:** each server reads the top 50 of each board every 120 s (staggered 20 s apart), not per player; your own rank comes from your saved stats and is shown as "212" only when the server's last read can place you, otherwise "Top 1,000+" (no per-player sorted read).
- Weekly top 48 on any board earns the Top 48 banner for the next week (granted by a Monday job in the first server to start after the reset, idempotent per week key).
- Where: the menu (2.8) and three Paper boards in the Lounge car.

### 3.10 Robux, all designed and OFF

| Switch (`Config.Shop`, new) | Product | Designed price | What changes when on |
|---|---|---|---|
| `RobuxGold` (= today's `Config.Economy.RobuxGold`) | Gold packs Pouch to Vault (Weapons_v2 §4.3) | 5 to 799 R$ | **Every crate, the wheel's paid spins and the Strongboxes become paid random items**; PolicyService gate on all of them; Strongboxes sell power for Robux (charter rule 2). Not recommended |
| `SeasonPremium`, `SeasonDeluxe` | developer product per season | 399 / 799 R$ | the premium row and its button appear; fixed items only |
| `RobuxLuck` | Lucky Charm game pass | 149 R$ | crates become paid random items for buyers (3.3) |
| `DirectBuy` | Shelf items for Robux | Prized 99 · Storied 199 · Fabled 399 R$ | a Robux price button beside the Gold one on Shelf items |
| `StarterKit` | one-time product: Hornbow-style Prized skin, a kill icon, a banner, no crates | 49 R$ | a hub card for new players for 7 days |
| `WardrobePass` | game pass: 8 loadout slots | 99 R$ | slots 5 to 8 |

- Every product id is `nil` until the lead creates the products after the owner's yes. A switch with a nil id stays off (the server checks both).
- Prices are **always read from Roblox** (`GetProductInfoAsync`), never written in the UI, because Managed Pricing and Plus change them per player.
- One receipt handler for all products, grant once per PurchaseId, save before `PurchaseGranted` (RandomItemRules §7, already designed).
- **PolicyService:** on join, `GetPolicyInfoForPlayerAsync` in `pcall`, cached; a failed call counts as restricted. It only matters when `RobuxGold` or `RobuxLuck` is on.
- Recommendation kept from ShopResearch: **Option A** (Gold never sold; Robux earns from the premium track, direct buys, bundles of fixed items, the Wardrobe Pass, private servers). Under it no crate is a paid random item, every player in every country uses everything, and the questionnaire answers stay No.

### 3.11 Today's screens, and what replaces them

| Today ("text chunks") | Becomes |
|---|---|
| `LoadoutController` KIT / BRING / WEAPON / GENERAL / TRAIL text rows | 2.1 Loadout cards + 2.2 Edit tabs |
| `KitController` KIT / BRING line | gone (already replaced by the Loadout) |
| Trail strip (names and prices) | 2.2 Trails cards with moving previews |
| Wheel prompt and thin odds line | wheel entry in CASES (odds list), the physical wheel stays |
| Strongbox counter prompt | CASES · Strongbox; the physical reveal stays |
| Armoury board text | 2.3 Inspect + CASES · Armoury |
| Results board rows | stays a Paper board; rows gain the kill icon, the best weapon as a small tile, the banner strip |

---

## 4. Pictures: icons and live 3D views

### 4.1 Live 3D (ViewportFrame via `ItemModels.build(id, variant)`)

Weapons (every tile, inspect, Bring, Armoury), **weapon skins and wraps** (the skinned mesh), crates and Strongboxes (in BUY, OPEN and the reveal), the kit parcel's contents on the Kit card (laid out items), trails (moving preview), kill effects, emotes and launch effects in **Preview** (played on a grey mannequin or your avatar). Tiles beyond 24 on screen fall back to their icon.

New 3D models (Blender, `art/blender`): the **five crates** from one base (Timber: planks and rope handles; Ironbound: planks with two iron bands; Steel: riveted grey steel with a brass latch; Silverleaf: pale silver-grey steel with a pressed leaf on the lid; Crown: dark slate-blue steel with a brass crown boss and brass foot rail), lids as separate parts for the reveal. Matte, faceted, about 1,500 triangles each.

### 4.2 Flat icons (for the blender-icons agent)

**Style:** 256 × 256 PNG, transparent; **one silhouette** centred in a 200 px box; 2 to 3 flat matte tones from our palette (Ink `#F4F1EA`, Ink2 `#BDB8AC`, steel `#A7AEB2`/`#6C747A`, wood `#8E6B4C`/`#6A4E38`, leather `#5A4535`, brass `#C9A24E`/`#9C7A34`, Sun `#E8B65A` only for an accent, sage `#9DBFAE`); a soft 1 px Shade shadow baked at 60%; no outline glow, no gradients beyond one shade step, no text except the "48"/"7" marks. Render in Blender orthographic with flat (emission) shading of simple faceted meshes, or draw as vectors and rasterise; either way the same look as the stand-ins in `icons.js`. Rank emblems 512 × 512. Each upload needs the owner's yes (image uploads), so batch them into one request.

| Group | Icons | Count |
|---|---|---|
| Weapon skills | Head Kick, Chained Strikes, Running Cut, Whirl, Vault Kick, Ricochet, Piercing Shot | 7 |
| General skills | Concentration, Second Wind, Sprint Burst, Quiet Step, Steady Hands, Brace | 6 |
| Kits | Archer, Forager, Trapper, Medic, Climber | 5 |
| Traits | Unseen, Quiet swish, Second in the arc, Heavy throw, Splits firewood, Long reach, Big throw, Armour-breaker, Spinning throw, Flat throw, Climb, Draw range | 12 |
| Currencies and consumables | Gold coin, Lucky Acorn, wheel spin token, XP star, daily stamp | 5 |
| Cases (icon fallback for the 3D) | Timber, Ironbound, Steel, Silverleaf, Crown, Strongbox, Masterwork Strongbox, Prize Wheel, Armoury | 9 |
| Ranks | Recruit to Paragon emblems (shield, chevrons, metal stepping stone → copper → steel → brass → moonstone → parchment) + Prestige star | 11 |
| Kill icons (these are the items themselves) | Crossed Axes, Compass Star, Wolf Head, Laurel, Horned Helm | 5 |
| Kill effects / emotes / launch effects (tile pictures; Preview is live) | 9 + 5 + 4 | 18 |
| Pass and UI marks | season title tag, banner trim, Numbered seal, padlock, tick, "none" slot | 6 |

Banners (7) are full images (768 × 256), painted flat in the same matte palette. Total: 84 icons + 7 banners.

---

## 5. For the builders

### 5.1 New and changed Config

```lua
Config.Shop = {
	RobuxGold = false,      -- mirrors Config.Economy.RobuxGold (keep that key; read either)
	SeasonPremium = false, SeasonPremiumProductId = nil,
	SeasonDeluxe = false, SeasonDeluxeProductId = nil,
	RobuxLuck = false, LuckPassId = nil,
	DirectBuy = false, DirectBuyProductIds = {},   -- by grade: Prized, Storied, Fabled
	StarterKit = false, StarterKitProductId = nil,
	WardrobePass = false, WardrobePassId = nil,
	ShelfPerDay = 6, CrateMaxQuantity = 10, AcornMax = 10,
}
Config.Season = { Id = "S1", Name = "The First Ride", StartUnix = nil, Days = 42, Tiers = 50, TierXP = 1000, EncoreXP = 2500 }
Config.Ranks = { LevelBase = 400, LevelStep = 40, GoldPerLevel = 100, Arena = false }
Config.Daily = { Rewards = { "Gold150", "Timber", "Gold300", "Spins2", "Ironbound", "Acorn+Gold300", "Steel+Stamp" } }
```

### 5.2 Code touchpoints

- `Shared/Theme.lua`: add `Theme.Card` (surfaces, corners) and `Theme.Grade` (six colours); keep `Theme.Rarity` for loot only.
- `Shared/QuietCards.lua` (new): the builders in 1.8. `Shared/Cosmetics.lua` (new): the catalogue (id, type, weapon, grade, sources, look keys). `Shared/Crates.lua` (new): tables, pity, Acorn maths, per-player odds.
- Server: `ShopService` (crates, Shelf, Acorns, product receipts behind the switches), `SeasonService` (XP, tiers, claims, Encore, Daily Trials), `DailyService`, `RankService` (level, bands, Prestige), `LeaderboardService` (OrderedDataStores, the weekly job), all saving through `DataService`. `RewardsService` keeps the wheel and Strongboxes; CASES calls it.
- Client: `LoadoutController` rebuilt on QuietCards (keeps its remote and one-save rule), `CasesController`, `SeasonController`, `DailyController`, `RanksController`, `MenuHubController`; `WheelController` keeps the physical scenes.
- Remotes: `Shop` (buy, open, shelf, acorn), `Season` (claim), `Daily` (claim), each rate-limited and checked on the server.

### 5.3 Build order (show each as soon as it runs)

1. QuietCards kit + the Loadout and Edit screens (the owner's first complaint).
2. Weapon inspect with Look slots (skins can be placeholders).
3. CASES with the wheel, Strongboxes and Armoury (exists today) as cards.
4. Daily reward and Level ranks with the rank-up moment.
5. Crates, Shelf, Acorns, the first 10 skins and 4 kill effects.
6. Season Track (free row), leaderboards and the train boards.
7. The rest of the catalogue; the Robux paths stay built and off.

### 5.4 Checks before each is called done

- Every odds table on screen sums to 100% (or shows the rounding line) and matches `Crates.lua`.
- Phone 812 × 375: no target under 44 px, the odds list visible beside BUY, nothing cut.
- Gamepad only: every screen fully usable, focus never lost.
- With every `Config.Shop` switch off, no Robux price, button or teaser appears anywhere.
- No menu can open in the arena; the HUD is unchanged except the kill icon.

## 6. Questions for the lead (not for the builders)

1. The owner asked to be asked for **examples of items** after this work: the catalogue above is ready for their likes and dislikes (which 3 weapons get skins first; Recall Beam in tone; Horned Helm instead of a skull).
2. **Grade names**: Plain / Crafted / Prized / Storied / Fabled, or would the owner rather keep Common to Legendary as the reference does (it collides with the loot words and colours)?
3. **Option A** (Gold never sold) is assumed everywhere; the owner still has to choose.
4. **Premium Season Track at 399 R$** and the Wardrobe Pass are the cleanest first Robux items; both are fixed items and need no compliance work.
5. Image uploads (84 icons, 7 banners) need the owner's yes, in one batch.
