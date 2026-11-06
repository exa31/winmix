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
                VStack(spacing: 3) {
                    Image(nsImage: model.icon(for: ch))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 32, height: 32)
                        .opacity(ch.muted ? 0.45 : 1.0)
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)

                    Text(ch.name)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(ch.muted ? .secondary : .primary)
                        .frame(width: 82)
                        .help(ch.name)

                    // Condition Badge: Call App, Ducked, or Protected
                    if ch.isCallApp {
                        HStack(spacing: 2.5) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 7))
                            Text("CALL")
                                .font(.system(size: 7.5, weight: .black))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.green.opacity(0.2)))
                        .foregroundStyle(Color.green)
                        .help("\(ch.name) terdeteksi sebagai aplikasi panggilan aktif")
                    } else if ch.isDucked {
                        HStack(spacing: 2.5) {
                            Image(systemName: "arrow.down.right")
                                .font(.system(size: 7, weight: .bold))
                            Text("REDUP 25%")
                                .font(.system(size: 7, weight: .black))
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                        .foregroundStyle(Color.orange)
                        .help("Volume \(ch.name) otomatis diredupkan ke 25% karena ada panggilan telepon")
                    } else if model.isCallActive {
                        HStack(spacing: 2.5) {
                            Image(systemName: "shield.fill")
                                .font(.system(size: 7))
                            Text("100% BYPASS")
                                .font(.system(size: 7, weight: .black))
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.green.opacity(0.12)))
                        .foregroundStyle(Color.green)
                        .help("Volume \(ch.name) dipertahankan 100% (Anti-Ducking Aktif)")
                    }
                }
                .frame(height: 54)

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
                        height: 115
                    )

                    VerticalVUMeter(
                        level: ch.muted ? 0 : meter.level,
                        peak: ch.muted ? 0 : meter.peak,
                        isClassic: isClassic,
                        isMuted: ch.muted,
                        height: 115
                    )
                }
                .frame(height: 115)

                // Numerical Volume Percent
                if ch.isDucked {
                    HStack(spacing: 2) {
                        Text("\(Int((ch.gain * 100).rounded()))%")
                            .strikethrough()
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("25%")
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.orange)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.orange.opacity(0.12))
                    )
                } else {
                    Text("\(Int((ch.gain * 100).rounded()))")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(ch.muted ? .secondary : .primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isClassic ? Color.black.opacity(0.08) : Color.primary.opacity(0.06))
                        )
                }

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

