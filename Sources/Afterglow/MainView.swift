import SwiftUI
import AfterglowCore

enum Palette {
    private static func adaptive(_ name: String, light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name(name)) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    static let paper = adaptive("Paper", light: NSColor(red: 0.953, green: 0.937, blue: 0.898, alpha: 1), dark: NSColor(red: 0.105, green: 0.102, blue: 0.094, alpha: 1))
    static let ink = adaptive("Ink", light: NSColor(red: 0.161, green: 0.145, blue: 0.122, alpha: 1), dark: NSColor(red: 0.94, green: 0.91, blue: 0.85, alpha: 1))
    static let secondary = adaptive("Secondary", light: NSColor(red: 0.40, green: 0.37, blue: 0.32, alpha: 1), dark: NSColor(red: 0.72, green: 0.68, blue: 0.61, alpha: 1))
    static let accent = adaptive("Accent", light: NSColor(red: 0.70, green: 0.25, blue: 0.105, alpha: 1), dark: NSColor(red: 0.84, green: 0.44, blue: 0.23, alpha: 1))
    static let line = adaptive("Line", light: NSColor(red: 0.82, green: 0.79, blue: 0.73, alpha: 1), dark: NSColor(red: 0.26, green: 0.24, blue: 0.21, alpha: 1))
    static let buttonText = adaptive("ButtonText", light: .white, dark: NSColor(red: 0.105, green: 0.102, blue: 0.094, alpha: 1))
    static let dark = Color(red: 0.145, green: 0.137, blue: 0.125)
}

