# Using TwinKeys

TwinKeys fires your sound cues on two Macs at once. Open the same Live set on both Macs and map clips to keys: each key you press on the main Mac launches the same clip on the backup Mac too. If the main Mac fails, you can switch to the backup straight away.

Unofficial third-party tool. Not affiliated with Ableton.

## What you need

- Two Macs with macOS 13 or later (main and backup)
- Both on the same network: a wired network, your own router, or one Ethernet cable directly between the two Macs
- The same Live set on both Macs

## First launch

1. On both Macs, open the TwinKeys .dmg and drag TwinKeys to Applications, then open it.
2. When macOS asks about the local network, click Allow.
3. On the main Mac, click Open System Settings… in the box at the top of the window and turn on TwinKeys under Input Monitoring. Come back and click Check Again.
4. On the main Mac, also turn on TwinKeys under Accessibility (System Settings > Privacy & Security > Accessibility). It is used to keep cue keys from other apps. Without it, the window shows a note.

## Pairing code (once)

Both Macs need the same pairing code. Only Macs with the same code can connect, and their traffic is encrypted.

1. On one Mac, click Set Up Pairing Code… and then Make New Code. A code such as K7MQ2-WX9TP appears.
2. On the other Mac, click Set Up Pairing Code… > Enter Code… and type the same 10 characters. Case and hyphens do not matter.
3. The code is kept in the keychain. You do this only once.

## Live settings (both Macs)

1. Open Live's Settings (⌘,) and choose the Link, Tempo & MIDI tab (in Live 11: Preferences > Link/Tempo/MIDI).
2. If your set plays to tempo or bars, turn on Link (it keeps tempo and bar position in sync).
3. In the MIDI ports list, turn on Remote for the input TwinKeys. Track is not needed (with Track on, keys you have not mapped can play armed MIDI tracks).
4. Map your cues: press MIDI at the top right of Live (⌘M) to enter MIDI Map Mode. Click what you want to control (a clip slot, scene up/down, launch the selected scene, the Play or Stop button…), then press one of TwinKeys' cue keys (↓ and so on) on the main Mac. Press MIDI again to finish.
5. Use the same mapping on both Macs (the same Set file is the safest way).
6. If the same keys are mapped in Live's Key Map Mode (⌘K), remove them. Otherwise Live on the main Mac moves twice.
7. Keep each clip's Launch Mode at Trigger. With Gate or Repeat, the clip stops (or stops repeating) as soon as you release the cue key, and also when TwinKeys turns notes off after a network drop.
8. On the main Mac, turn off Live's Computer MIDI Keyboard (shortcut M). Otherwise letter keys also play notes in Live.

## Connecting

1. Open TwinKeys on both Macs.
2. Check Send my keys on the main Mac and Receive notes on the backup Mac.
3. When the other Mac appears under Nearby TwinKeys on the main Mac, click Connect.
4. The top of the window shows Connected to … and the latency.

If the other Mac is not listed, use Connect by IP Address… (⇧⌘K) and type its IP address. The other Mac shows its address under Settings > Pairing Code.

If the network drops, TwinKeys reconnects by itself (every second at first, slowing to every 5 seconds).

## Cue keys

Choose the keys that fire cues in Settings (⌘,) > Cue Keys. ↑ ↓ ← → Space Return Esc are there to begin with. Any key on the Mac can be a cue key.

- Click Add Key… and press the keys you want, one after another. Letters, digits, arrows, Space, F1–F12: any key works.
- "Add A–Z and 0–9" adds all letters and digits at once.
- Remove a key with "−" at the right of its row.
- Give each key a memo (for example "Next scene"). It is shown under Last cue.
- Each cue key sends its own fixed note (MIDI channel 1, from C1 up, velocity 127). Removing other keys does not change the notes of the keys left, so Live's mappings keep working.
- Keys are matched by position, not by letter: JIS and US keyboards give the same cue for the same key.
- Holding a key down sends it once. Keys pressed with ⌘, ⌃, ⌥ or Shift are not sent.
- While "Keep cue keys from other apps (recommended)" is on, cue keys do not reach other apps, Live included. Live on the main Mac then reacts only to TwinKeys' MIDI, exactly like the backup. Turn Key capture off (⌃⌘K) to use the arrows and the other keys normally.

