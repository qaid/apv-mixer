# Implementation notes

## Deviations

- **P1 finds the turntable by name on first sight.** P1 picks the device named "USB AUDIO  CODEC" that has input streams, saves its UID, then uses the saved UID only. Reason: no other fact separates it from other USB input devices before its UID is known. P2 (strips for all hardware inputs) removes the name rule.
- **Powering off the turntable does not remove its USB audio device, so "Disconnected" cannot mean power-off.** Core Audio sends no device-list change and the device stays alive, so spec §7.7 and AC1/AC5 "power on/off" cannot show or hide the strip. "Disconnected" now means the USB device is gone (cable unplugged). A powered-off turntable shows "No signal": raw input peak below -75 dBFS for 3 s (measured off about -78 dBFS peak, on with needle up above -72 dBFS). AC1's power-on check becomes "No signal goes away within 2 s"; AC5's power-off check becomes "strip shows No signal", plus a USB-unplug check for "Disconnected".
- **P2 strip styling follows the owner's reference (a rotary DJ mixer), not §6.** A rotary level knob replaces the vertical fader (300° sweep, -∞ to +10 dB, 0 dB at the same position as the fader detent). One analog needle meter per strip (VU ballistics about 0.3 s, the louder of L/R) replaces the stereo LED meter, with no peak hold; the clip light stays. The faceplate is brushed silver in Light appearance and brushed black in Dark appearance, following the system, instead of always dark. Reason: the owner's direction for P2.
- **An input device joins the audio engine only while its level knob is above the bottom (§4 D2 puts every input device in the aggregate).** Raising a knob from the bottom rebuilds the engine at once; a knob that stays at the bottom for 1 s leaves it. Reason: opening an input lights the mic-in-use indicator and drops a Bluetooth headset's output to call quality. New devices start at the bottom (D4), so nothing opens until the owner raises it. "No signal" applies only to devices in the engine.
- **"Disconnected" shows only for a device that went away during this session (§3.1 says strips disappear; §6 says they show Disconnected).** At launch, only present devices get strips. In P1 the turntable's strip showed "Disconnected" at launch from saved data; in P2 an unplugged turntable has no strip at launch.
- **P3 gives each app strip its own engine (§4 D2 puts every source in one aggregate).** Each app strip owns a private aggregate with the default output as main sub-device and that app's tap; the input strips keep the P2 engine. Reason: with one shared aggregate, every app that starts a sound (a notification, a video) adds a tap, rebuilds the engine and interrupts the turntable. Consequences for P4: the master meter sums peaks across engines, and the §7.5 hard clip applies per engine, with the HAL mixing the engines on the output device.
- **Tap drift compensation is off when the output is Bluetooth.** Reason: a reference app reports a rhythmic crackle with drift compensation on a tap and Bluetooth output.
- **App grouping follows only the process tree (§7.11), so some browser helpers get their own strip.** The walk stops at the first parent that is a regular `.app` (activation policy regular), so helper processes that are themselves `.app` bundles reach their browser. Web content and GPU helpers launched by launchd (Safari's, for example) have no parent app and get their own strip, named from the process. A process with no parent app and no bundle ID gets no strip. Reason: §7.11 and D12 (no private API to find the responsible app).
- **The clip light stays lit while the strip clips, then fades out over about 2.5 s (§6: "stays lit until clicked").** It sits behind the meter glass, in the upper corner, and is not a button. Reason: the owner's direction after the P3 look check. The master strip's clip light (P4) follows the same rule.
- **The Mute button has no red ring (P2 styling: red-ring Mute).** Lit, it still glows red. Reason: the owner's direction after the P3 look check.
- **The "System Audio Recording may be off" banner checks only until tapped audio first arrives.** After any app strip delivers non-zero audio in a session, the banner no longer appears. Reason: a paused app reports output running while silent, which would show the banner falsely; the cost is that permission removed during a session is not detected.
- **The master strip follows the P2 styling (§6: master fader, stereo meter).** The master level is the chrome rotary knob with a percent readout and no 0 dB detent, because the system volume is a 0 to 1 value with no 0 dB point. One needle meter, like the strips. The needle follows the master volume and mute: it rests when either is at the bottom. For a system volume, the mixer estimates the level with the knob's own curve. The clip light shows the mix before the volume, because the volume cannot fix that clipping. At volume 0 the mixer also silences its mix, because some outputs still play quietly at their lowest volume. Reason: the owner's P4 decisions D1 to D5, and the owner's direction after the P4 check (D6 first put the needle before the volume).
- **The master meter and the CPU load add up the engines (P3's one engine per app).** The master needle uses the sum of each engine's peak, which can read higher than the true mix. The CPU load is the sum of each engine's share of its buffer period. Reason: each engine runs its own IOProc, and the HAL mixes their outputs.
- **The software volume (D8) starts at 100 % at each launch and is not saved.** Reason: §3.7 persistence covers strips only.
- **After the owner moves the master volume, balance or mute, the mixer ignores change notices for that control for 0.3 s, then reads it once (§7.9 says only: ignore a value equal to the last one).** Reason: a drag sends many values, and a late notice for an earlier value would pull the knob back.
- **Input strips have Bass and Treble knobs (§3 lists EQ as out of scope for v1).** Each is a shelving filter (RBJ cookbook, slope 1): Bass at 100 Hz, Treble at 8 kHz, -12 to +12 dB, saved per device. They act on the raw input before Trim and the fader, so "No signal" still reads the raw input and the clip light includes a boost. The audio thread steps each value 1 dB per buffer toward the knob. App strips have no Bass and Treble. Reason: the owner's request (2026-10-25), to improve the turntable's sound.
- **Input strips have a power button, left of DEFAULT (not in the spec).** Off removes the device from the engine at once, so macOS closes it and the mic-in-use indicator goes off; the level and other settings stay. The off state is saved per device. Mute does not do this, because mute is a gain of 0 and keeps the device open. Reason: the owner's request (2026-10-30), to release the OBSBOT camera's microphone while the mixer is open.

## Sound settings left out (spec R8)

These System Settings > Sound controls have no documented public API, so the mixer does not show them: alert sound choice, alert volume, play user interface sound effects, play feedback when volume is changed, play sound on startup.

## Process tap references (spec R5)

- SDK headers: `CoreAudio.framework/Headers/AudioHardware.h` (process objects, tap properties, aggregate tap keys), `AudioHardwareTapping.h` (`AudioHardwareCreateProcessTap`, `AudioHardwareDestroyProcessTap`), `CATapDescription.h` (initializers, `muteBehavior`, `isPrivate`).
- Apple: "Capturing system audio with Core Audio taps", https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps; forum threads https://developer.apple.com/forums/thread/756783 and https://developer.apple.com/forums/thread/771864.
- FineTune (GPL-3, read only, no code copied): https://github.com/ronitsingh10/FineTune (`ProcessTapController.swift`, `OrphanedTapCleanup.swift`, `AudioProcessMonitor.swift`).
- AudioCap (read only, no code copied): https://github.com/insidegui/AudioCap (`ProcessTap.swift`).
- Probes on the owner's Mac (2026-10-10): the `CATapDescription` Swift names compile; tap format is 48 kHz stereo Float32 in one interleaved buffer; in an aggregate, tap buffers follow the sub-device input buffers; `kAudioAggregateDevicePropertyTapList` and `kAudioTapPropertyDescription` are settable; private taps and aggregates disappear when their process is killed.
- Probe on the owner's Mac (2026-10-10): when an app starts playback, its process object sends a `kAudioProcessPropertyIsRunning` notice but no `kAudioProcessPropertyIsRunningOutput` notice, although the IsRunningOutput value changes. Listen to both; read IsRunningOutput on each notice.

## Phase checks

### 2026-10-10, P1

Commit: `ddefdb4` (tested build: the same code, before the commit).

Round 1:
- AC8: pass
- AC1: pass (the strip was already present at launch; see round 2)
- AC2: pass
- AC3: pass
- AC5: fail. Turntable power-off did not remove the USB audio device, so the strip did not show "Disconnected".
- AC4: not done

Round 2 (after the "No signal" change, see Deviations):
- AC1: pass ("No signal" goes away within 2 s of power-on; name restored after relaunch)
- AC5: pass (power-off shows "No signal"; USB unplug shows "Disconnected"; level restored after power-on and after replug)
- AC4: pass (30 minutes, no dropouts or clicks)

Result: P1 done.

### 2026-10-10, P2

Commit: `d2f7d1e` (tested build: the same code, before the commit).

- AC8: pass
- AC1: pass
- AC2: pass
- AC3: pass
- AC4: pass
- AC5: pass (power-off shows "No signal"; USB unplug shows "Disconnected"; a second input kept playing; level restored after power-on and after replug)
- AC7: pass
- AC9: pass
- AC11: pass (Default input button both ways; output change in System Settings or headphones moved playback)
- Look (owner direction, not a spec check): pass (Light and Dark faceplates follow the system)

Result: P2 done.

### 2026-10-10, P3

Commit: `5d7f68d` (tested build: the same code, before the commit).

Round 1:
- P0: fail. After the permission was turned on, "Quit & Reopen" launched a stale P1 build: other build folders had registered extra copies of the app. Fixed in `scripts/build.sh`.

Round 2 (reply sheet):
- P0: pass (app audio stays audible with the permission off; banner shows; its button opens the right pane)
- AC6: fail. An app that starts playing after the mixer opens gets no strip. Cause: the mixer listened only for IsRunningOutput notices (see the R5 probe above). Fixed; the tone self-check now passes.
- AS9: pass
- AC13: pass
- AP1: pass
- V2: pass (enhancement requested: the window should fit its strips)

Round 3 (after the AC6 fix and the window fit):
- AC6: pass
- V2: pass (enhancements requested: clip light inside the meter glass, fading clip light, no ring on Mute)

Round 4 (owner's look changes: clip light in the meter glass, clip fade, Mute without ring):
- V3: pass (clip light stays lit while clipping, then fades; Mute reads as a button in Light and Dark)

Result: P3 done.


### 2026-10-10, P4

Commit: `3cc4d2f`.

Round 1 (reply sheet):
- AC1: pass
- AC2: pass
- AC3: fail. With the master volume at the bottom, a USB output still plays quietly, and the master needle still moves. Fixed: at volume 0 the mixer silences its mix, and the needle follows the master volume and mute (owner's direction; see Deviations).
- AC4: pass
- AC5: pass
- AC6: pass
- AC7: pass
- AC8: pass
- AC9: pass
- AC10: pass
- AC11: fail. The Output and Sound effects menus list no devices. Cause: the "can be default device" flags were read in the global scope, which returns an error; they need the output scope. Fixed.
- AC12: pass
- AC13: pass
- V4: pass

Round 2 (chat):
- AC3: pass
- AC11: pass

Result: P4 done.
