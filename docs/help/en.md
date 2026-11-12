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

## Controlling Live from an iPhone or iPad (TwinKeys Remote)

TwinKeys Remote controls both Lives from an iPhone or iPad: scenes and clips, play and stop, tempo, the mixer (volume, pan, mute, solo), your cue keys and All Notes Off. The iPhone connects to the main Mac, and the main Mac sends the same action to the backup Mac.

### What you need

- TwinKeys 2.0 or later on both Macs (GO, the set check and sends need 2.1)
- An iPhone or iPad with iOS 17 or later (TestFlight for now); watchOS 10 or later for the Apple Watch
- The iPhone or iPad on the same network as the Macs

### On the Macs (both)

1. Open TwinKeys Settings.
2. Under Live, click **Install into Live**. This puts a small Live part (TwinKeysBridge) into Live's folder.
3. Restart Live. In **Settings > Link, Tempo & MIDI**, choose **TwinKeysBridge** in a free **Control Surface** slot. Input and Output can stay at None.
4. TwinKeys Settings shows **Live: Connected** when it works.
5. On the main Mac, turn on **Allow TwinKeys Remote to connect** under iPhone and iPad (TwinKeys Remote).

When you update TwinKeys, TwinKeysBridge is updated too (2.2 or later). If you are asked to restart Live, do it before the show.

### Connecting the iPhone (once)

1. Open TwinKeys Remote, type the same pairing code as on the Macs and tap **Save**.
2. If iOS asks to find devices on your local network, tap **Allow**.
3. When the main Mac appears under **TwinKeys nearby**, tap **Connect**.
4. The iPhone shows 4 digits and the Mac asks **Allow this iPhone?** with a code. Click **Allow** on the Mac only if the digits match.
5. From then on the app connects when you open it. To take the permission back, click **Remove** under Allowed devices in the Mac's Settings.

### The screens

- **Top bar**: link status (main Mac, latency to the backup), play, stop, tempo, position, All Notes Off and the show lock.
- **Session**: the clip grid. Tap a clip to launch it, an empty slot to stop that track, ▶ at the right to launch the scene. Playing clips show the time left.
- **Mixer**: drag anywhere in a column to set the volume (or pan). The dashed line is 0 dB. M is mute, S is solo.
- **Cues**: the same buttons as the cue keys on the Mac, showing what each one does (the memo written on the Mac), plus the last cue and whether it reached the backup.
- **GO**: uses Live's scene list as the script. Tap the big GO to launch the scene selected in Live on both Macs and move the selection down one. Back and Next only choose; they never play. A second GO within 0.5 s is ignored.
- **Mixer sends**: Send A and Send B in the mixer move the sends to the return tracks (when the set has return tracks).
- The iPhone is meant to be held sideways. In landscape the screen switcher is at the right edge. On an iPad or an open iPhone Duo the screen spreads into two or three columns.

### Checking both Macs

- The Connections row at the top of the Mac window shows the other Mac (Live ✓ and latency), how many iPhones are connected, and their Apple Watch. On the backup Mac it says the iPhone is connected to the main Mac. Click it to open Settings.
- On the iPhone, an Apple Watch mark appears next to the Mac's name in the top bar (green: connected, yellow: not reachable). Tap it to open Settings > Connection.
- "Backup ✓ · Live ✓" in the top bar means the backup Mac and its Live both answer. With "Live ✗ no answer", check Live and TwinKeysBridge on the backup Mac.
- When the two Macs have different sets open, a yellow bar "Backup's set differs" appears (on the Mac too). Tap it for the tracks and scenes that differ. Only track and scene counts and names are compared, and nothing is changed automatically.
- Fader, pan, tempo, mute and solo changes made while the link to the backup was down are sent when it is back. Clip and scene launches are not sent late, because a late launch is dangerous.
- The backup Mac reports whether each action also ran in its Live (TwinKeys 2.2 or later). If it did not, you see for example "Ran on the main Mac, but the backup's Live refused it."
- When Live is slow to answer you see "No answer from Live". If it then runs after all, you see "Live ran it after all (late). Do not tap again."
- If Live's tracks or scenes changed since the screen was drawn (for example right after adding a track), the action is not sent and you see "Live's tracks or scenes changed, so it was not sent." Tap again.

### Safety during the show

- **Stop** and **Stop all clips** need a long press.
- The **show lock** (the lock button) freezes tempo and the mixer. Play, stop, clips, scenes and cues still work. Hold the lock for 1 second to unlock.
- Choose what the show lock stops in Settings > What the show lock stops (tempo, mixer, clip and scene launches, stops, cue buttons). GO, All Notes Off and unlocking are never stopped. These cannot be changed while the lock is on.
- With **Faders stop at 0 dB** on (in Settings), the volume never goes above 0 dB.

### When the main Mac stops (switching to the backup)

TwinKeys 2.2 or later. On the backup Mac, also turn on **Allow TwinKeys Remote to connect**, and allow this iPhone there once.

- When the main Mac has not answered for 3 seconds, the iPhone shows "The main Mac is not answering". The screens stay usable (they show the last state).
- Tap "Switch to the backup" and hold "Hold to switch" for 1 second. The iPhone connects to the backup Mac and that Mac becomes the main; its keyboard fires the cues too.
- To switch on the Macs alone, click "Make This Mac the Main" on the backup Mac.
- When the old main Mac comes back, it only receives (the two Macs never send keys at the same time). To switch back, click "Make This Mac the Main" on the old main Mac, or "Return to Main" on the current main Mac.

### Apple Watch

TwinKeys Remote 1.2 or later. TwinKeys appears on the Apple Watch (watchOS 10 or later). The watch works through the iPhone, so keep TwinKeys Remote open on the iPhone and connected to the main Mac. The show lock applies as on the iPhone.

