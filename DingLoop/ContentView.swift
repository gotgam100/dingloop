import SwiftUI
import UIKit
import UniformTypeIdentifiers

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

    var timeUnitTitle: String {
        switch self {
        case .korean: "시간 단위"
        case .english: "Time Unit"
        }
    }

    var minuteUnitTitle: String {
        switch self {
        case .korean: "분"
        case .english: "Min"
        }
    }

    var secondUnitTitle: String {
        switch self {
        case .korean: "초"
        case .english: "Sec"
        }
    }

    var appInfoTitle: String {
        switch self {
        case .korean: "앱정보"
        case .english: "App Info"
        }
    }

    var userGuideTitle: String {
        switch self {
        case .korean: "사용가이드"
        case .english: "User Guide"
        }
    }

    var termsTitle: String {
        switch self {
        case .korean: "이용약관 및 정책"
        case .english: "Terms & Policy"
        }
    }

    func hintText(_ hint: LoopHint) -> String {
        switch (self, hint) {
        case (.korean, .lowVolume): "미디어 볼륨이 낮아요"
        case (.english, .lowVolume): "Media volume is low"
        case (.korean, .holdToRecord): "Voice를 길게 눌러 녹음하세요"
        case (.english, .holdToRecord): "Hold Voice to record"
        case (.korean, .recording): "녹음 중 · 손을 떼면 저장돼요"
        case (.english, .recording): "Recording · release to save"
        case (.korean, .recordingTooShort): "조금 더 길게 눌러 녹음하세요"
        case (.english, .recordingTooShort): "Hold a little longer to record"
        }
    }
}

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel = AlarmViewModel()
    @State private var isInfoPresented = false
    @State private var isUserGuidePresented = false
    @State private var selectedLanguage: AppLanguage = .korean
    @State private var draggingTone: AlarmTone?
    @State private var dragLocation: CGPoint = .zero
    @State private var loopLaneFrame: CGRect = .zero
    @State private var loopHoverIndex: Int?
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
        .coordinateSpace(name: "DingLoopDragSpace")
        .overlay {
            if let draggingTone {
                ToneChip(tone: draggingTone, isSelected: false) {}
                    .scaleEffect(1.08)
                    .opacity(0.92)
                    .position(dragLocation)
                    .allowsHitTesting(false)
            }
        }
        .onPreferenceChange(LoopLaneFramePreferenceKey.self) { frame in
            loopLaneFrame = frame
        }
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
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                        isInfoPresented.toggle()
                    }
                }

            Spacer()
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 18)

            ClockDial(
                intervalMinutes: $viewModel.intervalMinutes,
                timeUnit: viewModel.timeUnit,
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
                timeUnitRow
                infoRow(selectedLanguage.appInfoTitle, value: appVersion)
                userGuideRow
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
        .overlay {
            if isUserGuidePresented {
                userGuideModal
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isUserGuidePresented)
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

    private var timeUnitRow: some View {
        HStack {
            Text(selectedLanguage.timeUnitTitle)
                .font(.paper(.medium, size: 14))
                .foregroundStyle(Color.ampText.opacity(0.56))

            Spacer()

            HStack(spacing: 6) {
                timeUnitButton(.minutes, title: selectedLanguage.minuteUnitTitle)
                timeUnitButton(.seconds, title: selectedLanguage.secondUnitTitle)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(Color.black.opacity(0.28), in: Capsule())
        .opacity(viewModel.isRunning ? 0.48 : 1)
    }

    private func timeUnitButton(_ unit: AlarmTimeUnit, title: String) -> some View {
        Button {
            viewModel.timeUnit = unit
        } label: {
            Text(title)
                .font(.paper(.bold, size: 12))
                .foregroundStyle(viewModel.timeUnit == unit ? Color.black : Color.ampText.opacity(0.72))
                .frame(width: 54, height: 30)
                .background(viewModel.timeUnit == unit ? accentColor : Color.ampPanel, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRunning)
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

    private var userGuideRow: some View {
        Button {
            isUserGuidePresented = true
        } label: {
            HStack {
                Text(selectedLanguage.userGuideTitle)
                    .font(.paper(.medium, size: 14))
                    .foregroundStyle(Color.ampText.opacity(0.72))

                Spacer()

                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.ampText.opacity(0.44))
            }
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background(Color.black.opacity(0.28), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var userGuideModal: some View {
        ZStack {
            Color.black.opacity(0.58)
                .ignoresSafeArea()
                .onTapGesture {
                    isUserGuidePresented = false
                }

            VStack(spacing: 16) {
                HStack {
                    Text(selectedLanguage.userGuideTitle)
                        .font(.paper(.black, size: 22))
                        .foregroundStyle(accentColor)

                    Spacer()

                    Button {
                        isUserGuidePresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.ampText.opacity(0.74))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(userGuideSections, id: \.title) { section in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(section.title)
                                    .font(.paper(.bold, size: 15))
                                    .foregroundStyle(Color.ampText.opacity(0.92))

                                Text(section.body)
                                    .font(.paper(.regular, size: 13))
                                    .foregroundStyle(Color.ampText.opacity(0.68))
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 2)
                }
            }
            .padding(20)
            .frame(maxWidth: 340)
            .frame(maxHeight: 560)
            .background(Color.ampPanel.opacity(0.98), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 28, y: 18)
            .padding(.horizontal, 24)
        }
    }

    private var userGuideSections: [(title: String, body: String)] {
        switch selectedLanguage {
        case .korean:
            [
                (
                    "DingLoop",
                    "DingLoop는 여러 알람 소리를 정한 순서대로 계속 반복해 주는 앱입니다. 화면이 꺼지거나 다른 앱을 쓰는 중에도, 멈출 때까지 중단 없이 이어집니다."
                ),
                (
                    "1. 시작과 정지",
                    "작고 동그란 핸들을 돌려 간격을 정하고, 가운데 숫자를 꾹 눌러 시작하거나 멈춥니다. 두 번 탭하면 일시정지합니다. 분/초 단위는 설정에서 고를 수 있고, 한 바퀴는 60단위, 최대 360단위입니다."
                ),
                (
                    "2. 루프 등록",
                    "하단의 소리 버튼을 탭하면 미리 들을 수 있고, 오른쪽 루프박스로 끌어다 놓으면 그 순서대로 반복됩니다. 소리마다 간격을 따로 정할 수 있습니다. 루프가 도는 동안에는 바꿀 수 없으니, 멈춘 뒤 수정해 주세요."
                ),
                (
                    "3. 목소리 녹음",
                    "Voice 버튼을 길게 누르는 동안 녹음되고, 손을 떼면 저장됩니다(최대 10초). 저장한 목소리도 다른 소리처럼 루프에 넣을 수 있습니다."
                ),
                (
                    "4. 알아두세요",
                    "소리는 벨소리가 아닌 미디어 볼륨을 따릅니다. 무음 모드에서도 울리지만 미디어 볼륨이 0이면 들리지 않습니다. 이어폰이 연결되어 있으면 이어폰으로 나옵니다. 루프 중에는 배터리를 조금 더 사용합니다. 앱을 완전히 종료하거나, 잠금화면의 DingLoop 표시를 밀어서 지우면 루프도 멈춥니다."
                )
            ]
        case .english:
            [
                (
                    "DingLoop",
                    "DingLoop plays your alarm sounds over and over in the order you set. It keeps going while the screen is off or you use other apps, until you stop it."
                ),
                (
                    "1. Start and Stop",
                    "Turn the small round handle to set the interval, then press and hold the center number to start or stop. Double-tap to pause. Choose minutes or seconds in Settings. One full turn is 60 units, up to 360."
                ),
                (
                    "2. Building a Loop",
                    "Tap a sound button at the bottom to preview it, and drag it into the loop box on the right to repeat it in that order. Each sound keeps its own interval. The loop can't be changed while it runs, so stop it first."
                ),
                (
                    "3. Recording Your Voice",
                    "Press and hold the Voice button to record, and release to save (up to 10 seconds). Your voice can join the loop like any other sound."
                ),
                (
                    "4. Good to Know",
                    "Sounds follow media volume, not ringer volume. They play in Silent mode, but not with media volume at zero. With earphones connected, they play through the earphones. Looping uses a little more battery. Quitting the app, or swiping away DingLoop on the Lock Screen, stops the loop."
                )
            ]
        }
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
                .accessibilityLabel("\(minutes) \(viewModel.timeUnit.shortTitle)")
            }
        }
    }

    private var controlDock: some View {
        HStack(spacing: 10) {
            toneControls
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.22), in: Capsule())

            SequenceLane(
                sequence: viewModel.alarmSequence,
                selectedTone: viewModel.alarmTone,
                hoverIndex: $loopHoverIndex,
                removeAction: viewModel.removeSequenceItem,
                insertAction: viewModel.insertToneToSequence
            )
            .frame(maxWidth: .infinity)
            .allowsHitTesting(!viewModel.isRunning)
        }
        .overlay(alignment: .top) {
            hintBubble
                .offset(y: -122)
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.84), value: viewModel.hint)
        .padding(12)
        .background(Color.ampPanel.opacity(0.96), in: Capsule())
        .shadow(color: .black.opacity(0.38), radius: 22, y: 14)
    }

    /// Ding, Pop, Chime and Voice, always in the same place.
    /// Tap: select and preview. Drag: add to the loop box. Hold Voice: record.
    /// Frozen while a loop runs.
    private var toneControls: some View {
        HStack(spacing: 6) {
            ForEach([AlarmTone.ding, .pop, .chime], id: \.self) { tone in
                ToneChip(tone: tone, isSelected: tone == viewModel.alarmTone) {
                    viewModel.selectAlarmTone(tone)
                }
                .simultaneousGesture(fastToneDragGesture(for: tone))
            }

            VoiceChip(
                hasRecording: viewModel.hasVoiceRecording,
                isSelected: viewModel.alarmTone == .voice,
                isRecording: viewModel.isRecordingVoice,
                onTap: { viewModel.selectAlarmTone(.voice) },
                onPressStart: { viewModel.voicePressBegan() },
                onHoldStart: { viewModel.beginHoldRecording() },
                onHoldEnd: { viewModel.endHoldRecording() }
            )
            .simultaneousGesture(fastToneDragGesture(for: .voice))
        }
        .fixedSize()
        .opacity(viewModel.isRunning ? 0.42 : 1)
        .allowsHitTesting(!viewModel.isRunning)
        .animation(.easeOut(duration: 0.18), value: viewModel.isRunning)
    }

    @ViewBuilder
    private var hintBubble: some View {
        if let hint = viewModel.hint {
            Text(selectedLanguage.hintText(hint))
                .font(.paper(.semiBold, size: 13))
                .foregroundStyle(hint == .recording ? Color.black : Color.ampText)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(hint == .recording ? Color.ampRed : Color.ampPanel, in: Capsule())
                .shadow(color: .black.opacity(0.36), radius: 14, y: 8)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .allowsHitTesting(false)
        }
    }

    private func fastToneDragGesture(for tone: AlarmTone) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("DingLoopDragSpace"))
            .onChanged { value in
                guard !viewModel.isRunning, !viewModel.isRecordingVoice else { return }
                guard tone != .voice || viewModel.hasVoiceRecording else { return }
                draggingTone = tone
                dragLocation = value.location
                updateLoopHover(at: value.location)
            }
            .onEnded { value in
                defer {
                    draggingTone = nil
                    loopHoverIndex = nil
                }

                guard draggingTone != nil, loopLaneFrame.contains(value.location) else { return }
                viewModel.insertToneToSequence(tone, at: loopInsertIndex(for: value.location))
            }
    }

    private func updateLoopHover(at location: CGPoint) {
        guard loopLaneFrame.contains(location) else {
            loopHoverIndex = nil
            return
        }

        loopHoverIndex = loopInsertIndex(for: location)
    }

    private func loopInsertIndex(for location: CGPoint) -> Int {
        guard !viewModel.alarmSequence.isEmpty else { return 0 }

        let relativeX = min(max(location.x - loopLaneFrame.minX, 0), max(loopLaneFrame.width, 1))
        let slotWidth = max(loopLaneFrame.width / 3, 1)
        let slotIndex = min(2, max(0, Int(relativeX / slotWidth)))

        if slotIndex >= viewModel.alarmSequence.count {
            return min(viewModel.alarmSequence.count, 2)
        }

        return slotIndex
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
    var timeUnit: AlarmTimeUnit
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
    @State private var centerPressFeedback = UIImpactFeedbackGenerator(style: .heavy)
    @State private var centerPauseFeedback = UIImpactFeedbackGenerator(style: .medium)
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

            ZStack(alignment: .center) {
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
        .onAppear {
            centerPressFeedback.prepare()
            centerPauseFeedback.prepare()
        }
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
                    Text(timeUnit.shortTitle)
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
                    centerPressFeedback.impactOccurred(intensity: 1.0)
                    centerPressFeedback.prepare()
                    onCenterLongPress()
                }
        )
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    guard isRunning else { return }
                    centerPauseFeedback.impactOccurred(intensity: 0.8)
                    centerPauseFeedback.prepare()
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
        let total = max(1, intervalMinutes * timeUnit.secondsMultiplier)
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

struct ToneChip: View {
    var tone: AlarmTone
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(tone.tint)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: tone.systemName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black.opacity(0.8))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isSelected ? 0.95 : 0.28), lineWidth: isSelected ? 2 : 1)
                )
                .shadow(color: tone.tint.opacity(0.28), radius: 10, y: 6)
        }
        .buttonStyle(.plain)
    }
}

