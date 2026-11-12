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

## 8. Pairing code and connect by IP (added in 0.5.0)

| # | Step | Expected | Live 11 | Live 12 | Notes |
|---|---|---|---|---|---|
| 8-1 | Fresh install on both Macs. | Window shows "To connect, both Macs need the same pairing code." Connect buttons are unavailable. | | | |
| 8-2 | Mac A: Set Up Pairing Code… > Make New Code. Mac B: Enter Code… and type it (try lower case and without the hyphen). | Both show the same code. Connect works; notes play on both. | | | |
| 8-3 | Mac B: Make New Code (confirm). | Link ends. Mac A shows Mac B with "Different pairing code"; Connect does not link. Enter the new code on Mac A: works again. | | | |
| 8-4 | Quit and reopen TwinKeys on both. | Code is remembered (keychain); connect works without entering it again. | | | |
| 8-5 | Network where Bonjour is blocked, or Macs on different subnets: Mac A > Connect by IP Address (⇧⌘K) with Mac B's address from its Settings. | Links; the row shows Mac B's name after connecting; notes play. | | | |
| 8-6 | Type an invalid address (e.g. "abc") in Connect by IP Address. | "Type an IP address such as 192.168.1.20." No crash. | | | |
| 8-7 | One Mac on 0.4.x, the other on 0.5.0. | The newer Mac lists the older one with "Different TwinKeys version"; no connection. | | | |
| 8-8 | Optional, with a packet capture tool: capture the UDP traffic on port 47801 while playing. | Note numbers are not readable in the packets (encrypted). | | | |


## 9. Cue keys, delivery check, updates and menu bar (added in 1.0.0)

