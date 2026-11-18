## summary
Style A "Quiet" is done: four 1920x1080 mock-ups over the owner's real captures (HUD, lobby, defeated/spectating strip, physical results board) and one owner sheet, sheet_A.png (1920x4900). Every PNG was rendered with Edge and looked at; the HUD, lobby and board each went through at least one fix-and-re-render pass. Nothing in the repo or Studio was touched.

## details
**What the owner sees on the sheet**
- **In a round (hud.png):** daylight valley capture. It carries everything asked for: three vitals lines, a 6-slot hotbar with no boxes, the compass with a water marker, crosshair, "17 left" with day and time, a kill-feed line, "E Open crate", and the border warning as a small picture bottom right.
- **Lobby (lobby.png):** the plaza capture with the owner's avatar. The top half stays pure picture; title, countdown and "7 contenders waiting" sit bottom left, the player list bottom right, and SETTINGS / HOW TO PLAY / ROBLOX PLUS are plain text buttons.
- **Defeated (fallen.png):** no card. One strip along the bottom: "Defeated by Kestrel", "You placed 9th of 24", "Spectating Rowan" with Q / E for previous and next, and "Back to lobby".
- **Results board (board.png):** the board face flat, and the same face on a wooden stand in the lobby plaza. It shows the winner, the top five with defeats and time survived, the owner's own row marked in amber, and four round facts.

**Things that are not real in the pictures**
- The old HUD was painted out of each capture; `tools/prep.py` does this and also crops to 16:9. The lobby capture was additionally brightened because the old result screen had dimmed it.
- No third-person arena capture exists, so the spectating picture shows the dusk valley with no contender in frame. The first-person hands were painted out of it.
- Player names and all numbers are invented. The small avatar tiles stand in for Roblox headshot thumbnails.
- Hotbar items are drawn as flat two-tone icons. Today's game uses 3D item icons, so this style needs one image per item.
- The lobby drops today's tagline and personal record card (wins, kills, rounds); only wins per player remain in the list. Put them back as one dim line if the owner misses them.

**What the owner has said about UI (from prompts.md)**
- Today's message: "fix the UI in a style that i will like also it shouldnt pop up after the game it can appear on one of the physical boards".
- Earlier: damage should read "without a HUD number telling them"; complexity should not come from "overwhelming them with menus, currencies, abilities and unnecessary statistics".
- That is all they have said on HUD, menus or boards; the style follows it.

**Palette**
| Name | Hex | Use |
|---|---|---|
| Ink | #F4F1EA | all text, lines and icons (second icon tone #BDB8AC) |
| Shade | #0D1012 | shadows and outlines only, never a fill |
| Sun | #E8B65A | "look at this": low hunger or thirst, water marker, YOU and PLUS tags |
| Red | #DE5B4B | danger: low health, the border, defeat |
| Paper | #EAE5D9 | board face |
| Paper ink | #23272B | text on the board |
| Board extras | #C98A22, #8A5C10 | your-row bar; YOU tag on paper |
| Wood | #5A4535, #6B5340, #43332A | frame and posts: front, lit edge, shaded edge |

`quiet.css` still defines a `--water` blue that nothing uses; I dropped it because a blue drop vanished against the sky.

**Fonts and Roblox equivalents**
- **Montserrat** (Light 300, Regular 400, Medium 500, SemiBold 600) maps to Roblox's built-in Montserrat family: `Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Light)` and so on. Use it for all words.
- **Roboto Mono** (Regular 400, Medium 500 for the key letter) maps to Roblox's built-in RobotoMono (`Enum.Font.RobotoMono`). Use it for numbers that change: vitals, distances, clock, slot numbers, board columns.
- I did not check in Studio which weights each family ships (Studio was off limits). If Montserrat Light is missing, Builder Sans Light is the nearest built-in; if Roboto Mono Medium is missing, use Regular.

**The style in ten rules**
1. **No panels.** Text, lines and icons sit directly on the 3D picture. The only outlines are the key square (UIStroke 1.5 px, 7 px corner) and the border-warning edge.
2. **One colour.** Everything is Ink. Sun appears only when something needs attention, Red only for danger. No gradients, no glow.
3. **Legibility comes from shadow.** Every label gets a UIStroke of 1 px in Shade at about 60% transparency plus one copy offset 1 px down at about 40% opacity. Icons are PNGs with that shadow baked in.
4. **Type sizes at 1080p.** Light 300 only at 28 px and above (title 68, "17" 46, status 30). Body is Medium 500 at 16–20 px; labels are SemiBold 600 capitals at 15–17 px. Nothing is under 14 px; scale with a UIScale on smaller screens.
5. **No letter-spacing.** Roblox has none, so all text is set at normal spacing. The one exception is the title: build it as one TextLabel per letter in a UIListLayout with 11 px padding.
6. **Bars are lines.** A 3 px Frame (health 4 px), 220 px long: track is Ink at 26% opacity, fill is solid Ink. Icon on the left, number on the right; a 1 px tick marks the healing threshold on hunger and thirst.
7. **Rest, active, low.** A value that is fine rests at 72% opacity. A low hunger or thirst row turns Sun and puts a Sun drop with its distance on the compass. Low health and the border use Red. Compass, hotbar and vitals hide while spectating.
8. **Layout.** 44 px margins. Top left stays empty for Roblox's own buttons. Compass is top centre: a 560 px, 1 px line with ticks, three letters above and markers hanging below. Round facts and kill feed are top right, vitals bottom left, hotbar bottom centre, prompt 60 px under the crosshair.
9. **Hotbar.** Six 96 px cells with no slot boxes. Items are flat two-tone icons at 56 px, slot number underneath, stack count at the icon's lower right. The selected slot grows to 70 px, gets a 26 x 2 px underline and its name above. An empty slot is a 10 px ring.
10. **Results live on the board, never on screen.** Defeat shows only the 78 px bottom strip under a 1 px line. The board is a 1600 x 900 SurfaceGui: Paper face, Paper ink text at 30 px or more, 2 px rules, your row with a 42% Sun band and an 8 px #C98A22 bar. Keep the SurfaceGui lit by the world so it stays matte.

**Border warning as designed:** a 2 px Red line inset from the screen edge, the compass line turns Red with an arrow toward safety, "Outside the border / Turn back · 28 m" under the compass, and the health line turns Red.

To rebuild: `python tools/prep.py` (backgrounds), `python tools/build_board.py` (board.html), `bash tools/render.sh <name> [width height out]`.

## open
- Check in Studio that Montserrat Light/SemiBold and Roboto Mono Medium exist as built-in weights before building; fallbacks are named in details.
- The spectating mock-up has no contender in frame because no third-person arena capture exists; a real spectate capture would make that picture more convincing.
- Hotbar icons in this style are flat images, one per item, replacing today's 3D viewport icons; that is an art task of its own if the owner picks Style A.

## questions


## files
C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\ui-A\sheet_A.png
C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\ui-A\hud.png
C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\ui-A\lobby.png
C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\ui-A\fallen.png
C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\ui-A\board.png
C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\ui-A\sheet.html
C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\ui-A\hud.html
C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\ui-A\lobby.html
C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\ui-A\fallen.html
C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\ui-A\board.html
C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\ui-A\quiet.css
C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\ui-A\img\bg_hud.jpg
C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\ui-A\img\bg_lobby.jpg
C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\ui-A\img\bg_fallen.jpg
C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\ui-A\img\bg_border.jpg
C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\ui-A\tools\prep.py
C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\ui-A\tools\build_board.py
C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\ui-A\tools\render.sh
C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\ui-A\notes.md