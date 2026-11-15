"""SUPERSEDED (14 November, lead review): the drafts in voice_mode/src are now edited directly and are the source of
truth, with patches/voice_mode.diff made from them by make_diff.py. Re-running this would overwrite those edits with
the first drafts, so it refuses unless --force is given. Kept for the record.

Apply the Proximity Voice edits to copies of the repo's scripts (never the repo itself).

Each edit is an exact (old, new) pair that must match exactly once, so a drifted source fails loudly.
Usage: python -I make_patches.py <repo_root> <voice_mode_root>
Writes <voice_mode_root>/src/<same path> for every patched file, LF line endings kept.
"""
import os
import sys

REPO, OUT = (sys.argv[1], sys.argv[2]) if len(sys.argv) > 2 else ("", "")


def snippet_block() -> str:
    path = os.path.join(OUT, "src", "ReplicatedStorage", "Shared", "Config.Voice.snippet.lua")
    with open(path, encoding="utf-8", newline="") as f:
        text = f.read()
    # drop the two MERGE lines and the blank line after them
    start = text.index("-- Proximity Voice (docs/design/VoiceMode.md)")
    return text[start:]


EDITS = {
    "ReplicatedStorage/Shared/Config.lua": [
        (
            "Config.Studio = {\n\t-- Only applied inside Roblox Studio.",
            None,  # filled below: the Config.Voice block goes in front
        ),
    ],
    "ReplicatedStorage/Shared/Net.lua": [
        (
            '"SetStance", "SaveSettings", "SpectateTarget", "TakeWorldItem",\n}',
            '"SetStance", "SaveSettings", "SpectateTarget", "TakeWorldItem", "VoiceRequest",\n}',
        ),
    ],
    "ReplicatedStorage/Shared/Lore.lua": [
        (
            'Lore.WaitingGrounds = "the Waiting Grounds" -- the Tor\'s courtyard\n',
            'Lore.WaitingGrounds = "the Waiting Grounds" -- the Tor\'s courtyard\n'
            'Lore.Stands = "the stands" -- during a round, everyone not in the arena: the fallen, spectators, the lobby (Proximity Voice)\n',
        ),
    ],
    "ServerScriptService/Server/Main.server.lua": [
        (
            '"CombatService", "ProjectileService", "ArenaService", "RoundService",\n}',
            '"CombatService", "ProjectileService", "ArenaService", "RoundService", "VoiceService",\n}',
        ),
    ],
    "StarterPlayer/StarterPlayerScripts/Client/ClientMain.client.lua": [
        (
            '"NotificationController", "SpectateController",\n}',
            '"NotificationController", "SpectateController", "VoiceController",\n}',
        ),
    ],
    "StarterPlayer/StarterPlayerScripts/Client/ClientState.lua": [
        (
            "\t\ttouchLook = 1, -- touch look speed (x)\n\t},\n",
            "\t\ttouchLook = 1, -- touch look speed (x)\n"
            "\t\t-- Proximity Voice (Config.Voice; SettingsController's VOICE rows, DataService saves them):\n"
            "\t\tvoiceOn = if (Config.Voice or {}).DefaultOn == false then 0 else 1, -- 0 Off, 1 On (the lobby card's choice)\n"
            "\t\tvoiceVolume = 1, -- 0..2: other players' voices\n"
            "\t\tvoiceTips = 0, -- the voice tips' show counters, 2 bits per tip (VoiceController)\n"
            "\t},\n",
        ),
        (
            "\t-- SpectateController writes:\n\tspectating = nil :: Player?,\n",
            "\t-- SpectateController writes:\n\tspectating = nil :: Player?,\n\n"
            "\t-- VoiceController writes (Proximity Voice, Config.Voice):\n"
            "\tvoice = {\n"
            "\t\tavailable = false, -- this account can use voice here (Roblox voice on, 13+ and age-checked)\n"
            "\t\tconnected = false, -- Roblox has made this player's voice device\n"
            "\t\ton = true, -- the player's choice (settings.voiceOn)\n"
            "\t\tmicOn = false, -- Roblox's own mic toggle (AudioDeviceInput.Active)\n"
            "\t\ttalking = false, -- the player is talking right now\n"
            '\t\tchannel = "", -- who hears you: "Nearby" | "Stands" | "Whisper" | "Off" | "" (no voice)\n'
            "\t\twatching = 0, -- other spectators in the stands' channel\n"
            "\t},\n",
        ),
        (
            "ClientState.spectateChanged = Signal.new() -- (player?)                            SpectateController\n",
            "ClientState.spectateChanged = Signal.new() -- (player?)                            SpectateController\n"
            "ClientState.voiceChanged = Signal.new() -- (voice)                                 VoiceController\n",
        ),
    ],
    "ServerScriptService/Server/Services/RoundService.lua": [
        (
            "\t  RoundService.isContender(player) -> boolean         picked for the current round\n",
            "\t  RoundService.isContender(player) -> boolean         picked for the current round\n"
            "\t  RoundService.isRoundRunning() -> boolean           a round is under way (Countdown, Active and the pre-arena phases\n"
            "\t                                                      named in Config.Voice.RoundPhases): VoiceService's bench rule\n",
        ),
        (
            "function RoundService.isContender(player: Player): boolean\n\treturn contenders[player] ~= nil\nend\n",
            "function RoundService.isContender(player: Player): boolean\n\treturn contenders[player] ~= nil\nend\n\n"
            "-- A round is under way: its contenders are picked, and the bench (the fallen, late joiners) must not reach them by voice\n"
            "-- (VoiceService). Countdown and Active today; the coming train, training room and launch phases join through\n"
            "-- Config.Voice.RoundPhases.\n"
            "function RoundService.isRoundRunning(): boolean\n"
            '\tif phase == "Countdown" or phase == "Active" then\n'
            "\t\treturn true\n"
            "\tend\n"
            "\tlocal extra = Config.Voice and Config.Voice.RoundPhases\n"
            '\treturn type(extra) == "table" and extra[phase] == true\n'
            "end\n",
        ),
    ],
    "ServerScriptService/Server/Services/PlayerService.lua": [
        (
            "\tRemote: SpectateTarget(target: Player?) points the requester's ReplicationFocus at an alive contender.\n",
            "\tRemote: SpectateTarget(target: Player?) points the requester's ReplicationFocus at an alive contender, and sets their\n"
            "\tSpectating attribute (true while they watch someone: Proximity Voice's stands channel). A contender's death moves\n"
            "\ttheir voice to the bench at once (VoiceService.onEliminated), before the cannon.\n",
        ),
        (
            "function PlayerService.clearSpectate(player: Player)\n"
            "\tspectateTargets[player] = nil\n"
            "\tif player.Parent == Players then\n"
            "\t\tplayer.ReplicationFocus = nil\n"
            "\tend\n"
            "end\n",
            "function PlayerService.clearSpectate(player: Player)\n"
            "\tspectateTargets[player] = nil\n"
            "\tif player.Parent == Players then\n"
            "\t\tplayer.ReplicationFocus = nil\n"
            '\t\tif player:GetAttribute("Spectating") == true then\n'
            '\t\t\tplayer:SetAttribute("Spectating", false)\n'
            "\t\tend\n"
            "\tend\n"
            "end\n",
        ),
        (
            "local function releaseSpectatorsOf(target: Player)\n",
            "-- (Spectating stays true here: the requester's SpectateController moves on to the next contender by itself.)\n"
            "local function releaseSpectatorsOf(target: Player)\n",
        ),
        (
            "\t\t\tspectateTargets[player] = target\n\t\t\tplayer.ReplicationFocus = root\n\t\t\treturn\n",
            "\t\t\tspectateTargets[player] = target\n\t\t\tplayer.ReplicationFocus = root\n"
            '\t\t\tplayer:SetAttribute("Spectating", true)\n'
            "\t\t\treturn\n",
        ),
        (
            '\t\tvictim:SetAttribute("KilledBy", if killer then killer.UserId else 0) -- SpectateController opens on the killer (QW4)\n',
            '\t\tvictim:SetAttribute("KilledBy", if killer then killer.UserId else 0) -- SpectateController opens on the killer (QW4)\n'
            "\t\t-- Proximity Voice: the fallen join the bench now, before the cannon, so not a word reaches the living from the body\n"
            '\t\tcall("VoiceService", "onEliminated", victim)\n',
        ),
    ],
    "ServerScriptService/Server/Services/DataService.lua": [
        (
            "the sprint / crouch modes, padLook, touchLook; values clamped;",
            "the sprint / crouch modes, padLook, touchLook,\n"
            "\t        voiceOn, voiceVolume, voiceTips (Proximity Voice); values clamped;",
        ),
        (
            "\ttouchLook = { 0.5, 2 }, -- touch look speed (x)\n}\n",
            "\ttouchLook = { 0.5, 2 }, -- touch look speed (x)\n"
            "\t-- Proximity Voice (Config.Voice; SettingsController's VOICE rows, VoiceController)\n"
            "\tvoiceOn = { 0, 1 }, -- 0 Off, 1 On\n"
            "\tvoiceVolume = { 0, 2 },\n"
            "\tvoiceTips = { 0, 255 }, -- the voice tips' show counters\n"
            "}\n",
        ),
    ],
    "StarterPlayer/StarterPlayerScripts/Client/Controllers/SettingsController.lua": [
        (
            "\t  Hidden settings (no row) are saved the same way: hintsSeen (Shared.ActionHints' fade counters).\n",
            "\t  Hidden settings (no row) are saved the same way: hintsSeen (Shared.ActionHints' fade counters).\n"
            "\t  Proximity Voice (Config.Voice.Enabled): a VOICE section (Proximity voice Off / On, Voice volume 0-200%) and an\n"
            "\t  action row, \"Players and muting\", that opens VoiceController's panel. The voice rows show only while this account\n"
            "\t  can use voice (ClientState.voice.available). Hidden: voiceTips (the voice tips' counters).\n"
            "\t  A def may carry visible = () -> boolean (rows and sections); an action row ({ action, label, value? }) has no\n"
            "\t  slider, saves nothing and runs its action when pressed.\n",
        ),
        (
            'local Sfx = require(Shared:WaitForChild("Sfx"))\n',
            'local Sfx = require(Shared:WaitForChild("Sfx"))\nlocal Config = require(Shared:WaitForChild("Config"))\n',
        ),
        (
            "local SettingsController = {}\nSettingsController.menuChanged = Signal.new()\n",
            "local SettingsController = {}\nSettingsController.menuChanged = Signal.new()\nlocal Controllers: any = nil\n",
        ),
        (
            "SettingsController.DEFS = DEFS\n",
            "-- Proximity Voice (Config.Voice): its rows show only while this account can use voice (VoiceController publishes it).\n"
            "if Config.Voice and Config.Voice.Enabled == true then\n"
            "\tlocal function voiceRows(): boolean\n"
            "\t\tlocal voice = ClientState.voice\n"
            '\t\treturn type(voice) == "table" and voice.available == true\n'
            "\tend\n"
            "\tlocal function voicePlayers(): string\n"
            "\t\tlocal vc = Controllers and Controllers.VoiceController\n"
            "\t\tlocal n = if vc and vc.mutedCount then vc.mutedCount() else 0\n"
            '\t\treturn if n > 0 then string.format("%d MUTED  ›", n) else "›"\n'
            "\tend\n"
            '\ttable.insert(DEFS, { section = "VOICE", visible = voiceRows })\n'
            '\ttable.insert(DEFS, { key = "voiceOn", label = "Proximity voice", min = 0, max = 1, step = 1, format = words({ "Off", "On" }), visible = voiceRows })\n'
            '\ttable.insert(DEFS, { key = "voiceVolume", label = "Voice volume", min = 0, max = 2, step = 0.05, format = percent, visible = voiceRows })\n'
            '\ttable.insert(DEFS, { action = "VoicePlayers", label = "Players and muting", value = voicePlayers, visible = voiceRows })\n'
            '\ttable.insert(DEFS, { key = "voiceTips", hidden = true, min = 0, max = 255, step = 1, format = tostring })\n'
            "end\n"
            "SettingsController.DEFS = DEFS\n",
        ),
        (
            "local rowOrder: { any } = {}\n",
            "local rowOrder: { any } = {}\nlocal extraRows: { any } = {} -- sections and action rows that have a visible() rule\n",
        ),
        (
            "local function rowShown(entry): boolean\n"
            "\treturn entry.def.device == nil or entry.def.device == Input.device()\n"
            "end\n",
            "local function rowShown(entry): boolean\n"
            "\tlocal def = entry.def\n"
            "\tif def.visible and not def.visible() then\n"
            "\t\treturn false\n"
            "\tend\n"
            "\treturn def.device == nil or def.device == Input.device()\n"
            "end\n",
        ),
        (
            "local function refreshRowVisibility()\n"
            "\tfor _, entry in pairs(rows) do\n"
            "\t\tlocal on = rowShown(entry)\n"
            "\t\tif entry.row.Visible ~= on then\n"
            "\t\t\tentry.row.Visible = on\n"
            "\t\tend\n"
            "\tend\n",
            "local function refreshRowVisibility()\n"
            "\tfor _, entry in pairs(rows) do\n"
            "\t\tlocal on = rowShown(entry)\n"
            "\t\tif entry.row.Visible ~= on then\n"
            "\t\t\tentry.row.Visible = on\n"
            "\t\tend\n"
            "\tend\n"
            "\tfor _, entry in ipairs(extraRows) do -- sections and action rows (no slider)\n"
            "\t\tlocal on = rowShown(entry)\n"
            "\t\tif entry.row.Visible ~= on then\n"
            "\t\t\tentry.row.Visible = on\n"
            "\t\tend\n"
            "\t\tif entry.value and entry.def.value then\n"
            "\t\t\tentry.value.Text = entry.def.value()\n"
            "\t\tend\n"
            "\tend\n",
        ),
        (
            "local function buildRows()\n",
            "-- Action rows (no slider): what they open.\n"
            "local function runAction(action: string)\n"
            '\tif action == "VoicePlayers" then\n'
            "\t\tlocal vc = Controllers and Controllers.VoiceController\n"
            "\t\tif vc and vc.openPanel then\n"
            "\t\t\tvc.openPanel() -- closes this menu and opens the VOICE panel\n"
            "\t\tend\n"
            "\tend\n"
            "end\n\n"
            "local function buildRows()\n",
        ),
        (
            "\t\t\tsection.LayoutOrder = i\n"
            "\t\t\tsection.Parent = list\n"
            "\t\telseif not def.hidden then\n",
            "\t\t\tsection.LayoutOrder = i\n"
            "\t\t\tsection.Parent = list\n"
            "\t\t\tif def.visible then\n"
            "\t\t\t\ttable.insert(extraRows, { row = section, def = def })\n"
            "\t\t\tend\n"
            "\t\telseif def.action then\n"
            "\t\t\t-- an action row: the slider row without its track; the value says where it leads\n"
            "\t\t\tlocal row = templates.SliderRow:Clone()\n"
            "\t\t\trow.Name = def.action\n"
            "\t\t\trow.LayoutOrder = i\n"
            "\t\t\trow.Size = UDim2.new(1, 0, 0, 44)\n"
            "\t\t\trow.Label.Text = def.label\n"
            "\t\t\trow.Track.Visible = false\n"
            '\t\t\trow.Value.Text = if def.value then def.value() else "›"\n'
            "\t\t\trow.SelectionImageObject = templates.Selection\n"
            "\t\t\trow.Parent = list\n"
            "\t\t\tlocal entry = { row = row, def = def, value = row.Value }\n"
            "\t\t\ttable.insert(extraRows, entry)\n"
            "\t\t\ttable.insert(rowOrder, entry)\n"
            "\t\t\tstyleButton(row, function(on)\n"
            "\t\t\t\tTheme.tween(row, Theme.Tween.Fast, { BackgroundTransparency = if on then 0.62 else 1 })\n"
            "\t\t\t\tentry.value.TextColor3 = if on then C.Text else C.TextDim\n"
            "\t\t\tend)\n"
            "\t\t\trow.Activated:Connect(function()\n"
            '\t\t\t\tSfx.play("UIClick")\n'
            "\t\t\t\trunAction(def.action)\n"
            "\t\t\tend)\n"
            "\t\telseif not def.hidden then\n",
        ),
        (
            "function SettingsController.Init(_registry)\n",
            "function SettingsController.Init(registry)\n\tControllers = registry\n",
        ),
        (
            "\tClientState.settingsChanged:Connect(applyControls)\n",
            "\tClientState.settingsChanged:Connect(applyControls)\n"
            "\tif ClientState.voiceChanged then\n"
            "\t\tClientState.voiceChanged:Connect(refreshRowVisibility) -- the VOICE rows appear once voice is known to work here\n"
            "\tend\n",
        ),
    ],
    "StarterPlayer/StarterPlayerScripts/Client/Controllers/LobbyController.lua": [
        (
            "\tPublic API (Controllers.LobbyController): setHowToVisible(visible: boolean)\n",
            "\tPublic API (Controllers.LobbyController): setHowToVisible(visible: boolean)\n"
            "\t  mountCard(card: GuiObject, order: number?)   adds a card to the left column (VoiceController's PROXIMITY VOICE\n"
            "\t                                               card, order 7: under the buttons); it shows and hides with the\n"
            "\t                                               lobby, and the column grows to fit it\n",
        ),
        (
            "local howToTouched = false -- the player opened or closed HOW TO PLAY themselves: leave it as they set it\n",
            "local howToTouched = false -- the player opened or closed HOW TO PLAY themselves: leave it as they set it\n"
            "local mounted: { GuiObject } = {} -- cards other controllers added to the left column (mountCard)\n"
            "local brandHeight: number? = nil -- the left column's height as UIBuilder made it\n",
        ),
        (
            "function LobbyController.Init(registry)\n",
            "-- The left column grows by the cards mounted into it, so its bottom-aligned list keeps everything inside it.\n"
            "local function fitBrand()\n"
            "\tlocal brand = R.brand\n"
            "\tif not brand or not brandHeight then\n"
            "\t\treturn\n"
            "\tend\n"
            "\tlocal extra = 0\n"
            "\tfor _, card in ipairs(mounted) do\n"
            "\t\tif card.Parent == brand and card.Visible then\n"
            "\t\t\textra += card.Size.Y.Offset + 8 -- (the column's list padding)\n"
            "\t\tend\n"
            "\tend\n"
            "\tbrand.Size = UDim2.fromOffset(brand.Size.X.Offset, brandHeight + extra)\n"
            "end\n\n"
            "function LobbyController.mountCard(card: GuiObject, order: number?)\n"
            "\tcard.LayoutOrder = order or 7\n"
            "\tif not table.find(mounted, card) then\n"
            "\t\ttable.insert(mounted, card)\n"
            '\t\tcard:GetPropertyChangedSignal("Size"):Connect(fitBrand)\n'
            '\t\tcard:GetPropertyChangedSignal("Visible"):Connect(fitBrand)\n'
            "\tend\n"
            "\tif R.brand then\n"
            "\t\tcard.Parent = R.brand\n"
            "\t\tfitBrand()\n"
            "\tend\n"
            "end\n\n"
            "function LobbyController.Init(registry)\n",
        ),
        (
            "\tR.title.Text = Config.GameTitle\n",
            "\tR.title.Text = Config.GameTitle\n"
            "\tbrandHeight = R.brand.Size.Y.Offset\n"
            "\tfor _, card in ipairs(mounted) do -- cards mounted before the lobby screen was ready\n"
            "\t\tcard.Parent = R.brand\n"
            "\tend\n"
            "\tfitBrand()\n",
        ),
    ],
}


def main() -> None:
    if "--force" not in sys.argv:
        raise SystemExit("make_patches.py is superseded: the drafts in src/ are the source of truth (see make_diff.py)")
    block = snippet_block()
    old, _ = EDITS["ReplicatedStorage/Shared/Config.lua"][0]
    EDITS["ReplicatedStorage/Shared/Config.lua"][0] = (old, block + "\n" + old)

    for rel, edits in EDITS.items():
        src = os.path.join(REPO, "src", *rel.split("/"))
        with open(src, encoding="utf-8", newline="") as f:
            text = f.read()
        assert "\r\n" not in text, f"{rel}: CRLF in source"
        for i, (old, new) in enumerate(edits):
            count = text.count(old)
            assert count == 1, f"{rel}: edit {i + 1} matched {count} times"
            text = text.replace(old, new, 1)
        dst = os.path.join(OUT, "src", *rel.split("/"))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        print(f"patched {rel} ({len(edits)} edits)")


if __name__ == "__main__":
    main()