struct MainView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
            VStack(spacing: 20) {
                header
                instrument
                controls
                schedule
            }
            .padding(28)
            .frame(maxWidth: 840)
            .frame(maxWidth: .infinity)
            }
            VStack(spacing: 14) { actionBar; footer }
                .padding(.horizontal, 28).padding(.bottom, 20).padding(.top, 14)
        }
        .background(Palette.paper)
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .preferredColorScheme(model.darkInterface ? .dark : .light)
        .onChange(of: model.darkInterface) { _, dark in
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        }
        .frame(minWidth: 640, minHeight: 720)
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 10) {
                Image(systemName: "sun.horizon.fill").font(.system(size: 25, weight: .light)).foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                Text("afterglow").font(.system(size: 29, weight: .semibold, design: .rounded)).tracking(-1.3)
            }
            Spacer()
            Button { model.darkInterface.toggle() } label: {
                Image(systemName: model.darkInterface ? "sun.max" : "moon")
                    .font(.system(size: 14)).frame(width: 36, height: 36)
            }.buttonStyle(.plain)
                .accessibilityLabel(model.darkInterface ? "Use paper appearance" : "Use low-glare appearance")
                .help(model.darkInterface ? "Paper appearance" : "Low-glare appearance")
            VStack(alignment: .trailing, spacing: 4) {
                Text("PERSONAL LIGHT").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2)
                Text("A softer end to the day.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
        }
    }

    private var instrument: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 7) {
                    Circle().fill(model.enabled ? Color(red: 0.95, green: 0.63, blue: 0.29) : Color.white.opacity(0.45))
                        .frame(width: 6, height: 6)
                    Text(model.recoveryPending ? "RESTORE NEEDS ATTENTION" : model.waitingForWake ? "RESUMES AFTER WAKE" : model.enabled ? "COMFORT IS ON" : "EVENING PREVIEW")
                        .font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.8)
                }
                .foregroundStyle(Color(red: 0.91, green: 0.80, blue: 0.61))
                Text("Less glare.\nMore evening.")
                    .font(.system(size: 32, weight: .regular, design: .serif)).tracking(-0.9).lineSpacing(-1)
                    .foregroundStyle(Color(red: 0.953, green: 0.937, blue: 0.898))
                Text(model.recoveryPending ? "Display colors are unconfirmed." : model.enabled ? model.output.phase : "Tune the light. Keep the calm.")
                    .font(.system(size: 12)).foregroundStyle(Color(red: 0.78, green: 0.74, blue: 0.67))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SunsetDial(warmth: (6500 - model.displayed.kelvin) / 3800, active: model.enabled)
                .frame(width: 254, height: 180).accessibilityHidden(true)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(Palette.dark, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .bottom) {
            HStack(spacing: 3) {
                ForEach(0..<48, id: \.self) { n in
                    Rectangle().fill(Color.white.opacity(n % 4 == 0 ? 0.13 : 0.05)).frame(width: 1, height: n % 4 == 0 ? 6 : 3)
                }
            }.padding(.bottom, 8).accessibilityHidden(true)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
        HStack {
            Text("Your evening setting").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondary)
            Spacer()
            if model.settings.scheduled {
                Button(model.isLiveAdjustment ? "Resume schedule" : "Apply now") {
                    if model.isLiveAdjustment { model.resumeSchedule() } else { model.previewSetting() }
                }.buttonStyle(.plain).foregroundStyle(Palette.accent)
                    .disabled(model.isPreview || model.recoveryPending || model.waitingForWake || model.scheduleError != nil)
            }
        }
        HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 12) {
                controlHeading("Warmth", symbol: "sun.max")
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(model.formattedKelvin).font(.system(size: 37, weight: .light, design: .rounded)).monospacedDigit().tracking(-1.5)
                    Text("K").font(.system(size: 15)).foregroundStyle(Palette.secondary)
                    Spacer()
                    Text(warmthLabel).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent)
                }
                Slider(value: Binding(get: { model.settings.kelvin }, set: model.adjustKelvin), in: 2700...6500)
                    .accessibilityLabel("Evening color temperature")
                    .accessibilityValue("\(Int(model.settings.kelvin)) approximate kelvin")
                scaleLabels("CANDLELIT", "DAYLIGHT")
            }
            Rectangle().fill(Palette.line).frame(width: 1, height: 128)
            VStack(alignment: .leading, spacing: 12) {
                controlHeading("Extra dimming", symbol: "circle.lefthalf.filled")
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(model.dimmingPercent)").font(.system(size: 37, weight: .light, design: .rounded)).monospacedDigit().tracking(-1.5)
                    Text("%").font(.system(size: 15)).foregroundStyle(Palette.secondary)
                    Spacer()
                    Text(model.dimmingPercent == 0 ? "Original" : "Softer").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent)
                }
                Slider(value: Binding(get: { model.settings.dimming }, set: model.adjustDimming), in: 0...0.55)
                    .accessibilityLabel("Evening extra dimming")
                    .accessibilityValue("\(Int((model.settings.dimming * 100).rounded())) percent")
                scaleLabels("ORIGINAL", "LOW LIGHT")
            }
        }
        .disabled(model.recoveryPending)
        .opacity(model.recoveryPending ? 0.45 : 1)
        Text(model.isLiveAdjustment ? "Applied now. Your schedule resumes in about one minute, or choose Resume schedule." : model.enabled && model.settings.scheduled ? "Drag to try your setting for one minute. Now: \(Int(model.output.kelvin)) K · \(Int((model.output.dimming * 100).rounded()))% dimming." : model.enabled ? "Applied now. Adjust the sliders to change your display." : "Choose Enable comfort to apply your setting.")
            .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var warmthLabel: String {
        let k = model.settings.kelvin
        return k < 3300 ? "Candlelit" : k < 4400 ? "Warm" : k < 5700 ? "Soft white" : "Daylight"
    }
    private func controlHeading(_ label: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Palette.secondary).accessibilityHidden(true)
            Text(label).font(.system(size: 13, weight: .medium))
        }
    }
    private func scaleLabels(_ left: String, _ right: String) -> some View {
        HStack {
            Text(left); Spacer(); Text(right)
        }.font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.1).foregroundStyle(Palette.secondary)
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ease into bedtime").font(.system(size: 15, weight: .semibold))
                    Text(model.settings.scheduled ? model.nextTransition : "Switch on for an automatic evening fade.")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Toggle("Bedtime transition", isOn: $model.settings.scheduled)
                    .labelsHidden().toggleStyle(.switch).accessibilityLabel("Use bedtime transition")
            }
            if model.settings.scheduled {
            HStack(spacing: 20) {
                timeControl("BEDTIME", selection: model.dateBinding(for: \.bedtime))
                timeControl("WAKE UP", selection: model.dateBinding(for: \.wake))
                VStack(alignment: .leading, spacing: 6) {
                    Text("FADE IN").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1)
                        .foregroundStyle(Palette.secondary)
                    Menu {
                        ForEach([30, 60, 90, 120, 180], id: \.self) { minutes in
                            Button("\(minutes) min") { model.settings.fadeMinutes = minutes }
                        }
                    } label: {
                        Text("\(model.settings.fadeMinutes) min")
                            .font(.system(size: 13, weight: .medium)).monospacedDigit()
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("Fade duration, \(model.settings.fadeMinutes) minutes")
                }
                Spacer(minLength: 0)
            }
            EveningTimeline(enabled: model.settings.scheduled)
                .frame(height: 20).accessibilityHidden(true)
            HStack {
                Text("\(model.timeLabel(model.fadeStart))  ·  FADE BEGINS")
                Spacer()
                Text("\(model.timeLabel(model.settings.bedtime))  ·  LIGHTS LOW")
            }.font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(0.7).foregroundStyle(Palette.secondary)
            if let problem = model.scheduleError {
                Text(problem).font(.system(size: 12)).foregroundStyle(Palette.accent)
            }
            } else {
                Text("\(model.timeLabel(model.settings.bedtime)) bedtime  ·  \(model.settings.fadeMinutes)-minute fade  ·  \(model.timeLabel(model.settings.wake)) wake")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
        }
        .padding(.vertical, 12)
    }
    private func timeControl(_ label: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Palette.secondary)
            BorderlessTimeField(date: selection, label: label == "BEDTIME" ? "Bedtime" : "Wake time")
                .frame(width: 100, height: 28)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.scheduleError != nil && !model.enabled && !model.recoveryPending ? "Check your sleep times" : model.statusTitle).font(.system(size: 13, weight: .semibold))
                Text(model.recoveryPending ? "Retry Restore before starting another session." : model.enabled ?
                     (model.emergencyShortcutAvailable ? "Restore anytime with ⌃⌥⌘R" : "Restore from the menu bar or with ⇧⌘0") :
                     model.waitingForWake ? "Comfort will resume automatically. Turn off to cancel." : model.scheduleError ?? model.notice)
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            if model.enabled && !model.recoveryPending {
                Button("Restore original", action: model.restore).buttonStyle(QuietButton())
                    .keyboardShortcut("0", modifiers: [.command, .shift])
            }
            Button(action: model.toggle) {
                HStack(spacing: 8) {
                    Image(systemName: model.recoveryPending ? "arrow.counterclockwise" : (model.enabled || model.waitingForWake) ? "pause.fill" : "power")
                    Text(model.recoveryPending ? "Retry Restore" : (model.enabled || model.waitingForWake) ? "Turn off" : "Enable comfort")
                }
            }
            .buttonStyle(PrimaryButton())
            .disabled(model.isPreview || (model.scheduleError != nil && !model.enabled && !model.waitingForWake && !model.recoveryPending))
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Palette.line).frame(height: 1)
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(Palette.accent)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(model.notice).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Label("On your Mac. Nothing sent anywhere.", systemImage: "lock")
                Spacer()
                Text("01 / LOCAL EDITION").font(.system(size: 8, design: .monospaced)).tracking(1)
            }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
            if !model.enabled && !model.recoveryPending {
                Text("Pause f.lux and Night Shift before enabling. Warmth is approximate; use your usual brightness keys too.")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
        }
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Palette.buttonText).padding(.horizontal, 18).frame(height: 44)
            .background(Palette.accent.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}
struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.ink)
            .padding(.horizontal, 12).frame(height: 44)
            .background(Palette.line.opacity(configuration.isPressed ? 0.5 : 0.25), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct SunsetDial: View {
    let warmth: Double
    let active: Bool
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2 + 1)
            for i in 0..<9 {
                let radius = CGFloat(51 + i * 6)
                let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(Color(red: 0.91, green: 0.65, blue: 0.37).opacity(0.09 + Double(8 - i) * 0.009)), lineWidth: 0.7)
            }
            let sun = CGRect(x: center.x - 65, y: center.y - 65, width: 130, height: 130)
            let top = Color(red: 0.96, green: 0.76 - warmth * 0.12, blue: 0.42 - warmth * 0.16)
            let bottom = Color(red: 0.82, green: 0.34, blue: 0.17)
            context.fill(Path(ellipseIn: sun), with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: CGPoint(x: center.x, y: sun.minY), endPoint: CGPoint(x: center.x, y: sun.maxY)))
            for row in 0..<8 {
                let y = center.y + CGFloat(row * 8)
                var stripe = Path(); stripe.move(to: CGPoint(x: 20, y: y)); stripe.addLine(to: CGPoint(x: size.width - 20, y: y))
                context.stroke(stripe, with: .color(Palette.dark), lineWidth: CGFloat(2 + row))
            }
            for index in 0..<29 {
                let angle = Double(index) / 28 * Double.pi + Double.pi
                let r: Double = 111
                let p = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
                let q = CGPoint(x: center.x + cos(angle) * (r - (index % 7 == 0 ? 7 : 3)), y: center.y + sin(angle) * (r - (index % 7 == 0 ? 7 : 3)))
                var tick = Path(); tick.move(to: p); tick.addLine(to: q)
                context.stroke(tick, with: .color(Color.white.opacity(0.22)), lineWidth: 1)
            }
            let angle = Double.pi + (1 - warmth) * Double.pi
            let marker = CGPoint(x: center.x + cos(angle) * 111, y: center.y + sin(angle) * 111)
            context.fill(Path(ellipseIn: CGRect(x: marker.x - 3, y: marker.y - 3, width: 6, height: 6)), with: .color(Color(red: 0.953, green: 0.937, blue: 0.898)))
            context.draw(Text("SLOW DOWN / TUNE IN").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.5).foregroundColor(Color(red: 0.73, green: 0.66, blue: 0.55)), at: CGPoint(x: center.x, y: size.height - 8))
        }
    }
}

