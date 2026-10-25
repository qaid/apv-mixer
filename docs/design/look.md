# Look

The target is a rotary DJ mixer: `reference.png` shows the same mixer in silver and in black. Match its materials and controls, not its layout or functions. Spec §6 sets the strip contents; the P2 styling deviation in `implementation-notes.md` records why this look replaces §6's styling.

Exact colours and sizes live in the code (`Faceplate.swift`, `Knob.swift`, `VUMeter.swift`, `StripView.swift`). These rules say what the code must look like.

## Faceplate

- Light appearance: brushed silver. Dark appearance: brushed black. The app follows the system appearance; it never forces one.
- Fine horizontal brushing, visible but quiet. The brushing does not move on redraw.
- Screw heads in the corners.
- Strips are separated by thin engraved lines; the Inputs, Apps and Master groups by a heavier one.

## Lettering

- Engraved, condensed, uppercase, small. Ink contrasts with the plate: dark ink on silver, light ink on black.
- Labels sit directly under or beside their control, as on the reference.
- Readable at the window's default size: no panel label under 8 pt. Print on the meter face (scale, CLIP) follows the meter's own scale size.

## Controls

- **Level knob**: the large chrome knob at the bottom of each strip (the reference's CH ONE knob). Brushed-aluminium cap, black skirt, a pointer line, a ring of tick dots; the dots up to the current position light orange. The 0 dB tick is larger.
- **Small knobs** (Trim, Device gain, Bass, Treble): black, with a white pointer line, like the reference's TRIM and AUX knobs.
- **Mute**: a round dark button with a thin light and dark bezel, no red ring, like the reference's CUE button. Lit: the button glows red.
- **Default**: a capsule button. Lit: amber glow.
- Disabled controls fade; they keep their shape.

## Meter

- One backlit analog VU meter per strip: warm cream face, black scale and needle, a soft amber glow around it, like the reference's two meters.
- The needle rests at the left stop when there is no signal.
- **Clip light**: a small red light (about 7 pt) in the meter's upper-left corner, behind the glass, with "CLIP" printed beside it. It is not a button. Off: dark red, still visible on the face. Lit while the strip clips, then fades out over about 2.5 s.

## Master

- The last strip, after a heavy divider, titled "Master". Top to bottom: Output menu, "Sound effects through" menu with a one-line note, Balance knob (small, black), one meter with clip light, Mute, Level knob, readout.
- When a row is added above the meter on a strip, raise `MasterStripView.topHeight` by the same height, and give app strips a `Color.clear` spacer of that height (not a hidden control: a hidden `Knob` still takes scroll input).
- Menus are native pop-ups under small engraved labels; long device names truncate.
- The meter, Mute and Level sit level with the other strips' meter, Mute and Level.
- Level uses the chrome knob with evenly spaced ticks and no 0 dB mark. The readout is a percent ("62 %"). When the mixer applies the volume itself, a small engraved "Software" label sits under the readout.
- Balance fades when the output has none.

## Status line

- One engraved line across the bottom of the window, centred, with monospaced digits: "48 kHz · 12.4 ms · CPU 3 %". A missing value shows "—".

## States

- No signal: the strip stays, with a dim "No signal" label.
- Disconnected: the whole strip fades.
- Banners sit above the strips, full width.

## How to check

Run `scripts/snapshot.sh`, then look at the PNG files next to `reference.png`. The `ui-reviewer` agent does this after any UI change.