/// The Voice chip. Tap selects and previews the recording; holding it records
/// (release to save, up to 10 seconds).
struct VoiceChip: View {
    var hasRecording: Bool
    var isSelected: Bool
    var isRecording: Bool
    var onTap: () -> Void
    var onPressStart: () -> Void
    var onHoldStart: () -> Void
    var onHoldEnd: () -> Void

    var body: some View {
        Circle()
            .fill(isRecording ? Color.ampRed : AlarmTone.voice.tint.opacity(hasRecording ? 1 : 0.38))
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: hasRecording || isRecording ? AlarmTone.voice.systemName : "mic.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.black.opacity(0.8))
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(isSelected || isRecording ? 0.95 : 0.28), lineWidth: isSelected || isRecording ? 2 : 1)
            )
            .scaleEffect(isRecording ? 1.14 : 1)
            .shadow(color: (isRecording ? Color.ampRed : AlarmTone.voice.tint).opacity(isRecording ? 0.6 : 0.28), radius: isRecording ? 14 : 10, y: 6)
            .animation(.spring(response: 0.24, dampingFraction: 0.7), value: isRecording)
            .contentShape(Circle())
            .onTapGesture(perform: onTap)
            .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 40, perform: onHoldStart) { isPressing in
                if isPressing {
                    onPressStart()
                } else {
                    onHoldEnd()
                }
            }
            .accessibilityLabel("Voice")
            .accessibilityHint("Hold to record")
    }
}