struct EveningTimeline: View {
    var enabled: Bool
    var body: some View {
        Canvas { context, size in
            for i in 0..<60 {
                let t = Double(i) / 59
                let ease = t * t * (3 - 2 * t)
                let height = 5 + ease * 23
                let x = t * (size.width - 3)
                let rect = CGRect(x: x, y: size.height - height, width: 2.5, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(enabled ? Palette.accent.opacity(0.22 + ease * 0.65) : Palette.secondary.opacity(0.2 + ease * 0.16)))
            }
        }
    }
}

/// Native, keyboard-editable time control without permanent field borders.
struct BorderlessTimeField: NSViewRepresentable {
    @Binding var date: Date
    let label: String
    func makeCoordinator() -> Coordinator { Coordinator(date: $date) }
    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textField
        picker.datePickerElements = [.hourMinute]
        picker.isBordered = false; picker.isBezeled = false; picker.drawsBackground = false
        picker.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        picker.textColor = .labelColor
        picker.setAccessibilityLabel(label)
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        return picker
    }
    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.date = $date
        if picker.dateValue != date { picker.dateValue = date }
        picker.setAccessibilityLabel(label)
    }
    final class Coordinator: NSObject {
        var date: Binding<Date>
        init(date: Binding<Date>) { self.date = date }
        @objc func changed(_ sender: NSDatePicker) { date.wrappedValue = sender.dateValue }
    }
}
