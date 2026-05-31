import SwiftUI
import UIKit

private enum AppLanguage {
    case korean
    case english

    var shortTitle: String {
        switch self {
        case .korean: "KR"
        case .english: "EN"
        }
    }

    var settingsTitle: String {
        switch self {
        case .korean: "설정"
        case .english: "Settings"
        }
    }

    var languageTitle: String {
        switch self {
        case .korean: "언어선택"
        case .english: "Language"
        }
    }

    var appInfoTitle: String {
        switch self {
        case .korean: "앱정보"
        case .english: "App Info"
        }
    }

    var termsTitle: String {
        switch self {
        case .korean: "이용약관 및 정책"
        case .english: "Terms & Policy"
        }
    }
}

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel = AlarmViewModel()
    @State private var isInfoPresented = false
    @State private var selectedLanguage: AppLanguage = .korean
    private var accentColor: Color { viewModel.alarmTone.tint }
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    private let legalPageURL = URL(string: "https://gotgam100.github.io/dingloop/index.html")!

    var body: some View {
        ZStack {
            AppBackground(accent: accentColor)

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 20)
                    .padding(.horizontal, 24)

                ZStack(alignment: .top) {
                    mainContent

                    if isInfoPresented {
                        settingsPanel
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .zIndex(1)
                    }
                }
                .clipped()
            }
        }
        .foregroundStyle(Color.ampText)
    }

    private var topBar: some View {
        HStack {
            Circle()
                .fill(viewModel.isRunning ? accentColor : Color.ampText.opacity(0.72))
                .frame(width: 9, height: 9)
                .shadow(color: (viewModel.isRunning ? accentColor : Color.ampText).opacity(0.35), radius: 8)

            Text("DingLoop")
                .font(.paper(.semiBold, size: 17))
                .foregroundStyle(Color.ampText.opacity(0.82))

            Spacer()

            Button {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                    isInfoPresented.toggle()
                }
            } label: {
                Rectangle()
                    .fill(accentColor)
                    .frame(width: 16, height: 16)
                    .shadow(color: accentColor.opacity(0.22), radius: 8, y: 5)
                    .rotationEffect(.degrees(isInfoPresented ? 45 : 0))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isInfoPresented ? "Close app information" : "Open app information")
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 18)

            ClockDial(
                intervalMinutes: $viewModel.intervalMinutes,
                remainingSeconds: viewModel.remainingSeconds,
                isRunning: viewModel.isRunning,
                isPaused: viewModel.isPaused,
                currentLoopNumber: viewModel.currentLoopNumber,
                accent: accentColor,
                onCenterLongPress: {
                    viewModel.toggleTimer()
                },
                onCenterDoubleTap: {
                    viewModel.togglePause()
                }
            )
            .padding(12)
            .padding(.horizontal, 18)

            Spacer(minLength: 18)

            quickIntervals
                .padding(.horizontal, 26)
                .padding(.bottom, 18)

            controlDock
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
        }
    }

    private var settingsPanel: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 52)

            Text(selectedLanguage.settingsTitle)
                .font(.paper(.black, size: 28))
                .foregroundStyle(accentColor)

            VStack(spacing: 12) {
                languageRow
                infoRow(selectedLanguage.appInfoTitle, value: "v\(appVersion)")
                linkRow(selectedLanguage.termsTitle)
            }
            .padding(.horizontal, 26)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color.ampBlack.opacity(0.98), Color.ampPanel.opacity(0.98)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(accentColor.opacity(0.26))
                .frame(height: 2)
        }
    }

    private var languageRow: some View {
        HStack {
            Text(selectedLanguage.languageTitle)
                .font(.paper(.medium, size: 14))
                .foregroundStyle(Color.ampText.opacity(0.56))

            Spacer()

            HStack(spacing: 6) {
                languageButton(.korean)
                languageButton(.english)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(Color.black.opacity(0.28), in: Capsule())
    }

    private func languageButton(_ language: AppLanguage) -> some View {
        Button {
            selectedLanguage = language
        } label: {
            Text(language.shortTitle)
                .font(.paper(.bold, size: 12))
                .foregroundStyle(selectedLanguage == language ? Color.black : Color.ampText.opacity(0.72))
                .frame(width: 54, height: 30)
                .background(selectedLanguage == language ? accentColor : Color.ampPanel, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.paper(.medium, size: 14))
                .foregroundStyle(Color.ampText.opacity(0.56))

            Spacer()

            Text(value)
                .font(.paper(.bold, size: 14))
                .foregroundStyle(Color.ampText.opacity(0.86))
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(Color.black.opacity(0.28), in: Capsule())
    }

    private func linkRow(_ title: String) -> some View {
        Button {
            guard var components = URLComponents(url: legalPageURL, resolvingAgainstBaseURL: false) else {
                openURL(legalPageURL)
                return
            }
            components.fragment = selectedLanguage == .korean ? "ko" : "en"
            openURL(components.url ?? legalPageURL)
        } label: {
            HStack {
                Text(title)
                    .font(.paper(.medium, size: 14))
                    .foregroundStyle(Color.ampText.opacity(0.72))

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.ampText.opacity(0.44))
            }
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background(Color.black.opacity(0.28), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var quickIntervals: some View {
        HStack(spacing: 8) {
            ForEach([1, 5, 10, 30, 60], id: \.self) { minutes in
                Button {
                    viewModel.intervalMinutes = minutes
                } label: {
                    Text("\(minutes)")
                        .font(.paper(.bold, size: 18))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
                .buttonStyle(IntervalButtonStyle(isSelected: viewModel.intervalMinutes == minutes, accent: accentColor))
                .disabled(viewModel.isRunning)
                .accessibilityLabel("\(minutes) minutes")
            }
        }
    }

    private var controlDock: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            IconButton(
                systemName: viewModel.alarmTone.systemName,
                tint: accentColor,
                isActive: true
            ) {
                viewModel.cycleAlarmTone()
            }
            .id(viewModel.alarmTone.id)
            .accessibilityLabel("Change ringtone")

            IconButton(
                systemName: "speaker.wave.2.fill",
                tint: .ampText,
                isActive: false
            ) {
                viewModel.previewDefaultSound()
            }
            .accessibilityLabel("Preview sound")

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.ampPanel.opacity(0.96), in: Capsule())
        .shadow(color: .black.opacity(0.38), radius: 22, y: 14)
    }
}

struct AppBackground: View {
    var accent: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.ampBlack, Color(red: 0.035, green: 0.036, blue: 0.038)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [accent.opacity(0.2), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 340
            )

            RadialGradient(
                colors: [Color.white.opacity(0.08), .clear],
                center: .topLeading,
                startRadius: 30,
                endRadius: 260
            )
        }
        .ignoresSafeArea()
    }
}

struct ClockDial: View {
    @Binding var intervalMinutes: Int
    var remainingSeconds: Int
    var isRunning: Bool
    var isPaused: Bool
    var currentLoopNumber: Int
    var accent: Color
    var onCenterLongPress: () -> Void
    var onCenterDoubleTap: () -> Void

    @GestureState private var isCenterPressed = false
    @State private var lastHapticMinute: Int?
    @State private var isDraggingHandle = false
    @State private var dragMinute: Int?
    private let range = 1...360

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let lineWidth = max(16, size * 0.06)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = (size / 2) - lineWidth - 12
            let dialProgress = dialProgress(for: intervalMinutes)
            let runtimeProgress = runningProgress
            let activeProgress = isRunning ? max(runtimeProgress, 0.0012) : dialProgress
            let angle = Angle.degrees(Double(dialProgress) * 360 - 90)
            let handleRadius = radius - lineWidth * 0.1
            let handlePoint = CGPoint(
                x: center.x + cos(angle.radians) * handleRadius,
                y: center.y + sin(angle.radians) * handleRadius
            )

            ZStack {
                Circle()
                    .fill(Color.ampDial)
                    .overlay(recordGrooves(size: size, lineWidth: lineWidth))
                    .overlay(
                        Circle()
                            .stroke(Color.ampStroke.opacity(0.9), lineWidth: max(10, lineWidth * 0.7))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                            .padding(lineWidth * 0.48)
                    )
                    .shadow(color: .black.opacity(0.75), radius: 26, x: 0, y: 16)

                Circle()
                    .stroke(Color.black.opacity(0.94), lineWidth: max(22, size * 0.19))
                    .padding(lineWidth * 0.95)

                Circle()
                    .trim(from: 0, to: CGFloat(activeProgress))
                    .stroke(
                        accent.opacity(isDraggingHandle ? 0.96 : 0.52),
                        style: StrokeStyle(lineWidth: max(3, lineWidth * 0.18), lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(lineWidth * 0.38)
                    .shadow(color: accent.opacity(isDraggingHandle ? 0.35 : 0.12), radius: 12)
                    .animation(.smooth(duration: 0.2), value: remainingSeconds)
                    .animation(.smooth(duration: 0.18), value: intervalMinutes)
                    .animation(.smooth(duration: 0.16), value: isDraggingHandle)

                centerButton(size: size)

                Circle()
                    .stroke(accent.opacity(0.9), lineWidth: 1.6)
                    .frame(width: max(10, lineWidth * 0.48), height: max(10, lineWidth * 0.48))
                    .position(x: center.x, y: center.y - radius + lineWidth * 0.05)

                Circle()
                    .fill(accent)
                    .frame(width: lineWidth * (isDraggingHandle ? 2.0 : 1.72), height: lineWidth * (isDraggingHandle ? 2.0 : 1.72))
                    .position(handlePoint)
                    .shadow(color: accent.opacity(isDraggingHandle ? 0.48 : 0.24), radius: 16, y: 8)
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDraggingHandle)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !isRunning else { return }
                        if !isDraggingHandle {
                            guard isRecordTouch(value.startLocation, center: center, radius: radius, lineWidth: lineWidth)
                                    || isHandleTouch(value.startLocation, handle: handlePoint, lineWidth: lineWidth) else { return }
                            isDraggingHandle = true
                        }
                        let nextMinute = minutes(for: value.location, in: center)
                        guard nextMinute != intervalMinutes else { return }
                        let previousMinute = intervalMinutes
                        intervalMinutes = nextMinute
                        dragMinute = nextMinute
                        playDialHaptic(from: previousMinute, to: nextMinute)
                    }
                    .onEnded { _ in
                        lastHapticMinute = nil
                        dragMinute = nil
                        isDraggingHandle = false
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func centerButton(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(accent)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(isCenterPressed ? 0.32 : 0.16), lineWidth: 1.5)
                )
                .shadow(
                    color: accent.opacity(isCenterPressed ? 0.16 : 0.32),
                    radius: isCenterPressed ? 8 : 24,
                    y: isCenterPressed ? 4 : 13
                )

            VStack(spacing: 2) {
                Text(isRunning ? remainingText : "\(intervalMinutes)")
                    .font(.paper(.black, size: isRunning ? size * 0.13 : size * 0.22))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.54)

                if isRunning {
                    loopIndicator(size: size)
                    .frame(height: max(12, size * 0.04))
                } else {
                    Text("min")
                        .font(.paper(.bold, size: max(12, size * 0.038)))
                        .foregroundStyle(Color.black.opacity(0.58))
                        .frame(height: max(12, size * 0.04))
                }
            }
            .foregroundStyle(Color.black)
            .frame(width: size * 0.48)
        }
        .frame(width: size * 0.58, height: size * 0.58)
        .scaleEffect(isCenterPressed ? 0.92 : (isRunning ? 0.95 : 1))
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isCenterPressed)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isRunning)
        .animation(.smooth(duration: 0.14), value: isPaused)
        .accessibilityLabel(isRunning ? "Stop timer" : "Start timer")
        .gesture(
            LongPressGesture(minimumDuration: 0.38, maximumDistance: 18)
                .updating($isCenterPressed) { currentValue, state, _ in
                    state = currentValue
                }
                .onEnded { _ in
                    let feedback = UIImpactFeedbackGenerator(style: .heavy)
                    feedback.prepare()
                    feedback.impactOccurred(intensity: 1.0)
                    onCenterLongPress()
                }
        )
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    guard isRunning else { return }
                    let feedback = UIImpactFeedbackGenerator(style: .medium)
                    feedback.prepare()
                    feedback.impactOccurred(intensity: 0.8)
                    onCenterDoubleTap()
                }
        )
    }

    @ViewBuilder
    private func loopIndicator(size: CGFloat) -> some View {
        let indicatorColor = isPaused ? Color.white : Color.black.opacity(0.72)

        if currentLoopNumber > 1 {
            Text("\(currentLoopNumber)")
                .font(.paper(.black, size: max(10, size * 0.034)))
                .monospacedDigit()
                .foregroundStyle(indicatorColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else if isPaused {
            Rectangle()
                .fill(indicatorColor)
                .frame(width: max(6, size * 0.02), height: max(6, size * 0.02))
        } else {
            Circle()
                .fill(indicatorColor)
                .frame(width: max(5, size * 0.018), height: max(5, size * 0.018))
        }
    }

    private func recordGrooves(size: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            ForEach(0..<9, id: \.self) { index in
                let inset = lineWidth * 1.25 + CGFloat(index) * size * 0.036
                Circle()
                    .stroke(Color.white.opacity(index.isMultiple(of: 3) ? 0.055 : 0.032), lineWidth: 0.8)
                    .padding(inset)
            }

            Circle()
                .stroke(Color.black.opacity(0.35), lineWidth: 1)
                .padding(size * 0.31)
        }
    }

    private var runningProgress: Double {
        let total = max(1, intervalMinutes * 60)
        return min(max(Double(total - remainingSeconds) / Double(total), 0), 1)
    }

    private var remainingText: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    private func dialProgress(for minutes: Int) -> Double {
        Double(positionMinute(for: minutes)) / 60
    }

    private func minutes(for point: CGPoint, in center: CGPoint) -> Int {
        let positionMinute = positionMinute(for: point, in: center)
        let currentMinute = dragMinute ?? intervalMinutes
        let currentPosition = self.positionMinute(for: currentMinute)
        var delta = positionMinute - currentPosition

        if delta > 30 {
            delta -= 60
        } else if delta < -30 {
            delta += 60
        }

        var nextMinute = currentMinute + delta
        if nextMinute > range.upperBound {
            nextMinute = range.lowerBound
        } else if nextMinute < range.lowerBound {
            nextMinute = range.upperBound
        }

        return nextMinute
    }

    private func positionMinute(for point: CGPoint, in center: CGPoint) -> Int {
        let dx = point.x - center.x
        let dy = point.y - center.y
        var degrees = atan2(dy, dx) * 180 / .pi + 90
        if degrees < 0 {
            degrees += 360
        }
        let normalized = min(max(degrees / 360, 0), 1)
        let value = normalized * 60
        let minute = Int(value.rounded())
        return min(max(minute == 0 ? 60 : minute, 1), 60)
    }

    private func positionMinute(for minutes: Int) -> Int {
        ((min(max(minutes, range.lowerBound), range.upperBound) - 1) % 60) + 1
    }

    private func isHandleTouch(_ point: CGPoint, handle: CGPoint, lineWidth: CGFloat) -> Bool {
        let dx = point.x - handle.x
        let dy = point.y - handle.y
        let distance = sqrt(dx * dx + dy * dy)
        return distance <= lineWidth * 1.55
    }

    private func isRecordTouch(_ point: CGPoint, center: CGPoint, radius: CGFloat, lineWidth: CGFloat) -> Bool {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        return distance > lineWidth * 3.2 && distance < radius - lineWidth * 0.4
    }

    private func playDialHaptic(from previousMinute: Int, to nextMinute: Int) {
        guard lastHapticMinute != nextMinute else { return }
        lastHapticMinute = nextMinute

        if completedHour(for: previousMinute) != completedHour(for: nextMinute) {
            let feedback = UIImpactFeedbackGenerator(style: .heavy)
            feedback.prepare()
            feedback.impactOccurred(intensity: 1.0)
        } else {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func completedHour(for minute: Int) -> Int {
        (min(max(minute, range.lowerBound), range.upperBound) - 1) / 60
    }
}

struct IconButton: View {
    var systemName: String
    var tint: Color
    var isActive: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(isActive ? Color.black : tint)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(isActive ? tint.opacity(0.96) : Color.ampPanel, in: Circle())
        .shadow(color: .black.opacity(isActive ? 0.42 : 0.28), radius: 14, y: 8)
        .compositingGroup()
        .animation(.smooth(duration: 0.16), value: isActive)
        .animation(.smooth(duration: 0.16), value: systemName)
    }
}

struct IntervalButtonStyle: ButtonStyle {
    var isSelected: Bool
    var accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.black : Color.ampText.opacity(0.74))
            .background(isSelected ? accent : Color.ampPanel, in: Capsule())
            .shadow(color: .black.opacity(isSelected ? 0.44 : 0.26), radius: 12, y: 7)
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

extension Font {
    enum PaperlogyWeight: String {
        case regular = "Paperlogy-4Regular"
        case medium = "Paperlogy-5Medium"
        case semiBold = "Paperlogy-6SemiBold"
        case bold = "Paperlogy-7Bold"
        case black = "Paperlogy-9Black"
    }

    static func paper(_ weight: PaperlogyWeight, size: CGFloat) -> Font {
        .custom(weight.rawValue, size: size)
    }
}

extension Color {
    static let appBackground = Color(red: 0.955, green: 0.975, blue: 0.985)
    static let lowerBackground = Color(red: 0.985, green: 0.94, blue: 0.92)
    static let glassPanel = Color(red: 1.0, green: 0.985, blue: 0.965).opacity(0.76)
    static let panelBackground = Color(red: 0.965, green: 0.97, blue: 0.965)
    static let surface = Color(red: 0.995, green: 0.99, blue: 0.975)
    static let clockFace = Color(red: 0.925, green: 0.955, blue: 0.965)
    static let softControl = Color(red: 0.955, green: 0.952, blue: 0.935)
    static let yellowTrack = Color(red: 1.0, green: 0.89, blue: 0.54)
    static let warmYellow = Color(red: 1.0, green: 0.78, blue: 0.30)
    static let peach = Color(red: 1.0, green: 0.68, blue: 0.54)
    static let alarmRed = Color(red: 0.96, green: 0.25, blue: 0.36)
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.13)
    static let softText = Color(red: 0.47, green: 0.49, blue: 0.55)
    static let shadowBlue = Color(red: 0.42, green: 0.54, blue: 0.64)
    static let popPink = alarmRed
    static let popBlue = warmYellow
    static let popGreen = warmYellow
    static let toneDing = ampRed
    static let tonePop = ampYellow
    static let toneChime = ampBlue
    static let ampBlack = Color(red: 0.005, green: 0.005, blue: 0.005)
    static let ampDial = Color(red: 0.015, green: 0.015, blue: 0.016)
    static let ampPanel = Color(red: 0.105, green: 0.108, blue: 0.11)
    static let ampStroke = Color(red: 0.21, green: 0.215, blue: 0.22)
    static let ampRed = Color(red: 1.0, green: 0.13, blue: 0.025)
    static let ampYellow = Color(red: 1.0, green: 0.78, blue: 0.13)
    static let ampBlue = Color(red: 0.18, green: 0.48, blue: 1.0)
    static let ampText = Color(red: 0.89, green: 0.89, blue: 0.86)
}

extension AlarmTone {
    var systemName: String {
        switch self {
        case .ding: "bell.fill"
        case .pop: "circle.hexagongrid.fill"
        case .chime: "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .ding: .toneDing
        case .pop: .tonePop
        case .chime: .toneChime
        }
    }
}

#Preview {
    ContentView()
}
