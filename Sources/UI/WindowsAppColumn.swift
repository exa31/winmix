import SwiftUI
import CoreAudio

/// One application's channel strip in the Windows Volume Mixer (Applications section).
struct WindowsAppColumn: View {
    @ObservedObject var model: MixerModel
    let id: AudioObjectID

    var isClassic: Bool { model.isClassicTheme }

    var body: some View {
        if let ch = model.channels.first(where: { $0.id == id }) {
            let meter = model.levels[id] ?? .init()

            VStack(spacing: 8) {
                // App Icon & Name
                VStack(spacing: 4) {
                    Image(nsImage: model.icon(for: ch))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 32, height: 32)
                        .opacity(ch.muted ? 0.45 : 1.0)
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)

                    Text(ch.name)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(ch.muted ? .secondary : .primary)
                        .frame(width: 82, height: 26)
                        .help(ch.name)
                }

                // Per-App Output Device Selector
                Menu {
                    Button {
                        model.setAppOutput(uid: nil, id: id)
                    } label: {
                        if ch.outputUID == nil {
                            Label("Default (\(model.outputName))", systemImage: "checkmark")
                        } else {
                            Text("Default (\(model.outputName))")
                        }
                    }

                    Divider()

                    ForEach(model.outputDevices()) { dev in
                        Button {
                            model.setAppOutput(uid: dev.uid, id: id)
                        } label: {
                            if ch.outputUID == dev.uid {
                                Label(dev.name, systemImage: "checkmark")
                            } else {
                                Text(dev.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: appOutputIcon(ch.outputUID))
                            .font(.system(size: 8))
                        Text(appOutputTitle(ch.outputUID))
                            .font(.system(size: 8.5, weight: .medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.06))
                    )
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 82)
                .help("Pilih output suara untuk \(ch.name)")

                Spacer().frame(height: 2)

                // Fader + VU Meter pair
                HStack(alignment: .bottom, spacing: 6) {
                    VerticalFader(
                        value: Binding(
                            get: { ch.gain },
                            set: { model.setGain($0, id: id) }
                        ),
                        range: 0.0...1.0,
                        isClassic: isClassic,
                        isMuted: ch.muted,
                        height: 140
                    )

                    VerticalVUMeter(
                        level: ch.muted ? 0 : meter.level,
                        peak: ch.muted ? 0 : meter.peak,
                        isClassic: isClassic,
                        isMuted: ch.muted
                    )
                }
                .frame(height: 140)

                // Numerical Volume Percent
                Text("\(Int((ch.gain * 100).rounded()))")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(ch.muted ? .secondary : .primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isClassic ? Color.black.opacity(0.08) : Color.primary.opacity(0.06))
                    )

                // Mute Button
                Button(action: { model.toggleMute(id: id) }) {
                    Image(systemName: ch.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(ch.muted ? MixerTheme.win11MutedRed : .primary)
                        .frame(width: 28, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(ch.muted ? Color.red.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(ch.muted ? "Unmute \(ch.name)" : "Mute \(ch.name)")
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .frame(width: 94)
            .background(
                RoundedRectangle(cornerRadius: isClassic ? 2 : 8)
                    .fill(MixerTheme.cardBackground(isClassic: isClassic))
                    .overlay(
                        RoundedRectangle(cornerRadius: isClassic ? 2 : 8)
                            .stroke(MixerTheme.columnBorder(isClassic: isClassic), lineWidth: 1)
                    )
            )
        }
    }

    private func appOutputTitle(_ uid: String?) -> String {
        guard let uid = uid else { return "Default" }
        if let match = model.outputDevices().first(where: { $0.uid == uid }) {
            let name = match.name
            if name.lowercased().contains("headphone") { return "Headphones" }
            if name.lowercased().contains("speaker") { return "Speakers" }
            if name.lowercased().contains("airpod") { return "AirPods" }
            return name
        }
        return "Custom"
    }

    private func appOutputIcon(_ uid: String?) -> String {
        guard let uid = uid else { return "arrow.triangle.branch" }
        let low = uid.lowercased()
        if low.contains("headphone") { return "headphones" }
        if low.contains("speaker") { return "speaker.wave.2.fill" }
        if low.contains("airpod") { return "airpodspro" }
        return "hifispeaker.fill"
    }
}

