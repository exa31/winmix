import SwiftUI
import CoreAudio

/// Renders all active Master Output Devices side-by-side.
struct WindowsDeviceColumn: View {
    @ObservedObject var model: MixerModel

    var isClassic: Bool { model.isClassicTheme }

    var body: some View {
        let inUse = model.activeInUseDevices()

        VStack(alignment: .leading, spacing: 6) {
            // Section Title
            Text(inUse.count > 1 ? "Master Devices" : "Device")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isClassic ? .primary : MixerTheme.win11Blue)
                .frame(maxWidth: .infinity, alignment: inUse.count > 1 ? .leading : .center)
                .padding(.top, 10)
                .padding(.leading, 4)

            HStack(alignment: .top, spacing: 10) {
                ForEach(inUse) { dev in
                    WindowsSingleDeviceColumn(model: model, device: dev)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// The Master Device strip for an individual physical audio output device.
struct WindowsSingleDeviceColumn: View {
    @ObservedObject var model: MixerModel
    let device: MixerModel.OutputDevice

    var isClassic: Bool { model.isClassicTheme }
    var isSystemMaster: Bool { device.name == model.outputName }

    var body: some View {
        let currentGain = model.gain(for: device)
        let isMuted = model.mute(for: device)
        let meterData = model.meter(for: device)

        VStack(spacing: 8) {
            // Device Icon & Dropdown Menu
            Menu {
                if !isSystemMaster {
                    Button {
                        model.selectOutput(device.id)
                    } label: {
                        Label("★ Jadikan Output Sistem", systemImage: "star.fill")
                    }

                    Button {
                        for ch in model.channels where ch.outputUID == device.uid {
                            model.setAppOutput(uid: nil, id: ch.id)
                        }
                    } label: {
                        Label("Kembalikan Semua App ke Default", systemImage: "arrow.uturn.backward")
                    }

                    Divider()
                } else {
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

                    ForEach(model.outputDevices()) { d in
                        Button {
                            model.selectOutput(d.id)
                        } label: {
                            if !model.isAutoOutput && d.name == model.outputName {
                                Label(d.name, systemImage: "checkmark")
                            } else {
                                Text(d.name)
                            }
                        }
                    }
                }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: iconForDeviceName(device.name))
                        .font(.system(size: 24))
                        .foregroundStyle(isMuted ? .secondary : (isClassic ? .primary : (isSystemMaster ? MixerTheme.win11Blue : Color.accentColor)))
                        .frame(width: 32, height: 30)

                    // Role Badge
                    HStack(spacing: 2) {
                        if isSystemMaster {
                            Image(systemName: "sparkles")
                                .font(.system(size: 7.5))
                            Text("Sistem")
                                .font(.system(size: 8, weight: .bold))
                        } else {
                            Image(systemName: "speaker.badge.waveform.fill")
                                .font(.system(size: 7.5))
                            Text("Eksternal")
                                .font(.system(size: 8, weight: .bold))
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule().fill(isSystemMaster ? MixerTheme.win11Blue.opacity(0.12) : Color.orange.opacity(0.12))
                    )
                    .foregroundStyle(isSystemMaster ? (isClassic ? .primary : MixerTheme.win11Blue) : Color.orange)

                    Text(device.name)
                        .font(.system(size: 9.5, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .frame(width: 82, height: 26)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .help(isSystemMaster ? "Master Output Sistem • Sinkron dengan F11/F12" : "Master Output Eksternal • \(device.name)")

            Spacer().frame(height: 2)

            // Fader + VU Meter pair
            HStack(alignment: .bottom, spacing: 6) {
                VerticalFader(
                    value: Binding(
                        get: { model.gain(for: device) },
                        set: { model.setGain($0, for: device) }
                    ),
                    range: 0.0...1.0,
                    isClassic: isClassic,
                    isMuted: isMuted,
                    height: 115
                )

                VerticalVUMeter(
                    level: isMuted ? 0 : meterData.level,
                    peak: isMuted ? 0 : meterData.peak,
                    isClassic: isClassic,
                    isMuted: isMuted,
                    height: 115
                )
            }
            .frame(height: 115)

            // Numerical Volume Percent
            Text("\(Int((currentGain * 100).rounded()))")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(isMuted ? .secondary : .primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isClassic ? Color.black.opacity(0.08) : Color.primary.opacity(0.06))
                )

            // Mute Button
            Button(action: { model.toggleMute(for: device) }) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(isMuted ? MixerTheme.win11MutedRed : .primary)
                    .frame(width: 28, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isMuted ? Color.red.opacity(0.12) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help(isMuted ? "Unmute \(device.name)" : "Mute \(device.name)")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(width: 96)
        .background(
            RoundedRectangle(cornerRadius: isClassic ? 2 : 8)
                .fill(MixerTheme.cardBackground(isClassic: isClassic))
                .overlay(
                    RoundedRectangle(cornerRadius: isClassic ? 2 : 8)
                        .stroke(isSystemMaster ? (isClassic ? MixerTheme.columnBorder(isClassic: isClassic) : MixerTheme.win11Blue.opacity(0.3)) : MixerTheme.columnBorder(isClassic: isClassic), lineWidth: 1)
                )
        )
    }

    private func iconForDeviceName(_ rawName: String) -> String {
        let name = rawName.lowercased()
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
