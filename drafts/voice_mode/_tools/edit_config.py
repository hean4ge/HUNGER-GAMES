"""Apply the same Config.Voice edits to Config.lua and Config.Voice.snippet.lua (kept identical). Usage: python -I edit_config.py <Shared dir>"""
import os
import sys

EDITS = [
    (
        "\tDefaultOn = true, -- a player's Proximity voice choice until they make one (settings.voiceOn)\n"
        "\tJoinMuteTime = 20, -- a joiner stays muted while their saved choice loads, at most this many seconds\n",
        "\tDefaultOn = true, -- the choice of a player who never made one, once their saved settings have loaded\n"
        "\t-- (There is no time limit: a player stays muted until DataService says their settings loaded, or they choose.\n"
        "\t-- A failed load keeps them muted, with a note on the lobby card, until they turn voice on themselves.)\n",
    ),
    (
        "\tSpectators = {\n"
        "\t\tHearArena = true, -- spectators hear the arena around the contender they watch\n"
        "\t\tListenAt = \"Target\", -- \"Target\": through the watched contender's ears; \"Camera\": from the orbiting camera\n"
        "\t\tVolume = 0.85, -- the other spectators' voices (no distance: the stands share one channel)\n"
        "\t},\n",
        "\tSpectators = {\n"
        "\t\tHearArena = true, -- spectators hear the arena around the contender they watch\n"
        "\t\tListenAt = \"Target\", -- \"Target\": through the watched contender's ears (Custom); \"Camera\": from the orbit camera\n"
        "\t\t-- The stands' channel: while you spectate, the other spectators come in with no distance. It wires their voice\n"
        "\t\t-- devices straight to this client, so it stays off until the published safety gate shows Roblox's own mute, block,\n"
        "\t\t-- voice volume and age rules reach it (VoiceMode.md, test plan G1-G6).\n"
        "\t\tStandsBus = false,\n"
        "\t\tVolume = 0.85, -- the stands' channel volume\n"
        "\t},\n",
    ),
    (
        "\t-- \"Custom\": our own listener and an emitter per speaker (volume, muffling, whisper reach). \"Engine\": our listener with\n"
        "\t-- Roblox's emitters (volume, no muffling): the fallback if a published test hears nothing through the custom chain.\n"
        "\t-- \"Default\": Roblox's own listener and playback, untouched; we only shape Roblox's emitters (curves, your mutes) and\n"
        "\t-- add the stands' bus (Voice volume then sets the stands only): the fallback if Roblox's own mute or volume\n"
        "\t-- controls turn out not to reach our listener.\n"
        "\tClientGraph = \"Custom\",\n",
        "\t-- \"Default\" (the safe setting): Roblox's own listener and playback, untouched. We only give Roblox's emitters our\n"
        "\t-- distance curves, and move one to a silent group while you mute that player or turn voice off (and move it back\n"
        "\t-- once, only if nothing else changed it). Roblox's own mute, block and volume controls keep working as Roblox built\n"
        "\t-- them. \"Custom\": our own listener and an emitter per speaker, wired from each voice device (Voice volume,\n"
        "\t-- muffling by walls, listening through the watched contender's ears). Switch to \"Custom\" (and StandsBus on) only\n"
        "\t-- after the published safety gate passes (VoiceMode.md, test plan G1-G6). (\"Engine\" is gone: it rewrote Roblox's own\n"
        "\t-- emitters every half second, which could undo Roblox's own mute.)\n"
        "\tClientGraph = \"Default\",\n",
    ),
]


def main() -> None:
    shared = sys.argv[1]
    for name in ("Config.lua", "Config.Voice.snippet.lua"):
        path = os.path.join(shared, name)
        with open(path, encoding="utf-8", newline="") as f:
            text = f.read()
        for i, (old, new) in enumerate(EDITS):
            n = text.count(old)
            assert n == 1, f"{name}: edit {i + 1} matched {n} times"
            text = text.replace(old, new, 1)
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        print("edited", name)


if __name__ == "__main__":
    main()