## Last cue and the delivery check

The Last cue box near the top of the window shows:

- The key, its memo, and "Cue n since connecting". The backup shows the same, so comparing the two numbers tells you both Macs are at the same cue. The count starts again after reconnecting.
- **Reached the backup** (green ✓): the backup received the cue.
- **No confirmation** (red): no answer came even after sending the cue again every 0.1 s for about 0.3 s. Check that the cue fired on the backup. It is not sent again after that, because a cue that starts late would do more harm.
- **Delivery cannot be checked**: the other Mac runs TwinKeys older than 1.0.0. Use 1.0.0 or later on both.

Turn Key capture off (⌃⌘K) while typing in other apps.

## Shortcuts

- Connect / Disconnect — ⌘K (when only one other Mac is listed; otherwise click Connect in the list)
- Key capture on / off — ⌃⌘K
- All Notes Off — ⌃⌘P
- Connect by IP Address — ⇧⌘K
- Settings — ⌘,
- This guide — ⌘?

## Updates

- New versions are downloaded in the background (checked a minute after launch and every 6 hours).
- When one is ready, a note appears at the top of the window. The app is replaced **only when TwinKeys quits**: never on its own during a show.
- Restart Now is offered only while not connected.
- The downloaded app is used only if it is signed by the same developer as the running one.
- Turn automatic checks off in Settings > Updates. TwinKeys > Check for Updates… checks at any time.

## Menu bar

- TwinKeys shows a keyboard icon in the menu bar: filled while connected, outlined while not, with "!" while reconnecting.
- Its menu has All Notes Off, Connect, Key capture, Open TwinKeys, Settings, Open at Login, Check for Updates and Quit.
- Closing the window keeps TwinKeys running. Choose Quit TwinKeys (⌘Q) to stop it.
- Settings > Menu Bar has Open at Login and Show only in the menu bar (both off to begin with).

## Stuck notes

- The red All Notes Off button (⌃⌘P) stops every note on this Mac and the connected Mac.
- Quitting TwinKeys and clicking Disconnect also stop notes on both Macs.
- A note whose note-off never arrives stops after 10 seconds (notes whose keys are still held keep playing). Change this in Settings; 0 turns it off. Even at 1–2 seconds, notes received from the other Mac wait at least 3 seconds.
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

**Live moves twice for one cue key**
- Turn on "Keep cue keys from other apps" in Settings and allow TwinKeys under Accessibility.
- Check that the same key is not left in Live's Key Map Mode (⌘K).

**Keys make no sound**
- Check that Input Monitoring is allowed (shown at the bottom of the window).
- Check that Send my keys and Key capture are on.
- Check that the key is one of the cue keys.
- Check that Remote is on for TwinKeys in Live's MIDI settings.
- While you type in a password field (macOS Secure Input), keys are hidden from TwinKeys. The window shows "Key capture: Paused (password field)", and held notes are ended when that starts.

**"Different pairing code" next to the other Mac**
- The two Macs use different codes. On one Mac, choose Connection > Set Up Pairing Code… (or Settings > Pairing Code), click Enter Code… and type the other Mac's code.

**Only Live on the main Mac plays, or it moves twice**
- Turn off Live's Computer MIDI Keyboard on the main Mac.

**Key capture stopped working after an update**
- Turn TwinKeys off and on again in the Input Monitoring and Accessibility lists.

**"Different TwinKeys version" next to the other Mac**
- Install the same version on both Macs.

## Files

- Settings — ~/Library/Application Support/TwinKeys/settings.json
- Logs — ~/Library/Logs/TwinKeys/ (open from the Help menu)

## Credits

Shogo Kajiyama / SEVENTHWELL · MIT License