- **GO**: plays the scene shown as Next on both Macs. Turn the Digital Crown to choose back or next (choosing does not play). A second GO within 0.5 seconds is ignored.
- **Choose scene**: the scene list. Tap a scene to make it Next (does not play).
- **All Notes Off**: stops every note on both Macs. The link status and the last cue are shown too.
- Swipe left or right to switch pages.

### Trying it without a Mac

Tap "Try with sample data" on the pairing screen to try the screens with made-up data. Nothing is sent to a Mac. To end it, tap "End the sample and connect to a Mac" in Settings.

## Switching a Yamaha console's faders too (experimental)

An experimental feature of TwinKeys 2.4 or later, off to begin with. Until it has been checked on real consoles, always try it in a rehearsal before a show.

When the main Mac stops, the backup Mac moves the faders of a Yamaha console: it raises the channels that carry the backup Mac's sound to the level the main Mac's channels had just before, and at the same time pulls the main Mac's channels to −∞.

### What it moves

- Only fader levels. EQ, dynamics, routing, scenes and channel ON are never touched.
- Only the backup Mac connects to the console (when the main Mac stops, the Mac still running moves it).

### Consoles

- QL1 (inputs 1–32, ST IN 1–8), QL5 (inputs 1–64, ST IN 1–8)
- DM3 / DM3 Standard (inputs 1–16, ST IN 1)
- DM7 (inputs 1–120), DM7 Compact (inputs 1–72)
- DM5 (inputs 1–60), DM5 Compact (inputs 1–48)
- Reading levels (`get` and the console's `NOTIFY` on TCP 49280) is not in Yamaha's documents; there are only reports from people who use it (QL5, DM7, DM7 Compact). Whether DM5 and DM5 Compact can be read has not been checked yet.
- Writing levels uses Yamaha's own script example for QL (TCP 49280) and Yamaha's OSC specifications for DM3, DM5 and DM7 (UDP 49900).
- When levels cannot be read, each backup channel goes to the level set in its row (with "Raise to set levels" on; DM consoles get it over Yamaha's OSC). QL has no OSC, so while it cannot be reached it cannot be moved.

### Setting it up on the backup Mac

1. Find the console's "For Mixer Control" IP address and connect the backup Mac to the same network as the console.
2. On the backup Mac, open Settings (⌘,) > Console (Yamaha) and check "Turn on the experimental feature".
3. Choose the console model, type its IP address and click Check Connection. Green "Connected to QL5 · Reading fader levels" means levels are read. Yellow "Levels cannot be read: raises to the set levels" means each backup channel goes to its row's set level. Red means the console cannot be reached.
4. Under Channel assignment, click "+ Add Row" and enter, row by row, the channel that carries the main Mac's sound and the channel that carries the backup Mac's sound. Numbers are as on the console (from 1); numbers above the model's limit cannot be entered. An ST IN row moves L and R together.
5. While levels are read, each row shows the main channel's level now. Move a fader on the console and it changes right away.
6. Choose When switching (After confirming, Automatically), the Fade time (Instant, 0.5 s, 1 s, 2 s) and "Pull the main channels to −∞".

### Switching

- **After confirming** (the default): "Make this Mac the main Mac?" also shows "Also switch the console's faders (QL5: 4 rows, 0.5 s)". Leave it checked and click Make It the Main to switch the console too. Your answer is remembered and also used when an iPhone switches to this Mac.
- When the console is not connected, or the levels read are old (not updated for 2 seconds or more), the confirmation says "The console cannot be moved" and only the Mac switches.
- **Automatically**: when the main Mac has not answered for 3 seconds, only the console's faders are switched, once (the Macs' roles still switch only by a person or an iPhone, as before). It may also move when the network drops for a moment, so choosing it asks first. It never moves the console when it is not connected or the levels are old.
- After switching, the window says "Console switched (0.5 s)". The levels are read back from the console; any channel that did not end up where it should is shown in yellow.
- "Restore the Console" puts the backup channels back to their levels before the switch and the main channels back to theirs.
- The Connections row at the top shows "Console QL5 ✓": green "Reading levels", yellow "Raises to set levels" or "Not connected".

### Trying it without a console

- A small fake console, `scripts/fake-yamaha-desk.py` (Python 3 only), is in the source code on GitHub.
- Run `python3 scripts/fake-yamaha-desk.py --model ql5 --set 1=-6 --set 9=-inf` in Terminal and enter the IP address of the Mac running it in TwinKeys (127.0.0.1 on the same Mac).
- Type `in 1 -10` in its Terminal window to move a fader as if on the console. `--no-read` acts like a console whose levels cannot be read, and `--model dm5` (and so on) changes the model.
- Try it on a receiving Mac too ("Send my keys" off).

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

**The Mac does not appear on the iPhone**
- Check that the iPhone and the Mac are on the same network.
- On the iPhone, turn on TwinKeys Remote in Settings > Privacy & Security > Local Network.
- On the main Mac, check that **Allow TwinKeys Remote to connect** is on.

**The iPhone says the pairing code does not match the Mac**
- Use the same pairing code on the iPhone as in the Mac's Settings > Pairing Code.

**Nothing happens in Live when you use the iPhone**
- The Mac's Settings should show **Live: Connected**. If not, check that **TwinKeysBridge** is chosen as a Control Surface in Live.
- While the show lock is on, tempo and the mixer do not move.

## Files

- Settings — ~/Library/Application Support/TwinKeys/settings.json
- Logs — ~/Library/Logs/TwinKeys/ (open from the Help menu)

## Credits

Shogo Kajiyama / SEVENTHWELL · MIT License
