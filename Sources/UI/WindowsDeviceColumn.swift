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

            // If multiple devices are actively in use, show quick switcher tabs
            let inUse = model.activeInUseDevices()
            if inUse.count > 1 {
                HStack(spacing: 3) {
                    ForEach(inUse) { dev in
                        let isSelected = (model.focusedDeviceUID == dev.uid) || (model.focusedDeviceUID == nil && dev.name == model.outputName)
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if dev.name == model.outputName {
                                    model.focusDevice(uid: nil)
                                } else {
                                    model.focusDevice(uid: dev.uid)
                                }
                            }
                        } label: {
                            Image(systemName: iconForDeviceName(dev.name))
                                .font(.system(size: 9))
                                .foregroundStyle(isSelected ? (isClassic ? .primary : MixerTheme.win11Blue) : .secondary)
                                .frame(width: 22, height: 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(isSelected ? (isClassic ? Color.black.opacity(0.12) : MixerTheme.win11Blue.opacity(0.18)) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Kontrol volume untuk \(dev.name)")
                    }
                }
            }

            // Device Icon & Dropdown
            Menu {
                if !model.isFocusedDeviceMaster(), let dev = model.currentControlledDevice() {
                    Button {
                        model.selectOutput(dev.id)
                        model.focusDevice(uid: nil)
                    } label: {
                        Label("★ Jadikan Output Sistem", systemImage: "star.fill")
                    }
                    Divider()
                }

                Button {
                    model.focusDevice(uid: nil)
                    model.selectOutputAuto()
                } label: {
                    if model.isAutoOutput && model.isFocusedDeviceMaster() {
                        Label("Auto: Ikuti Sistem (\(model.outputName))", systemImage: "checkmark")
                    } else {
                        Text("Auto: Ikuti Sistem")
                    }
                }

                Divider()

                ForEach(model.outputDevices()) { dev in
                    Button {
                        model.selectOutput(dev.id)
                        model.focusDevice(uid: nil)
                    } label: {
                        if !model.isAutoOutput && dev.name == model.outputName && model.isFocusedDeviceMaster() {
                            Label(dev.name, systemImage: "checkmark")
                        } else {
                            Text(dev.name)
                        }
                    }
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: iconForDeviceName(model.currentDeviceName()))
                        .font(.system(size: 24))
                        .foregroundStyle(model.currentDeviceMute() ? .secondary : (isClassic ? .primary : MixerTheme.win11Blue))
                        .frame(width: 32, height: 32)

                    HStack(spacing: 2) {
                        if model.isAutoOutput && model.isFocusedDeviceMaster() {
                            Image(systemName: "sparkles")
                                .font(.system(size: 8))
                                .foregroundStyle(isClassic ? Color.accentColor : MixerTheme.win11Blue)
                        }
                        Text(model.currentDeviceName())
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
            .help(model.isAutoOutput ? "Output: Otomatis mengikuti sistem (\(model.currentDeviceName())) • Sinkron dengan F11/F12" : "Output: \(model.currentDeviceName()) • Sinkron dengan F11/F12")

            Spacer().frame(height: 4)

            // Fader + VU Meter pair
            HStack(alignment: .bottom, spacing: 6) {
                VerticalFader(
                    value: Binding(
                        get: { model.currentDeviceGain() },
                        set: { model.setControlledDeviceGain($0) }
                    ),
                    range: 0.0...1.0,
                    isClassic: isClassic,
                    isMuted: model.currentDeviceMute(),
                    height: 115
                )

                VerticalVUMeter(
                    level: model.currentDeviceMute() ? 0 : model.masterMeter.level,
                    peak: model.currentDeviceMute() ? 0 : model.masterMeter.peak,
                    isClassic: isClassic,
                    isMuted: model.currentDeviceMute(),
                    height: 115
                )
            }
            .frame(height: 115)

            // Numerical Volume Percent
            Text("\(Int((model.currentDeviceGain() * 100).rounded()))")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(model.currentDeviceMute() ? .secondary : .primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isClassic ? Color.black.opacity(0.08) : Color.primary.opacity(0.06))
                )

            // Mute Button
            Button(action: { model.toggleControlledDeviceMute() }) {
                Image(systemName: model.currentDeviceMute() ? "speaker.slash.fill" : "speaker.wave.3.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(model.currentDeviceMute() ? MixerTheme.win11MutedRed : .primary)
                    .frame(width: 28, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(model.currentDeviceMute() ? Color.red.opacity(0.12) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help(model.currentDeviceMute() ? "Unmute \(model.currentDeviceName())" : "Mute \(model.currentDeviceName())")
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

    private var deviceIconName: String {
        iconForDeviceName(model.outputName)
    }
}