struct SequenceLane: View {
    var sequence: [AlarmTone]
    var selectedTone: AlarmTone
    @Binding var hoverIndex: Int?
    var removeAction: (Int) -> Void
    var insertAction: (AlarmTone, Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let slotSpacing: CGFloat = 6
            let contentWidth = max(0, proxy.size.width - 14)
            let slotWidth = max(24, (contentWidth - slotSpacing * 2) / 3)
            let preview = previewSequence

            ZStack {
                if sequence.isEmpty && hoverIndex == nil {
                    Text("Loop")
                        .font(.paper(.medium, size: 12))
                        .foregroundStyle(Color.ampText.opacity(0.34))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }

                HStack(spacing: slotSpacing) {
                    ForEach(0..<3, id: \.self) { index in
                        if index < preview.count {
                            switch preview[index] {
                            case .tone(let tone, let originalIndex):
                                Button {
                                    removeAction(originalIndex)
                                } label: {
                                    sequenceItem(tone: tone, index: originalIndex, width: slotWidth)
                                }
                                .buttonStyle(.plain)
                            case .placeholder:
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.ampText.opacity(0.14))
                                    .frame(width: slotWidth, height: 34)
                            }
                        } else {
                            Color.clear
                                .frame(width: slotWidth, height: 34)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 7)

            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            .contentShape(Rectangle())
            .onDrop(
                of: [UTType.plainText.identifier],
                delegate: SequenceLaneDropDelegate(
                    sequenceCount: sequence.count,
                    slotWidth: slotWidth,
                    slotSpacing: slotSpacing,
                    hoverIndex: $hoverIndex,
                    insertAction: insertAction
                )
            )
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: hoverIndex)
            .background(
                GeometryReader { frameProxy in
                    Color.clear.preference(
                        key: LoopLaneFramePreferenceKey.self,
                        value: frameProxy.frame(in: .named("DingLoopDragSpace"))
                    )
                }
            )
        }
        .frame(height: 40)
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.28), in: Capsule())
    }

    private var previewSequence: [SequencePreviewItem] {
        var items = sequence.enumerated().map { SequencePreviewItem.tone($0.element, originalIndex: $0.offset) }
        guard let hoverIndex else { return Array(items.prefix(3)) }

        let insertIndex = min(max(hoverIndex, 0), min(sequence.count, 2))
        items.insert(.placeholder, at: insertIndex)
        return Array(items.prefix(3))
    }

    private func sequenceItem(tone: AlarmTone, index: Int, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(tone.tint.opacity(tone == selectedTone ? 0.94 : 0.68))
            .frame(width: width, height: 34)
            .overlay(
                Text("\(index + 1)")
                    .font(.paper(.bold, size: 12))
                    .foregroundStyle(.black.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            )
    }
}

