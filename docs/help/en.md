# Using TwinKeys

TwinKeys plays the notes you type on the main Mac on a backup Mac at the same time. Open the same Live set on both Macs, and every key you press on the main Mac plays on both.

Unofficial third-party tool. Not affiliated with Ableton.

## What you need

- Two Macs with macOS 13 or later (main and backup)
- Both on the same network: a wired network, your own router, or one Ethernet cable directly between the two Macs
- The same Live set on both Macs

## First launch

1. On both Macs, open the TwinKeys .dmg and drag TwinKeys to Applications, then open it.
2. When macOS asks about the local network, click Allow.
3. On the main Mac, click Open System Settings… in the box at the top of the window and turn on TwinKeys under Input Monitoring. Come back and click Check Again.

## Pairing code (once)

Both Macs need the same pairing code. Only Macs with the same code can connect, and their traffic is encrypted.

1. On one Mac, click Set Up Pairing Code… and then Make New Code. A code such as K7MQ2-WX9TP appears.
2. On the other Mac, click Set Up Pairing Code… > Enter Code… and type the same 10 characters. Case and hyphens do not matter.
3. The code is kept in the keychain. You do this only once.

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

If the other Mac is not listed, use Connect by IP Address… (⇧⌘K) and type its IP address. The other Mac shows its address under Settings > Pairing Code.

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
- Connect by IP Address — ⇧⌘K
- Settings — ⌘,
- This guide — ⌘?

## Stuck notes

- The red All Notes Off button (⌃⌘P) stops every note on this Mac and the connected Mac.
- Quitting TwinKeys and clicking Disconnect also stop notes on both Macs.
- A note whose note-off never arrives stops after 10 seconds (notes whose keys are still held keep playing). Change this in Settings; 0 turns it off. Notes received from the other Mac always wait at least 3 seconds.
- When the network drops, only notes that came from the other Mac stop. Notes you are playing on the main Mac keep sounding.

## Troubleshooting

**"Local Network: Not allowed" is shown**
- TwinKeys could not announce itself on the network. Turn TwinKeys on in System Settings > Privacy & Security > Local Network, then reopen TwinKeys.

**The other Mac does not appear**
- Check that both Macs are on the same network.
- Check that TwinKeys is on in System Settings > Privacy & Security > Local Network.
- Turn off VPN software. Some VPNs send all traffic, including traffic to the other Mac, through the VPN. Also turn off Limit IP Address Tracking for the Wi-Fi network.
- If the firewall is on, open System Settings > Network > Firewall > Options and check that TwinKeys allows incoming connections and that "Block all incoming connections" is off.

**Using one cable between the Macs (no router)**
- Connect the two Macs with one Ethernet cable (or a Thunderbolt/USB-C cable). No settings are needed. After a short wait, System Settings > Network shows "Self-assigned IP" with a yellow dot. That is normal here, and TwinKeys still finds the other Mac.

**The other Mac does not appear on venue or hotel Wi-Fi**
- Many public Wi-Fi networks block devices from seeing each other. Connect the Macs with a cable, or bring your own router.
- Both Macs must be on the same network. If one is on Wi-Fi and the other on a different router or VLAN, they cannot find each other.
- A phone hotspot may work, but some phones block devices from seeing each other. For shows, use a cable or a router.

**Both Wi-Fi and a cable are connected**
- TwinKeys uses the cable. For the steadiest timing, turn Wi-Fi off during the show.

**Keys make no sound**
- Check that Input Monitoring is allowed (shown at the bottom of the window).
- Check that Send my keys and Key capture are on.
- Check that Track is on for TwinKeys in Live's MIDI settings.
- While you type in a password field (macOS Secure Input), keys are hidden from TwinKeys. The window shows "Key capture: Paused", and held notes are ended when that starts.

**"Different pairing code" next to the other Mac**
- The two Macs use different codes. On one Mac, open Set Up Pairing Code… and use Enter Code… to type the other Mac's code.

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
