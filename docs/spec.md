# Turntable Mixer: Build Spec

The decisions from the [map](https://github.com/qaid/apv-mixer/issues/1) are written into this spec. Each changed line names the ticket that holds the reason.

A small native macOS mixer app that looks like a DJ mixer. It does two jobs:

1. **Mixing:** one channel strip per audio source on the Mac (input devices and apps), all mixed to the speakers or headphones.
2. **Sound settings:** mixer-style controls for what System Settings > Sound offers (output and input device, volumes, balance, sound effects device).

**Primary job:** power on the turntable, open the app, raise the turntable's fader, hear the record.

---

## 1. Context

**Hardware chain:** Audio-Technica LP120 (USB model) → USB cable → USB hub → Mac. The turntable's built-in USB codec shows up in macOS as two devices with the same name, "USB AUDIO  CODEC" (two spaces): an input and an output. Select the input by UID and input streams, never by name. The input has no macOS input volume ([Aggregate engine](https://github.com/qaid/apv-mixer/issues/4), [Two-way sync test](https://github.com/qaid/apv-mixer/issues/12)).

**Current state:** recording apps (for example GarageBand) can already record the turntable. Listening to it today needs an audio routing app such as Rogue Amoeba Loopback; this app replaces that. If a routing app also sends the turntable to the speakers, the record plays twice (see R7).

**Why build:** existing apps cover the controls but not the UI. SoundSource (Rogue Amoeba) and FineTune (open source) offer device switching, device volumes and per-app volume, but only as menu bar lists. None found has a mixer window with channel strips.

**README audience:** a non-engineer. Setup steps (signing, permissions, running from Xcode) must be explained in plain language in the README.

**Testing constraint:** Claude Code cannot hear audio. At the end of each phase, stop and ask the owner to run the acceptance checks on the real hardware before continuing.

---

## 2. Assumptions (veto before build)

| Code | Assumption |
|------|-----------|
| AS1 | "All other audio sources" means both other input devices (mics, interfaces) and apps playing audio (Spotify, browser, Music). |
| AS2 | The Mac runs macOS 27. The app targets macOS 27 only ([Charting scope decisions](https://github.com/qaid/apv-mixer/issues/2)). |
| AS3 | Personal use only. No App Store, no distribution to others. |
| AS4 | Level control, mute, metering and the Sound settings controls are enough for v1. The DJ mixer is a visual style, not a request for DJ features. |

---

## 3. Scope

### In scope (v1)

1. **Input device channels:** one strip per hardware input device (turntable, built-in mic, any USB interface). Software devices (audio routing apps, conferencing app drivers, user-made aggregate devices) get no strip ([Charting scope decisions](https://github.com/qaid/apv-mixer/issues/2), [Engine and control list](https://github.com/qaid/apv-mixer/issues/8)). Strips appear and disappear live as devices are powered on, plugged in or removed.
2. **App channels:** one strip per running app that is producing audio, captured with Core Audio process taps.
3. **Per mixer channel:** editable name, trim knob, stereo peak meter, mute button, vertical fader, dB readout.
4. **Master section:** output device menu, sound effects device menu, master fader, balance knob, mute, master meter.
5. **Sound settings controls** (the list is confirmed on macOS 27, [Sound settings APIs](https://github.com/qaid/apv-mixer/issues/5), [Engine and control list](https://github.com/qaid/apv-mixer/issues/8)):
   - Output: default output device, output volume, balance, mute.
   - Input: default input device, device input volume.
   - Sound Effects: the device that plays sound effects, as an explicit device only.
   - Left out under R8 (no documented API): alert sound choice, alert volume, play user interface sound effects, play feedback when volume is changed, play sound on startup.
6. **Two-way sync:** changes made in the mixer show in System Settings, and changes made in System Settings, Control Center or the volume keys show in the mixer.
7. **Persistence:** names, trim, fader and mute saved per input device (by device UID) and per app (by bundle ID), restored on relaunch and on reconnect. Store: `UserDefaults`, one dictionary for input devices and one for apps, written on each change ([Last spec gaps](https://github.com/qaid/apv-mixer/issues/15)).

### Out of scope (v1)

EQ, crossfader, cue/headphone split, effects, recording, MIDI controller support, menu bar mode, App Store packaging. Do not build these.

---

## 4. Decisions

| Code | Decision | Reason |
|------|----------|--------|
| D1 | Native Swift + SwiftUI app. Targets macOS 27 only ([Charting scope decisions](https://github.com/qaid/apv-mixer/issues/2)). No Electron or web stack. | Needs direct Core Audio access and low latency. |
| D2 | Audio engine: the app creates one **private aggregate device** (`AudioHardwareCreateAggregateDevice`) containing the current output device as clock master, each input device as a sub-device with drift compensation on, and process taps for app channels. One IOProc on that aggregate reads all inputs, applies gains, sums, and writes to the output. Confirmed on macOS 27: the codec keeps its sample rate, no overloads, and GarageBand records the turntable at the same time ([D2 run test](https://github.com/qaid/apv-mixer/issues/11)). Dictionary keys and composition: [Aggregate engine](https://github.com/qaid/apv-mixer/issues/4). Never nest a user-made aggregate device. | Handles different device clocks and sample rates in one place. This is the pattern Apple documents for process taps. |
| D2b | Fallback if D2 proves unstable: one input unit per device feeding lock-free ring buffers, mixed in the output callback with sample-rate conversion. Log the switch and why in `implementation-notes.md` under "Deviations". | Keeps the build moving without a redesign. |
| D3 | App channels mute the app's normal output while tapped (tap mute behavior "muted when tapped"). When the mixer quits, apps play normally again. | Otherwise the app plays twice (direct + through mixer) and its fader can't turn it down. |
| D4 | Default levels: newly seen **input devices** start with the fader at the bottom (silent), unmuted. Newly seen **apps** start at 0 dB. | Turntable flow is "raise the fader to hear it". The built-in mic can't feed back into the speakers by default. Tapping an app doesn't change what you hear. |
| D5 | Not sandboxed. Signed with the owner's existing Apple Development team, not a free personal team. Bundle ID `io.github.qaid.turntablemixer`, fixed from the first build. The owner creates the Xcode project once (steps in [Xcode project](https://github.com/qaid/apv-mixer/issues/7)). The build script fails on an ad hoc signature. | macOS ties Microphone and System Audio Recording permissions to the app's signature. Unsigned or ad-hoc builds may lose permission after every rebuild. |
| D6 | Never take exclusive ("hog mode") control of any device. | GarageBand and other apps must still be able to use the turntable while the mixer runs. |
| D7 | One output choice. The mixer's output menu sets the macOS default output device, and the mixer always plays to the macOS default output. | Two separate output settings (mixer vs system) would confuse which one is in charge. |
| D8 | The master fader is the system output volume of the current output device (the same value as the volume keys). If the device has no volume control (some HDMI or USB devices), the master fader applies gain in the mixer instead and shows a small "software" label. | Matches Sound settings and avoids two volume stages fighting each other. |
| D9 | Each input strip has two gain stages, labelled differently: **Device gain** (the macOS input volume, affects every app that records from the device) and **Trim + Fader** (mixer only). Device gain is greyed out when the device has no input volume control. The turntable input has none, so its Device gain is always greyed out ([Two-way sync test](https://github.com/qaid/apv-mixer/issues/12)). | The turntable codec may not expose an input volume; the mixer fader must still work. |
| D10 | Fresh codebase. FineTune (GitHub, GPL-3) may be read as a reference for process taps and device volume handling. If any code is copied rather than rewritten, log it in `implementation-notes.md`; the app then falls under GPL-3 if it is ever shared. | Owner's choice: keep the spec's own audio design rather than adapt a menu bar app. |
| D11 | Closing the window keeps the app and the audio running; the Dock icon opens it again. Command-Q quits with no confirmation. One mixer window. No in-app open-at-login setting ([App lifecycle](https://github.com/qaid/apv-mixer/issues/9)). | Closing the window by accident must not stop the record. |
| D12 | No private APIs. Where no public API exists, infer: the System Audio Recording state from silent taps (§5), the app for a helper process from the process tree (§7.11) ([App strips without a public API](https://github.com/qaid/apv-mixer/issues/10)). | Private APIs can break on any macOS update. |

---

## 5. Permissions

This is the most likely failure point. Handle it explicitly.

| Item | Detail |
|------|--------|
| Microphone | `NSMicrophoneUsageDescription` in Info.plist. Required to read any input device, including the turntable. Request on first launch. Enable the Hardened Runtime audio-input entitlement (`com.apple.security.device.audio-input`). |
| System Audio Recording | Required for process taps (app channels). Info.plist key `NSAudioCaptureUsageDescription` ([Process tap API](https://github.com/qaid/apv-mixer/issues/3)). The prompt appears the first time audio starts from an aggregate that contains a tap. No public API reads this permission: if a tapped app reports `kAudioProcessPropertyIsRunningOutput` = true but its tap gives only silence for about 2 s, show the banner "System Audio Recording may be off" ([App strips without a public API](https://github.com/qaid/apv-mixer/issues/10)). |
| Sound settings controls | Device volume, balance, mute and default device changes need no permission. The sound effects device needs no permission. The other Sound Effects settings are left out (R8). |
| Denied or not yet granted | Show a clear banner inside the mixer window naming the missing permission, with a button that opens the right pane in System Settings > Privacy & Security. Never show flat meters with no explanation. |

---

## 6. UI

**Overall look:** dark DJ mixer panel. Left to right: input device strips, app strips, master strip. Each group visually distinct. Scroll horizontally if there are many strips.

**Input device strip, top to bottom:**

| Element | Behavior |
|---------|----------|
| Icon + name | Device icon. Double-click to rename (e.g. "USB AUDIO CODEC" → "Turntable"). |
| Default input button | Lit on the strip that is the macOS default input. Click to make this device the default input. |
| Device gain knob | macOS input volume for this device (D9). Greyed out if unsupported. |
| Trim knob | -24 to +24 dB, mixer only. Drag vertically. Double-click resets to 0 dB. |
| Peak meter | Segmented LED style, stereo, green/yellow/red. Peak hold about 1.5 s. Clip light that stays lit until clicked. |
| Mute | Lit when muted. |
| Fader | Long-throw vertical fader, -∞ to +10 dB, detent at 0 dB. Double-click resets to 0 dB. |
| dB readout | Current fader value. |
| Disconnected state | Greyed out with "Disconnected" label when the device goes away; reconnects with saved settings. |

**App strip:** same as the input strip without the Default input button and Device gain knob. App icon instead of device icon.

**Master strip:** output device menu (D7; lists every output device), "Sound effects through" menu (an explicit device; a short note says that a choice here stops macOS from following the selected output) ([Engine and control list](https://github.com/qaid/apv-mixer/issues/8)), balance knob (double-click to center), mute, master fader (D8), stereo meter with clip light.

**Status line:** sample rate, estimated latency in ms, audio CPU load. CPU load: the IOProc reads the host clock at its start and end and writes the time used, as a share of the buffer period, to an atomic; the UI shows the highest value of the last 0.5 s. It measures the mixer's own audio work only ([Last spec gaps](https://github.com/qaid/apv-mixer/issues/15)).

**Window:** one mixer window (D11).

---

## 7. Audio behavior

1. **Gain chain per channel:** trim × fader × mute. Then sum, then master (D8). Smooth all gain changes over 10 to 20 ms so faders never click.
2. **Channel layout:** mono inputs go to both left and right. Inputs with more than 2 channels use the first two.
3. **Sample rate:** run at the output device's rate; drift compensation on the aggregate handles input clocks.
4. **Latency:** target under 20 ms from turntable to speakers. Use a small buffer (128 to 256 frames). Bluetooth output adds its own latency; show it, don't fight it.
5. **Clipping:** hard clip at 0 dBFS on the mixer sum, with the clip light. No limiter in v1.
6. **Real-time safety:** no memory allocation, locks, logging, file I/O or Objective-C/Swift object work on the audio thread. Pass parameters in via atomics. The audio thread writes peak values to atomics; the UI reads them at about 30 fps.
7. **Hot-plug:** listen for device list changes. Turntable powered on → strip appears within 2 seconds with its saved name and levels. Powered off → strip shows Disconnected, aggregate is rebuilt without it, other channels keep playing (a brief gap is acceptable, a crash is not).
8. **Default device changes:** when the macOS default output changes (from the mixer, System Settings, Control Center or plugging in headphones), rebuild the aggregate on the new device and keep playing.
9. **Two-way sync:** listen for changes to output volume, balance, mute, input volume and the default devices (output, input, sound effects), and update the controls. Each notification can arrive twice: ignore a value equal to the last one. Volume is on element 0 on some devices and on elements 1 and 2 on others. On a device without `kAudioDevicePropertyStereoPan`, balance is the ratio of the two channel volumes ([Two-way sync test](https://github.com/qaid/apv-mixer/issues/12)). Never write a value back in response to a change notification (avoids feedback loops between the mixer and System Settings).
10. **Device identity:** key everything by device UID, never by the numeric device ID. The ID can change when the USB hub resets.
11. **App list:** listen for process list changes. An app strip appears when the app starts producing audio and stays while the app is running. Group each helper process under its parent app by walking up the process tree with `sysctl`. A helper with no parent app gets its own strip ([App strips without a public API](https://github.com/qaid/apv-mixer/issues/10)).
12. **Self-exclusion:** never tap the mixer's own process.
13. **Crash cleanup:** at launch, destroy any private aggregate devices left behind, found by the mixer's name prefix. No crash signal handler ([App strips without a public API](https://github.com/qaid/apv-mixer/issues/10)).

---

## 8. Risks

| Code | Risk | Mitigation |
|------|------|-----------|
| R1 | Permission denied or never granted → silent channels with no explanation. | Section 5 banner. Test on first launch with permission denied. |
| R2 | USB hub resets change device IDs, breaking the aggregate. | Key by UID; rebuild aggregate on device list change. |
| R3 | Clock drift between the turntable codec and the output device causes clicks every few minutes. | Drift compensation on every non-master sub-device. 30-minute playback test (AC4). |
| R4 | Built-in mic feeding back into speakers. | D4: new inputs start silent. |
| R5 | Process tap APIs are newer and thinly documented, so it's easy to invent wrong API names. | Before coding phase 3, read Apple's current Core Audio tap documentation and sample code, plus FineTune's source as a working example. Cite what you used in `implementation-notes.md`. |
| R6 | Rebuilding with a different signature resets permissions. | D5; explain in README. |
| R7 | Loopback also sends the turntable to the speakers, so the record plays twice or echoes. | README tells the owner to remove Loopback's Monitor for the turntable (or quit Loopback) when using the mixer. Loopback is installed on the owner's Mac. Hiding software devices does not stop its monitor, so the step stays; the mixer shows no hint ([Last spec gaps](https://github.com/qaid/apv-mixer/issues/15)). |
| R8 | Some Sound Effects settings (alert sound choice, startup sound, interface sounds, volume feedback) may have no supported public API, or may need admin rights. | For each one, find a supported method first. If none exists, leave that control out, log it under "Deviations", and tell the owner at the end of the phase. Do not use private APIs or edit system files silently. Result: alert sound choice, alert volume, UI sound effects, volume feedback and startup sound are left out ([Engine and control list](https://github.com/qaid/apv-mixer/issues/8)). |

---

## 9. Build phases

Stop after each phase for the owner to test on real hardware.

| Phase | Deliverable | Checks |
|-------|-------------|--------|
| P1 | Turntable passthrough: one input device → default output, with fader, mute, meter, permission banner. Proves the core goal. | AC1 to AC5, AC8 |
| P2 | All input devices, hot-plug, persistence, full DJ mixer styling, Default input button, Device gain knob. | AC1 to AC5, AC7 to AC9, AC11 |
| P3 | App channels via process taps, crash cleanup. | AC6, AC13 |
| P4 | Master strip system controls (output menu, output volume, balance, mute), sound effects device menu, two-way sync, status line, README polish. | All |

---

## 10. Acceptance criteria

| Code | Check |
|------|-------|
| AC1 | With the app open, power on the turntable: its strip appears within 2 seconds. After one rename it shows "Turntable" on every later launch. |
| AC2 | Play a record and raise its fader: audio plays on the current output, meter moves, no audible delay versus the needle. |
| AC3 | Fader at bottom = silence. Mute = silence. Moving faders quickly produces no clicks. |
| AC4 | 30 minutes of continuous playback with no dropouts or clicks. |
| AC5 | Power off the turntable mid-play: strip shows Disconnected, other channels continue, no crash. Power on again: playback returns at the same level. |
| AC6 | Play music in Spotify (or Music) and a browser video: each gets its own strip, each fader controls only that app, no doubled audio. Quitting the mixer restores normal app audio. |
| AC7 | GarageBand can record the turntable while the mixer is running. |
| AC8 | First launch with Microphone permission denied shows the banner, and its button opens the right Settings pane. |
| AC9 | Names, trims, faders and mutes are restored after relaunch. |
| AC10 | Volume keys move the master fader, and moving the master fader moves the volume shown in Control Center. Same for mute. |
| AC11 | Changing the default input or output in the mixer shows in System Settings > Sound, and changing it in System Settings shows in the mixer. Plugging in headphones moves mixer playback to them without a crash. |
| AC12 | Balance and the sound effects device set in the mixer match System Settings > Sound. The controls left out under R8 are listed in `implementation-notes.md`. |
| AC13 | Force-quit the mixer while an app strip plays. Note whether the app's normal audio returns. Open the mixer again: the app's normal audio returns, and its strip works ([App strips without a public API](https://github.com/qaid/apv-mixer/issues/10)). |

---

## 11. Deliverables

1. Xcode project for the app.
2. `README.md` in plain language: the one-time Xcode project steps, build and run, grant permissions, rename the turntable channel, "if app audio is silent after a mixer crash, open the mixer once", turn off Loopback's turntable monitor (R7), what to do if a channel shows no signal.
3. `implementation-notes.md` with a "Deviations" section logging every departure from this spec and why, plus the references used for process taps.
