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

    var body: some View {
        VStack(spacing: 14) {
            header
            instrument
            controls
            schedule
            actions
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(Palette.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Afterglow needs attention. \(error)")
            } else {
                Text(model.enabled ? (model.emergencyShortcutAvailable ? "Restore instantly with ⌃⌥⌘R" : "Restore original is always available above.") : "Pause Night Shift or f.lux before turning on.")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(22)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.paper)
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .preferredColorScheme(model.darkInterface ? .dark : .light)
        .onChange(of: model.darkInterface) { _, dark in
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        }
        .frame(minWidth: 640, minHeight: 660)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.horizon.fill").font(.system(size: 22, weight: .light))
                .foregroundStyle(Palette.accent).accessibilityHidden(true)
            Text("afterglow").font(.system(size: 26, weight: .semibold, design: .rounded))
            Spacer()
            Button { model.darkInterface.toggle() } label: {
                Image(systemName: model.darkInterface ? "sun.max" : "moon")
                    .font(.system(size: 14)).frame(width: 36, height: 36)
            }.buttonStyle(.plain)
                .accessibilityLabel(model.darkInterface ? "Use paper appearance" : "Use dark appearance")
                .help(model.darkInterface ? "Paper appearance" : "Dark appearance")
        }
    }

    private var instrument: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text(benefitTitle)
                    .font(.system(size: 27, weight: .regular, design: .serif))
                    .foregroundStyle(Color(red: 0.953, green: 0.937, blue: 0.898))
                Text(benefitDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.81, green: 0.77, blue: 0.69))
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            SunsetDial(warmth: (6500 - model.displayed.kelvin) / 3800, dimming: model.displayed.dimming, active: model.enabled)
                .frame(width: 254, height: 240).scaleEffect(0.55)
                .frame(width: 144, height: 136).accessibilityHidden(true)
        }
        .padding(.horizontal, 18).padding(.vertical, 6)
        .background(Palette.dark, in: RoundedRectangle(cornerRadius: 14))
    }

    // Benefits describe actual output. Safety and restoration notices take priority.
    private var benefitTitle: String {
        if model.recoveryPending || model.restorationUnconfirmed || model.waitingForWake { return model.statusTitle }
        if !model.enabled { return "Your day was bright enough." }
        if model.isScheduledWaiting { return "A softer evening awaits." }
        if model.output.kelvin >= 6499 {
            return model.output.dimming > 0 ? "Less glare tonight." : "Your screen, unchanged."
        }
        return "Less glare. More evening."
    }
    private var benefitDetail: String {
        if model.recoveryPending || model.restorationUnconfirmed || model.waitingForWake || !model.enabled { return model.statusDetail }
        if model.isScheduledWaiting { return "Starts at \(model.timeLabel(model.fadeStart)). Turn on now to start sooner." }
        if model.output.kelvin >= 6499 { return "Move Blue-light reduction right for warmer colors." }
        if model.isLiveAdjustment, let end = model.previewUntil {
            return "On until your next wake time, \(end.formatted(date: .omitted, time: .shortened))."
        }
        return model.settings.scheduled ? "Following your bedtime schedule." : "On until you turn it off."
    }

    private var controls: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                controlHeading("Blue-light reduction", symbol: "sun.max")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(model.formattedKelvin).font(.system(size: 28, weight: .light, design: .rounded)).monospacedDigit()
                    Text("K").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    Spacer()
                    Text(warmthLabel).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
                Slider(value: Binding(get: { 6500 - model.settings.kelvin }, set: { model.adjustKelvin(6500 - $0) }), in: 0...3800)
                    .accessibilityLabel("Blue-light reduction")
                    .accessibilityValue("\(model.formattedKelvin) approximate kelvin; move right for warmer colors")
                    .help("Move right for warmer colors and less blue light.")
            }
            Rectangle().fill(Palette.line).frame(width: 1, height: 100)
            VStack(alignment: .leading, spacing: 8) {
                controlHeading("Extra dimming", symbol: "circle.lefthalf.filled")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(model.dimmingPercent)").font(.system(size: 28, weight: .light, design: .rounded)).monospacedDigit()
                    Text("%").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    Spacer()
                }
                Slider(value: Binding(get: { model.settings.dimming }, set: model.adjustDimming), in: 0...0.55)
                    .accessibilityLabel("Extra dimming")
                    .accessibilityValue("\(model.dimmingPercent) percent")
                    .help("Move right for a darker screen.")
            }
        }
        .disabled(model.recoveryPending)
        .opacity(model.recoveryPending ? 0.45 : 1)
    }

    private var warmthLabel: String {
        let k = model.settings.kelvin
        return k < 3300 ? "Candlelit" : k < 4400 ? "Warm" : k < 5700 ? "Soft warm" : "Daylight"
    }
    private func controlHeading(_ label: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Palette.secondary).accessibilityHidden(true)
            Text(label).font(.system(size: 12, weight: .medium))
        }
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Bedtime schedule").font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("Bedtime schedule", isOn: $model.settings.scheduled)
                    .labelsHidden().toggleStyle(.switch).accessibilityLabel("Use bedtime schedule")
            }
            HStack(spacing: 20) {
                timeControl("BEDTIME", selection: model.dateBinding(for: \.bedtime))
                timeControl("WAKE UP", selection: model.dateBinding(for: \.wake))
                VStack(alignment: .leading, spacing: 4) {
                    Text("START BEFORE BEDTIME").font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Palette.secondary)
                    Menu {
                        ForEach([30, 60, 90, 120, 180], id: \.self) { minutes in
                            Button("\(minutes) minutes before") { model.settings.fadeMinutes = minutes }
                        }
                    } label: {
                        Text("\(model.settings.fadeMinutes) min before").font(.system(size: 13, weight: .medium)).monospacedDigit()
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("Start warming \(model.settings.fadeMinutes) minutes before bedtime")
                }
                Spacer(minLength: 0)
            }.disabled(!model.settings.scheduled).opacity(model.settings.scheduled ? 1 : 0.5)
            Text(model.scheduleError ?? (model.settings.scheduled ? model.scheduleExplanation : "Schedule off. Use Turn on now whenever you like."))
                .font(.system(size: 11)).foregroundStyle(model.scheduleError == nil ? Palette.secondary : Palette.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func timeControl(_ label: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Palette.secondary)
            BorderlessTimeField(date: selection, label: label == "BEDTIME" ? "Bedtime" : "Wake time")
                .frame(width: 100, height: 26)
        }
    }

    private var immediateIsOn: Bool { model.enabled && (!model.settings.scheduled || model.isLiveAdjustment) }
    private var primaryTitle: String {
        model.recoveryPending ? "Retry Restore" : model.waitingForWake || immediateIsOn ? "Turn off" : "Turn on now"
    }
    private var actions: some View {
        HStack(spacing: 12) {
            Button("Restore original", action: model.restore).buttonStyle(QuietButton())
                .keyboardShortcut("0", modifiers: [.command, .shift])
                .disabled(!model.enabled && !model.recoveryPending && !model.waitingForWake)
            Spacer(minLength: 0)
            if model.settings.scheduled {
                Button(model.enabled && !model.isLiveAdjustment ? "Following schedule" : "Follow schedule", action: model.resumeSchedule)
                    .buttonStyle(QuietButton())
                    .disabled(model.isPreview || model.recoveryPending || model.waitingForWake || model.scheduleError != nil || (model.enabled && !model.isLiveAdjustment))
            }
            Button {
                if model.recoveryPending || model.waitingForWake || immediateIsOn { model.toggle() }
                else { model.previewSetting() }
            } label: {
                Label(primaryTitle, systemImage: model.recoveryPending ? "arrow.counterclockwise" : model.waitingForWake || immediateIsOn ? "pause.fill" : "power")
            }
            .buttonStyle(PrimaryButton())
            .disabled(model.isPreview || (model.scheduleError != nil && !model.enabled && !model.waitingForWake && !model.recoveryPending))
            .keyboardShortcut(.return, modifiers: .command)
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
    let dimming: Double
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
            let sunOpacity = 1 - min(0.55, max(0, dimming))
            let top = Color(red: 0.96, green: 0.76 - warmth * 0.12, blue: 0.42 - warmth * 0.16)
            let bottom = Color(red: 0.82, green: 0.34, blue: 0.17)
            // Keep the sun opaque so dimming does not reveal rings behind it.
            context.fill(Path(ellipseIn: sun), with: .color(Palette.dark))
            context.fill(Path(ellipseIn: sun), with: .linearGradient(Gradient(colors: [top.opacity(sunOpacity), bottom.opacity(sunOpacity)]), startPoint: CGPoint(x: center.x, y: sun.minY), endPoint: CGPoint(x: center.x, y: sun.maxY)))
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