private struct LoopLaneFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let nextValue = nextValue()
        if !nextValue.isEmpty {
            value = nextValue
        }
    }
}

private enum SequencePreviewItem: Equatable {
    case tone(AlarmTone, originalIndex: Int)
    case placeholder
}

private struct SequenceLaneDropDelegate: DropDelegate {
    let sequenceCount: Int
    let slotWidth: CGFloat
    let slotSpacing: CGFloat
    @Binding var hoverIndex: Int?
    let insertAction: (AlarmTone, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText.identifier])
    }

    func dropEntered(info: DropInfo) {
        hoverIndex = targetIndex(for: info.location.x)
    }

    func performDrop(info: DropInfo) -> Bool {
        let index = targetIndex(for: info.location.x)
        hoverIndex = nil
        guard let provider = info.itemProviders(for: [UTType.plainText.identifier]).first else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
            let rawValue: String?
            if let data = item as? Data {
                rawValue = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let text = item as? String {
                rawValue = text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let text = item as? NSString {
                rawValue = (text as String).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                rawValue = nil
            }

            guard let rawValue, let tone = AlarmTone(rawValue: rawValue) else { return }
            DispatchQueue.main.async {
                insertAction(tone, index)
            }
        }
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        hoverIndex = targetIndex(for: info.location.x)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        hoverIndex = nil
    }

    private func targetIndex(for xPosition: CGFloat) -> Int {
        guard sequenceCount > 0 else { return 0 }

        let localX = max(0, xPosition - 7)
        let slotStep = max(1, slotWidth + slotSpacing)
        let slotIndex = min(2, max(0, Int(localX / slotStep)))

        if slotIndex >= sequenceCount {
            return min(sequenceCount, 2)
        }

        return slotIndex
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
        case .voice: "waveform"
        }
    }

    var tint: Color {
        switch self {
        case .ding: .toneDing
        case .pop: .tonePop
        case .chime: .toneChime
        case .voice: .ampText
        }
    }
}

#Preview {
    ContentView()
}
