# Implementation notes

## Deviations

- **P1 finds the turntable by name on first sight.** P1 picks the device named "USB AUDIO  CODEC" that has input streams, saves its UID, then uses the saved UID only. Reason: no other fact separates it from other USB input devices before its UID is known. P2 (strips for all hardware inputs) removes the name rule.
- **Powering off the turntable does not remove its USB audio device, so "Disconnected" cannot mean power-off.** Core Audio sends no device-list change and the device stays alive, so spec §7.7 and AC1/AC5 "power on/off" cannot show or hide the strip. "Disconnected" now means the USB device is gone (cable unplugged). A powered-off turntable shows "No signal": raw input peak below -75 dBFS for 3 s (measured off about -78 dBFS peak, on with needle up above -72 dBFS). AC1's power-on check becomes "No signal goes away within 2 s"; AC5's power-off check becomes "strip shows No signal", plus a USB-unplug check for "Disconnected".
- **P2 strip styling follows the owner's reference (a rotary DJ mixer), not §6.** A rotary level knob replaces the vertical fader (300° sweep, -∞ to +10 dB, 0 dB at the same position as the fader detent). One analog needle meter per strip (VU ballistics about 0.3 s, the louder of L/R) replaces the stereo LED meter, with no peak hold; the clip light stays. The faceplate is brushed silver in Light appearance and brushed black in Dark appearance, following the system, instead of always dark. Reason: the owner's direction for P2.
- **An input device joins the audio engine only while its level knob is above the bottom (§4 D2 puts every input device in the aggregate).** Raising a knob from the bottom rebuilds the engine at once; a knob that stays at the bottom for 1 s leaves it. Reason: opening an input lights the mic-in-use indicator and drops a Bluetooth headset's output to call quality. New devices start at the bottom (D4), so nothing opens until the owner raises it. "No signal" applies only to devices in the engine.
- **"Disconnected" shows only for a device that went away during this session (§3.1 says strips disappear; §6 says they show Disconnected).** At launch, only present devices get strips. In P1 the turntable's strip showed "Disconnected" at launch from saved data; in P2 an unplugged turntable has no strip at launch.

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

Commit: not committed (tested build: working tree on base `1fc233b`).

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