| # | Step | Expected | Live 11 | Live 12 | Notes |
|---|---|---|---|---|---|
| 9-1 | Fresh install. Open Settings. | Cue Keys lists ↑ ↓ ← → Space Return Esc (ch 1 · C1 … F#1). Pressing A plays nothing. "Add A–Z and 0–9" adds 36 keys; pressing A then sends G1 (velocity 127). | | | |
| 9-2 | Live on both Macs: MIDI Map Mode (⌘M), map ↓ to scene down, ↑ to scene up, Return to launch the selected scene, Space to Play. | Pressing the keys on the main Mac moves and launches the same scenes on both Macs. | | | |
| 9-3 | Accessibility allowed, "Keep cue keys from other apps" on, Live in front on the main Mac. Press ↓ once. | Live moves down exactly one scene on both Macs (not two on the main Mac). | | | |
| 9-4 | Accessibility not allowed (or turned off). | The window shows the note about cue keys reaching other apps, with Open Accessibility Settings. | | | |
| 9-5 | Turn key capture off (⌃⌘K) and use the arrows in another app. | Arrows work normally; nothing is sent. | | | |
| 9-6 | Press ↓ several times while connected. | Main: "Reached the backup" ✓ and "Cue n since connecting"; backup shows the same key, memo and number. | | | |
| 9-7 | Pull the network cable on the backup, press ↓. | Within about half a second the main shows "No confirmation" in red. Reconnect: the count starts from 1. | | | |
| 9-8 | Hold ↓ for 2 s. | One cue only (no auto-repeat). | | | |
| 9-9 | Add keys (Settings > Add Key…, press F5 then F6 without closing) and give F5 a memo; remove Esc. | F5 gets the next free note; the other keys keep their notes; the memo shows on the backup when F5 is pressed. | | | |
| 9-10 | One Mac on 0.5.0, the other on 1.0.0. | Cues still play on the backup; the main shows "Delivery cannot be checked". | | | |
| 9-11 | After 1.0.1 is out: leave 1.0.0 running for a minute while connected. | Banner "TwinKeys 1.0.1 is ready" without Restart Now. Nothing is replaced while running. Quit: reopening shows 1.0.1. | | | |
| 9-12 | Same, while not connected. | Restart Now is shown; clicking it reopens TwinKeys as 1.0.1. | | | |
| 9-13 | Menu bar icon: not connected / connected / pull the cable. | Outline / filled / outline with "!". Visible on light and dark menu bars. | | | |
| 9-14 | Close the window. Use the menu bar menu: All Notes Off, Open TwinKeys, Quit. | TwinKeys keeps running after closing; the menu items work. | | | |
| 9-15 | Settings: Open at Login on, log out and in. Menu bar only on. | TwinKeys opens at login. No Dock icon while menu bar only is on. | | | |

## 10. TwinKeys Remote (iPhone and iPad, added in 2.0)

Needs both Macs on 2.0, TwinKeysBridge chosen as a Control Surface in Live on both, and TwinKeys Remote from TestFlight. Use a test set with fictional names only.

| # | Step | Expected | Live 11 | Live 12 | Notes |
|---|---|---|---|---|---|
| 10-1 | Settings → Live → Install into Live, restart Live, choose TwinKeysBridge as a Control Surface. | Live's status bar shows "TwinKeys Bridge: listening on 127.0.0.1:47811"; TwinKeys Settings shows "Live: Connected". | | | |
| 10-2 | Main Mac: Allow TwinKeys Remote to connect. iPhone: type the pairing code, Save, Connect. | iPhone and Mac show the same 4 digits; Allow on the Mac connects; the device appears under Allowed devices. | | | |
| 10-3 | Type a wrong pairing code on the iPhone. | "The pairing code does not match the Mac."; nothing appears on the Mac. | | | |
| 10-4 | Click Don't Allow on the Mac. | iPhone: "The Mac did not allow this iPhone." | | | |
| 10-5 | iPhone in landscape: launch a clip, a scene, an empty slot. | The same clip/scene launches on both Macs; the empty slot stops that track on both. The time left counts down on the playing clip. | | | |
| 10-6 | Play; Stop with a short tap, then a long press. | Play works; a short tap does nothing; a long press stops both. | | | |
| 10-7 | Mixer: drag a column, M, S. | Volume, mute and solo change on both Macs. With "Faders stop at 0 dB" on, the volume stops at the dashed line. | | | |
| 10-8 | Show lock on; try tempo and the mixer; then clips and cues; hold the lock 1 s. | Tempo and mixer do not move; clips, scenes and cues work; holding unlocks. | | | |
| 10-9 | Cues pane: press ↓. | Same as ↓ on the main Mac's keyboard; last cue shows ✓ when the backup confirms. | | | |
| 10-10 | All Notes Off on the iPhone while notes are held. | All notes stop on both Macs. | | | |
| 10-11 | Turn Wi-Fi off and on on the iPhone. | The app shows "Connection lost. Retrying…" and reconnects without asking for approval again. | | | |
| 10-12 | Remove the device on the Mac, reopen the app. | The Mac asks for approval again. | | | |
| 10-13 | iPad landscape and an open iPhone Duo. | Three columns (iPad) / two columns (Duo); nothing cut off. | | | |

## 11. GO, set check, sends and catch-up (added in 2.1)

Same setup as chapter 10, with a test set that has two return tracks (fictional names only).

| # | Step | Expected | Live 11 | Live 12 | Notes |
|---|---|---|---|---|---|
| 11-1 | iPhone GO screen: select scene 2 in Live, tap GO. | Scene 2 launches on both Macs; "Next" becomes scene 3. A second tap within 0.5 s does nothing. | | | |
| 11-2 | Back / Next on the GO screen. | Only the selection moves (on both Macs); nothing plays. | | | |
| 11-3 | Show lock on; GO, Back, Next. | They still work; tempo and mixer stay locked. | | | |
| 11-4 | Quit Live on the backup Mac. | iPhone top bar: "Backup ✓ · Live ✗ no answer" in yellow within a few seconds; Mac status line shows the other Mac's Live ✗. | | | |
| 11-5 | Rename one scene and delete one track on the backup only. | Yellow warning on both Macs and the iPhone; Details lists the renamed scene and the missing track. Undo: the warning goes away. | | | |
| 11-6 | Mixer Send A / Send B on the iPhone. | The send of that track's first / second return moves on both Macs; with no return tracks the buttons are hidden. | | | |
| 11-7 | Pull the network cable between the Macs; move a fader and the tempo on the iPhone; launch a clip; plug the cable back in. | After relinking, the backup gets the newest fader and tempo values; the clip is not launched late on the backup. | | | |
| 11-8 | MIDI Map: keys mapped to clips still work after TwinKeysBridge is installed. | Cue keys launch the same clips on both Macs as before. | | | |
| 11-9 | Insert a track at the start during playback, then tap a clip on the iPhone right away. | Either the right clip plays, or the iPhone says the layout changed and asks to tap again; never a different clip. | | | |

## 12. Backup confirmation, lock options, switching to the backup, Apple Watch (added in 2.2)

Same setup as chapter 10. On the backup Mac also turn on **Allow TwinKeys Remote to connect** and allow the iPhone there once. Apple Watch with watchOS 10 or later, paired with the iPhone.

| # | Step | Expected | Live 11 | Live 12 | Notes |
|---|---|---|---|---|---|
| 12-1 | Install an older TwinKeysBridge into Live, then start the new TwinKeys. | TwinKeys replaces the bridge by itself and asks to restart Live; after the restart the note goes away. | | | |
| 12-2 | On the backup, turn TwinKeysBridge off in Live's Control Surface list; launch a clip from the iPhone. | Plays on the main; the iPhone says the backup's Live did not answer. | | | |
| 12-3 | Settings > What the show lock stops: also turn on "Clip and scene launches"; lock; tap a clip, then GO. | The clip is refused ("Show lock is on"); GO still plays. The toggles are greyed out while locked. | | | |
| 12-4 | Quit TwinKeys on the main Mac during playback. | After about 3 s the iPhone shows "The main Mac is not answering"; the screens stay. | | | |
| 12-5 | Tap "Switch to the backup", then hold "Hold to switch" for 1 s. | The iPhone connects to the backup Mac; that Mac shows "This Mac is the main" and its cue keys work. A short tap does not switch. | | | |
| 12-6 | Start TwinKeys on the old main Mac again. | It only receives; a key pressed there does not fire on both. "Return to Main" on the current main hands it back. | | | |
| 12-7 | On the backup Mac alone (no iPhone): unplug the main Mac's cable, click "Make This Mac the Main". | After the confirmation this Mac sends the cues; the other Mac, when back, only receives. | | | |
| 12-8 | Apple Watch: open TwinKeys; GO page, turn the Digital Crown, tap GO. | The crown chooses Next (nothing plays); GO plays it on both Macs; a double tap within 0.5 s plays once. | | | |
| 12-9 | Apple Watch: scene list, tap a scene; All Notes Off page. | The tapped scene becomes Next (does not play); All Notes Off stops both Macs. | | | |
| 12-10 | Close TwinKeys Remote on the iPhone; tap GO on the watch. | Nothing plays; the watch says the iPhone app must be open. | | | |
| 12-11 | Pairing screen: "Try with sample data"; then Settings > "End the sample and connect to a Mac". | Sample screens with "· Sample" in the top bar; nothing reaches the Macs. Ending returns to the pairing screen and reconnects with the saved code. | | | |
| 12-12 | Settings: Privacy policy and Help and support. | Open the site's privacy and support pages in the iPhone's language. | | | |
