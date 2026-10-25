import SwiftUI

/// The master strip, top to bottom: Output and Sound effects menus, Balance, meter, Mute, Level (master volume), readout.
/// The meter, Mute and Level sit level with the strips' own.
struct MasterStripView: View {
    let mixer: Mixer
    @Environment(\.colorScheme) private var scheme

    private var master: Master { mixer.master }

    /// Height of everything above the meter. Equals a strip's icon, name, Default button and two rows of small knobs, so the meters line up.
    private static let topHeight: CGFloat = 230

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                menu("Output", selection: Binding(get: { master.outputUID }, set: { if let uid = $0 { mixer.setOutput(uid: uid) } }),
                     choices: master.outputs)
                VStack(spacing: 3) {
                    menu("Sound effects through", selection: Binding(get: { master.effectsUID }, set: { if let uid = $0 { mixer.setEffectsOutput(uid: uid) } }),
                         choices: master.effectsOutputs)
                    Text("Stops macOS following the output.")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: scheme == .dark ? 0.62 : 0.30))   // dimInk is under 4.5:1 at this size
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                labelled("Balance") { balanceKnob }
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: Self.topHeight, alignment: .top)
            VUMeter(needleDB: master.needleDB, clip: master.clip)
            muteButton
            labelled("Level") { levelKnob }
            Text("\(Int((master.volume * 100).rounded())) %")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Panel.ink(scheme))
            Text("Software").engraved(size: 9).opacity(master.software ? 1 : 0)   // always laid out, so the strip never jumps
        }
        .padding(.top, 24).padding(.bottom, 7)
        .padding(.horizontal, 8)
        .frame(width: StripView.width)
    }

    // MARK: Menus

    /// An engraved label above a pop-up menu. A device that is not in the list (unplugged, or not yet read) still shows as "—".
    private func menu(_ title: String, selection: Binding<String?>, choices: [OutputChoice]) -> some View {
        let known = selection.wrappedValue.map { uid in choices.contains { $0.uid == uid } } ?? false
        let shown = Binding(get: { known ? selection.wrappedValue : nil }, set: { selection.wrappedValue = $0 })
        return VStack(spacing: 3) {
            Text(title).engraved(size: 9).lineLimit(1).minimumScaleFactor(0.8)
            Picker(title, selection: shown) {
                if !known { Text("—").tag(String?.none) }
                ForEach(choices) { choice in Text(choice.name).tag(String?.some(choice.uid)) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Mute

    /// Same look as the strips' Mute button.
    private var muteButton: some View {
        let lit = master.muted
        return VStack(spacing: 3) {
            Button { mixer.toggleMasterMute() } label: {
                Circle()
                    .fill(lit ? RadialGradient(colors: [Color(red: 1, green: 0.45, blue: 0.4), Color(red: 0.85, green: 0.05, blue: 0.05)],
                                               center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: 16)
                              : RadialGradient(colors: [Color(white: 0.22), Color(white: 0.06)],
                                               center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: 16))
                    .frame(width: 26, height: 26)
                    .padding(3)
                    .overlay(Circle().inset(by: 1.5).stroke(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.85 : 0.55), .black.opacity(0.6)],
                                                                          startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
                    .shadow(color: lit ? .red.opacity(0.8) : .clear, radius: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mute")
            .accessibilityValue(lit ? "On" : "Off")
            Text("Mute").engraved()
        }
    }

    // MARK: Knobs

    private func labelled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 2) {
            content()
            Text(title).engraved(size: 9).lineLimit(1)
        }
    }

    private var balanceKnob: some View {
        let value = master.balance
        return Knob(style: .small, fraction: value ?? 0.5, enabled: value != nil,
                    label: "Balance", valueText: Self.balanceText(value),
                    set: { mixer.setBalance($0) },
                    reset: { mixer.setBalance(0.5) })
    }

    private static func balanceText(_ value: Float?) -> String {
        guard let value else { return "Not available" }
        let side = Int(((value - 0.5) * 200).rounded())
        return side == 0 ? "Centre" : "\(abs(side)) percent \(side < 0 ? "left" : "right")"
    }

    /// Percent scale: evenly spaced ticks, no detent.
    private var levelKnob: some View {
        let ticks = (0...10).map { Float($0) / 10 }
        return Knob(style: .chrome, fraction: master.volume, ticks: ticks,
                    label: "Level", valueText: "\(Int((master.volume * 100).rounded())) percent",
                    set: { mixer.setMasterVolume($0) })
    }
}

/// One engraved line: sample rate, latency and CPU load.
struct StatusLine: View {
    let master: Master
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            // Engraved look, but mixed case: "kHz" must not become "KHZ".
            .font(.custom("Avenir Next Condensed", size: 12).weight(.semibold))
            .monospacedDigit()
            .tracking(1.1)
            .foregroundStyle(Panel.ink(scheme))
            .shadow(color: scheme == .dark ? .black.opacity(0.9) : .white.opacity(0.8), radius: 0, x: 0, y: scheme == .dark ? -1 : 1)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Status")
            .accessibilityValue(text)
    }

    private var text: String {
        let rate = master.sampleRate.map { $0 / 1000 }.map { Self.number($0) } ?? "—"
        let latency = master.latencyMs.map { String(format: "%.1f", $0) } ?? "—"
        return "\(rate) kHz · \(latency) ms · CPU \(master.sampleRate == nil ? "—" : String(Int((master.cpu * 100).rounded()))) %"
    }

    /// Up to one decimal: 44.1, 48, 96.
    private static func number(_ v: Double) -> String {
        let s = String(format: "%.1f", v)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}
