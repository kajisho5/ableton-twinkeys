# Manual test checklist (two Macs)

TwinKeys is an unofficial third-party tool, not affiliated with Ableton. "Live" below means Ableton Live, used only to name the software it is tested with.

Real-hardware checks that unit tests cannot cover. Run every item on **Live 11** and **Live 12**, and record each result separately.

- Result values: `OK` / `NG` (write what happened in Notes) / `—` (not run)
- Use fictional names for the Macs (for example "Main Test Mac" and "Backup Test Mac").

## Test record

| Item | Value |
|---|---|
| Date | |
| Tester | |
| TwinKeys version (About TwinKeys) | |
| Main Mac: model / macOS version | |
| Backup Mac: model / macOS version | |
| Live 11 version (exact, e.g. 11.x.x) | |
| Live 12 version (exact, e.g. 12.x.x) | |
| Network (wired / Wi-Fi / router model) | |

## 0. Install and first launch

| # | Step | Expected | Live 11 | Live 12 | Notes |
|---|---|---|---|---|---|
| 0-1 | Open the release .dmg and drag TwinKeys to Applications on both Macs. Open it (README > Download and first launch). | TwinKeys opens without a Gatekeeper warning. The window shows "Not connected". | | | |
| 0-2 | Open **Audio MIDI Setup** > Window > Show MIDI Studio. | A device named **TwinKeys** is present while TwinKeys runs. | | | |
| 0-3 | In Live: Settings/Preferences > Link, Tempo & MIDI. | Input **TwinKeys** is listed. Turn on **Track** and **Remote**. Turn **Link** on. | | | |
| 0-4 | Quit and reopen TwinKeys, then reopen Live. | Live keeps the TwinKeys Track/Remote settings. | | | |
| 0-5 | Measure start-up: double-click TwinKeys and count until the window appears. | Under 1 second. | | | |
| 0-6 | Activity Monitor > Memory, TwinKeys, after 10 minutes connected. | Around 50 MB or less (write the value). | | | |

## 1. Permissions not granted

| # | Step | Expected | Live 11 | Live 12 | Notes |
|---|---|---|---|---|---|
| 1-1 | Main Mac: System Settings > Privacy & Security > Input Monitoring: turn TwinKeys **off** (or remove it). Open TwinKeys. | No crash. A yellow banner "Key capture needs Input Monitoring permission." with **Open System Settings…** and **Check Again**. Bottom row: "Input Monitoring: Not allowed". | | | |
| 1-2 | Click **Open System Settings…**, allow TwinKeys, return and click **Check Again** (reopen TwinKeys if macOS asks). | Banner disappears; "Key capture: On"; keys play notes. | | | |
| 1-3 | macOS 15 or later, both Macs: Privacy & Security > Local Network: turn TwinKeys **off**. Open TwinKeys. | No crash. Within about 10 s the bottom row shows "Local Network: Not allowed" and the empty state says macOS is blocking local network access. | | | |
| 1-4 | Click **How to Fix…**, follow the steps, turn Local Network on. | The other Mac appears in Nearby TwinKeys. | | | |
| 1-5 | First launch on a fresh Mac. | macOS asks for Local Network (macOS 15+) and possibly the firewall. After Allow, peers appear. | | | |

## 2. Discovery and connection

| # | Step | Expected | Live 11 | Live 12 | Notes |
|---|---|---|---|---|---|
| 2-1 | Open TwinKeys on both Macs. | Each Mac lists the other one, not itself. | | | |
| 2-2 | Only one Mac running TwinKeys. | Empty state "No TwinKeys found on this network" with guidance. | | | |
| 2-3 | Main: check Send my keys. Backup: check Receive notes. Main: click **Connect** next to the backup. | Both headers show "Connected to …" and latency in ms. The row is highlighted. | | | |
| 2-4 | Watch latency for 1 minute on a wired network, then on Wi-Fi. | Value updates about once per second. Write typical values. | | | |
| 2-5 | Press ⌘K on the main Mac. | Disconnects. Press again: reconnects (when only one peer is listed). | | | |

## 3. Playing on both Macs (simultaneous trigger)

Prepare the same set on both Macs: one MIDI track with an instrument, input from TwinKeys, monitor In (or armed). On the main Mac turn **off** Live's computer MIDI keyboard.

| # | Step | Expected | Live 11 | Live 12 | Notes |
|---|---|---|---|---|---|
| 3-1 | Main: press A, hold, release. | Both Macs play C3 and stop on release. Main shows "Held notes C3" while held. | | | |
| 3-2 | Press A, D, G together (chord) and release one by one. | Both Macs play the chord and release each note correctly. | | | |
| 3-3 | Hold A for 3 seconds. | One note on each Mac (key repeat does not retrigger). | | | |
| 3-4 | Press X twice, then A. Press C twice, then A. | Octave and velocity in the window change; both Macs play the same pitch and velocity. | | | |
| 3-5 | JIS keyboard (if available): press the keys in the A / W / ; positions. | Same notes as on a US keyboard. | | | |
| 3-6 | Press ⌘A, ⇧A, ⌥A in another app. | No notes. | | | |
| 3-7 | Press ⌃⌘K (key capture off) and type in another app. | No notes. Turn back on with ⌃⌘K. | | | |
| 3-8 | Map a key (Remote) to launch a clip/scene in both sets; press it on main. | The clip/scene launches on both Macs in time (Link on). | | | |
| 3-9 | Optional delay check: record the audio outputs of both Macs into one recorder and press a key 10 times. | Write the difference between the two onsets. | | | |

