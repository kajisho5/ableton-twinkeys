# Using TwinKeys

TwinKeys plays the notes you type on the main Mac on a backup Mac at the same time. Open the same Live set on both Macs, and every key you press on the main Mac plays on both.

Unofficial third-party tool. Not affiliated with Ableton.

## What you need

- Two Macs with macOS 13 or later (main and backup)
- Both on the same network (wired, or a dedicated router, works best)
- The same Live set on both Macs

## First launch

1. On both Macs, open the TwinKeys .dmg and drag TwinKeys to Applications, then open it.
2. When macOS asks about the local network, click Allow.
3. On the main Mac, click Open System Settings… in the box at the top of the window and turn on TwinKeys under Input Monitoring. Come back and click Check Again.

## Live settings (both Macs)

1. Open Live's Settings (Preferences in Live 11) and choose the Link, Tempo & MIDI tab.
2. Turn on Link. Link keeps tempo and bar position in sync.
3. In the MIDI ports list, turn on Track and Remote for the input TwinKeys.
4. On the main Mac, turn off Live's Computer MIDI Keyboard (shortcut M). Otherwise each key plays twice.
5. Set the MIDI tracks you want to play to receive from TwinKeys (or All Ins).

## Connecting

1. Open TwinKeys on both Macs.
2. Check Send my keys on the main Mac and Receive notes on the backup Mac.
3. When the other Mac appears under Nearby TwinKeys on the main Mac, click Connect.
4. The top of the window shows Connected to … and the latency.

If the network drops, TwinKeys reconnects by itself (every second at first, slowing to every 5 seconds).

## Playing

The layout is the common DAW computer keyboard:

- A S D F G H J K L ; — white keys (A is C3)
- W E T Y U O P — black keys
- Z / X — octave down / up
- C / V — velocity down / up

Keys are matched by position, not by letter, so JIS and US keyboards play the same notes. Keys pressed with ⌘, ⌃, ⌥ or Shift never play.

Turn Key capture off (⌃⌘K) while typing in other apps.

## Shortcuts

- Connect / Disconnect — ⌘K (when only one other Mac is listed; otherwise click Connect in the list)
- Key capture on / off — ⌃⌘K
- All Notes Off — ⌃⌘P
- Settings — ⌘,
- This guide — ⌘?

## Stuck notes

- The red All Notes Off button (⌃⌘P) stops every note on this Mac and the connected Mac.
- Quitting TwinKeys and clicking Disconnect also stop notes on both Macs.
- A note whose note-off never arrives stops after 10 seconds (notes whose keys are still held keep playing). Change this in Settings; 0 turns it off.
- When the network drops, only notes that came from the other Mac stop. Notes you are playing on the main Mac keep sounding.

## Troubleshooting

**"Local Network: Not allowed" is shown**
- TwinKeys could not announce itself on the network. Turn TwinKeys on in System Settings > Privacy & Security > Local Network, then reopen TwinKeys.

**The other Mac does not appear**
- Check that both Macs are on the same network.
- Check that TwinKeys is on in System Settings > Privacy & Security > Local Network.
- Turn off VPN software and Limit IP Address Tracking for the Wi-Fi network.

**Keys make no sound**
- Check that Input Monitoring is allowed (shown at the bottom of the window).
- Check that Send my keys and Key capture are on.
- Check that Track is on for TwinKeys in Live's MIDI settings.
- While you type in a password field (macOS Secure Input), keys are hidden from TwinKeys. Held notes are ended when that starts.

**Every note plays twice**
- Turn off Live's Computer MIDI Keyboard on the main Mac.

**Key capture stopped working after an update**
- Turn TwinKeys off and on again in the Input Monitoring list.

**"Different TwinKeys version" next to the other Mac**
- Install the same version on both Macs.

## Files

- Settings — ~/Library/Application Support/TwinKeys/settings.json
- Key mapping — ~/Library/Application Support/TwinKeys/mapping.json (after editing, click Reload Mapping in Settings)
- Logs — ~/Library/Logs/TwinKeys/ (open from the Help menu)

## Credits

Shogo Kajiyama / SEVENTHWELL · MIT License
