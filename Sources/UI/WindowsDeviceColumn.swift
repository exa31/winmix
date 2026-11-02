import SwiftUI
import CoreAudio

/// The Master Device strip (left column) of the Windows Volume Mixer.
struct WindowsDeviceColumn: View {
    @ObservedObject var model: MixerModel

    var isClassic: Bool { model.isClassicTheme }

    var body: some View {
        VStack(spacing: 8) {
            // Section Title
            Text("Device")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isClassic ? .primary : MixerTheme.win11Blue)
                .frame(maxWidth: .infinity, alignment: .center)

            // Device Icon & Dropdown
            Menu {
                Button {
                    model.selectOutputAuto()
                } label: {
                    if model.isAutoOutput {
                        Label("Auto: Ikuti Sistem (\(model.outputName))", systemImage: "checkmark")
                    } else {
                        Text("Auto: Ikuti Sistem")
                    }
                }

                Divider()

                ForEach(model.outputDevices()) { dev in
                    Button {
                        model.selectOutput(dev.id)
                    } label: {
                        if !model.isAutoOutput && dev.name == model.outputName {
                            Label(dev.name, systemImage: "checkmark")
                        } else {
                            Text(dev.name)
                        }
                    }
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: deviceIconName)
                        .font(.system(size: 24))
                        .foregroundStyle(model.masterMute ? .secondary : (isClassic ? .primary : MixerTheme.win11Blue))
                        .frame(width: 32, height: 32)

                    HStack(spacing: 2) {
                        if model.isAutoOutput {
                            Image(systemName: "sparkles")
                                .font(.system(size: 8))
                                .foregroundStyle(isClassic ? Color.accentColor : MixerTheme.win11Blue)
                        }
                        Text(model.outputName)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.primary)
                    }
                    .frame(width: 82, height: 26)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .help(model.isAutoOutput ? "Output: Otomatis mengikuti sistem (\(model.outputName))" : "Output manual: \(model.outputName)")

            Spacer().frame(height: 4)

            // Fader + VU Meter pair
            HStack(alignment: .bottom, spacing: 6) {
                VerticalFader(
                    value: Binding(
                        get: { model.masterGain },
                        set: { model.setMasterGain($0) }
                    ),
                    range: 0.0...1.0,
                    isClassic: isClassic,
                    isMuted: model.masterMute,
                    height: 140
                )

                VerticalVUMeter(
                    level: model.masterMute ? 0 : model.masterMeter.level,
                    peak: model.masterMute ? 0 : model.masterMeter.peak,
                    isClassic: isClassic,
                    isMuted: model.masterMute
                )
            }
            .frame(height: 140)

            // Numerical Volume Percent
            Text("\(Int((model.masterGain * 100).rounded()))")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(model.masterMute ? .secondary : .primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isClassic ? Color.black.opacity(0.08) : Color.primary.opacity(0.06))
                )

            // Mute Button
            Button(action: { model.toggleMasterMute() }) {
                Image(systemName: model.masterMute ? "speaker.slash.fill" : "speaker.wave.3.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(model.masterMute ? MixerTheme.win11MutedRed : .primary)
                    .frame(width: 28, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(model.masterMute ? Color.red.opacity(0.12) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help(model.masterMute ? "Unmute Master" : "Mute Master")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(width: 96)
        .background(
            RoundedRectangle(cornerRadius: isClassic ? 2 : 8)
                .fill(MixerTheme.cardBackground(isClassic: isClassic))
                .overlay(
                    RoundedRectangle(cornerRadius: isClassic ? 2 : 8)
                        .stroke(MixerTheme.columnBorder(isClassic: isClassic), lineWidth: 1)
                )
        )
    }

    private var deviceIconName: String {
        let name = model.outputName.lowercased()
        if name.contains("airpod") {
            return "airpodspro"
        } else if name.contains("headphone") || name.contains("headset") {
            return "headphones"
        } else if name.contains("display") || name.contains("hdmi") || name.contains("tv") {
            return "tv"
        } else {
            return "speaker.wave.2.fill"
        }
    }
}