## 4. Disconnect and reconnect

| # | Step | Expected | Live 11 | Live 12 | Notes |
|---|---|---|---|---|---|
| 4-1 | While connected, hold a key on main, then unplug the backup's network cable (or turn off its Wi-Fi). | Within about 3 s both show "Connecting to …". Backup stops the held note. Main keeps playing its own note. | | | |
| 4-2 | Reconnect the cable. | Both return to "Connected" by themselves within about 5 s. | | | |
| 4-3 | Keep the backup offline for 30 s, watch the main header. | Retry attempt number increases; retries slow to every 5 s. | | | |
| 4-4 | Quit TwinKeys on the backup while connected, then reopen it. | Main shows "Connecting to …" (or Not connected after Bye). After reopening, connect again works. | | | |
| 4-5 | Click **Disconnect** on main while holding a key. | Both Macs stop all notes. Backup shows "Not connected" and does not reconnect by itself. | | | |

## 5. Safety

| # | Step | Expected | Live 11 | Live 12 | Notes |
|---|---|---|---|---|---|
| 5-1 | Hold a chord on main, click **All Notes Off** (or ⌃⌘P). | All notes stop on both Macs. | | | |
| 5-2 | Hold a key and quit TwinKeys on main with ⌘Q. | Notes stop on both Macs. | | | |
| 5-3 | Settings: set automatic note-off to 1 s on both Macs. Hold a key for 5 s, then release. | The note sounds on both Macs until release (held keys are refreshed; the backup never uses less than 3 s). Set back to 10 s. | | | |

## 6. Window and appearance

| # | Step | Expected | Live 11 | Live 12 | Notes |
|---|---|---|---|---|---|
| 6-1 | Resize the window to its smallest size. | Status, All Notes Off and Connect/Disconnect stay usable; the rest scrolls. | | | |
| 6-2 | Switch System Settings > Appearance between Light and Dark. | Colors follow immediately and text stays readable. | | | |
| 6-3 | Turn on VoiceOver (⌘F5) and move through the window. | Status, buttons, checkboxes and values are read with meaningful labels. | | | |
| 6-4 | Check the menu bar. | TwinKeys (About, Settings…, Quit), Edit, Connection (Connect / "Connect to <name>" when one Mac is listed / Disconnect ⌘K, Turn Key Capture On/Off ⌃⌘K, All Notes Off ⌃⌘P), Window, Help (TwinKeys Help ⌘?, Show Log Folder in Finder). | | | |
| 6-5 | Help > Show Log Folder in Finder; open today's log. | Start, connect, disconnect and panic events are listed with times. | | | |
| 6-6 | Settings (⌘,) > Language: choose 日本語, then English, then Same as System. | The window, Settings and the Connection / Help menus switch at once. Standard items (Hide, Quit) follow the macOS language. | | | |
| 6-7 | TwinKeys menu > About TwinKeys. | Shows "Shogo Kajiyama / SEVENTHWELL", the unofficial-tool note and the copyright. | | | |
| 6-8 | macOS language set to Japanese, first launch (macOS 15+). | The Local Network dialog shows the Japanese reason text. | | | |
| 6-9 | Help > TwinKeys Help (⌘?) with Wi-Fi turned off, in English and in 日本語. | The guide opens in its own window in the chosen language; headings, lists and bold lines are readable. | | | |
| 6-10 | Press Tab repeatedly in the main window (System Settings > Keyboard > Keyboard navigation on). | A focus ring shows which button is selected; Space presses it. | | | |

## 7. Robustness (added in 0.4.0)

| # | Step | Expected | Live 11 | Live 12 | Notes |
|---|---|---|---|---|---|
| 7-1 | Click Connect on both Macs at the same moment (count down together). | Both end up "Connected" and notes play within a few seconds. | | | |
| 7-2 | Hold a key on main, then click into a password field (for example System Settings > Users & Groups > add user) on main. | The held note stops on both Macs. | | | |
| 7-3 | Hold a key for 30 s with automatic note-off at 10 s. | The note keeps sounding on both Macs until the key is released. | | | |
| 7-4 | Connect main to backup A, then connect to backup B. Disconnect from B. | Backup A does not reconnect by itself. | | | |
| 7-5 | Unplug the backup's cable for 5 s while holding a key on main, release the key while unplugged, plug back in. | Within about 1 s after the link returns, the note stops on the backup. | | | |
| 7-6 | Copy ~/Library/Application Support/TwinKeys/settings.json from main to backup and open TwinKeys on both. | One Mac shows that a new ID was made and asks to reopen TwinKeys; after reopening, both see each other. | | | |
| 7-7 | Run an older TwinKeys (with another protocol version, if available) on one Mac. | The other Mac lists it with "Different TwinKeys version" and Connect is unavailable. | | | |

