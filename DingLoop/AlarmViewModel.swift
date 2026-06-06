import AVFoundation
import AudioToolbox
import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

enum AlarmTone: String, CaseIterable, Identifiable {
    case ding
    case pop
    case chime
    case voice

    var id: String { rawValue }

    static var builtInCases: [AlarmTone] {
        [.ding, .pop, .chime]
    }

    var title: String {
        switch self {
        case .ding: "Ding"
        case .pop: "Pop"
        case .chime: "Chime"
        case .voice: "Voice"
        }
    }

    var soundResourceName: String {
        switch self {
        case .ding: "ding-tone"
        case .pop: "pop-tone"
        case .chime: "chime-tone"
        case .voice: "voice-tone"
        }
    }

    var soundFileName: String {
        "\(soundResourceName).caf"
    }

    var alarmKitSoundFileName: String {
        "\(soundResourceName)-alarmkit.caf"
    }
}

enum AlarmRunMode: String, Sendable {
    case stop
    case live
}

enum AlarmTimeUnit: String, Sendable {
    case minutes
    case seconds

    var secondsMultiplier: Int {
        switch self {
        case .minutes: 60
        case .seconds: 1
        }
    }

    var shortTitle: String {
        switch self {
        case .minutes: "min"
        case .seconds: "sec"
        }
    }

    var notificationTitle: String {
        switch self {
        case .minutes: "분"
        case .seconds: "초"
        }
    }
}

private struct AlarmRunState {
    var intervalMinutes: Int
    var remainingSeconds: Int
    var loopNumber: Int
    var timeUnit: AlarmTimeUnit
}

@MainActor
final class AlarmViewModel: ObservableObject {
    @Published var intervalMinutes = 5 {
        didSet {
            let clampedValue = min(max(intervalMinutes, 1), 360)
            guard intervalMinutes == clampedValue else {
                intervalMinutes = clampedValue
                return
            }

            Self.storeInterval(intervalMinutes, for: alarmTone)
            resetRemainingSeconds()
        }
    }
    @Published var alarmTone: AlarmTone = .ding
    @Published var alarmSequence: [AlarmTone] = []
    @Published var runMode: AlarmRunMode = .stop
    @Published var timeUnit: AlarmTimeUnit = .minutes {
        didSet {
            UserDefaults.standard.set(timeUnit.rawValue, forKey: Self.timeUnitKey)
            resetRemainingSeconds()
            sendStateToWatch()
        }
    }
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var remainingSeconds = 5 * 60
    @Published var currentLoopNumber = 1
    @Published var isRecordingVoice = false
    @Published var isVoiceRecordArmed = false
    @Published var hasVoiceRecording = false

    private let notificationIdentifier = "ding-things-repeating-alarm"
    private let liveNotificationIdentifier = "dingloop-live-notification"
    private static let selectedToneKey = "DingLoop.selectedTone"
    private static let runModeKey = "DingLoop.runMode"
    private static let timeUnitKey = "DingLoop.timeUnit"
    private static let alarmSequenceKey = "DingLoop.sequence"
    private static let intervalKeyPrefix = "DingLoop.interval."
    private static let systemActiveToneKey = "DingLoop.system.activeTone"
    private static let systemEndDateKey = "DingLoop.system.endDate"
    private static let systemLoopRunningKey = "DingLoop.system.isRunning"
    private static let widgetAppGroupID = "group.com.baekmac.dingloop"
    private static let widgetKind = "DingLoopHomeWidget"
    private static let widgetIsRunningKey = "DingLoop.widget.isRunning"
    private static let widgetIsPausedKey = "DingLoop.widget.isPaused"
    private static let widgetIntervalKey = "DingLoop.widget.intervalMinutes"
    private static let widgetTimeUnitKey = "DingLoop.widget.timeUnit"
    private static let widgetRemainingKey = "DingLoop.widget.remainingSeconds"
    private static let widgetToneKey = "DingLoop.widget.tone"
    private static let widgetEndDateKey = "DingLoop.widget.endDate"
    private var timer: Timer?
    private var player: AVAudioPlayer?
    private var recorder: AVAudioRecorder?
    private var recordingStopTimer: Timer?
    private var voiceRecordingStartTask: Task<Void, Never>?
    private var runningTone: AlarmTone?
    private var runningIntervalMinutes = 5
    private var runningTimeUnit: AlarmTimeUnit = .minutes
    private var runningRemainingSeconds = 5 * 60
    private var runningIsPaused = false
    private var runningLoopNumber = 1
    private var pausedRuns: [AlarmTone: AlarmRunState] = [:]
    private let liveActivityController = LiveActivityController()
    private var alarmKitController: Any?
    private var systemAlarmGeneration = 0
    private var currentSystemEndDate: Date?

    init() {
        alarmTone = Self.storedAlarmTone()
        runMode = Self.storedRunMode()
        timeUnit = Self.storedTimeUnit()
        alarmSequence = Self.storedAlarmSequence()
        if runMode == .stop {
            alarmSequence.removeAll { $0 == .voice }
            if alarmTone == .voice {
                alarmTone = .ding
            }
        }
        intervalMinutes = Self.storedInterval(for: alarmTone)
        hasVoiceRecording = FileManager.default.fileExists(atPath: Self.voiceRecordingURL.path)
        resetRemainingSeconds()
        Self.installNotificationSounds()
        if #available(iOS 26.0, *) {
            alarmKitController = DingLoopAlarmKitController()
        }
        publishWidgetState(reloadTimeline: false)
    }

    var remainingText: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var statusText: String {
        if isRunning {
            return "\(intervalMinutes)\(timeUnit.notificationTitle)마다 한 번씩 소리가 나요."
        }
        return "간격과 소리를 정한 뒤 시작하세요."
    }

    func toggleTimer() {
        isRunning ? stopTimer() : startTimer()
    }

    func togglePause() {
        if runningTone != alarmTone, pausedRuns[alarmTone] != nil {
            resumePausedTone(alarmTone)
            return
        }

        guard runningTone == alarmTone else { return }

        if runningIsPaused {
            resumeTimer()
        } else {
            pauseTimer()
        }
    }

    func previewDefaultSound() {
        playSound(for: alarmTone)
    }

    func cycleAlarmTone() {
        let tones = AlarmTone.builtInCases
        guard let index = tones.firstIndex(of: alarmTone) else {
            applyAlarmTone(.ding)
            previewDefaultSound()
            return
        }

        applyAlarmTone(tones[(index + 1) % tones.count])
        previewDefaultSound()
    }

    func selectAlarmTone(_ tone: AlarmTone) {
        applyAlarmTone(tone)
    }

    func toggleRunMode() {
        setRunMode(runMode == .stop ? .live : .stop)
    }

    func startVoiceRecording() {
        guard runMode == .live else { return }
        stopCurrentSound()
        stopVoiceRecording(save: false)

        let permissionHandler: @Sendable (Bool) -> Void = { [weak self] allowed in
            Task { @MainActor in
                guard allowed else { return }
                self?.scheduleVoiceRecordingStart()
            }
        }

        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: permissionHandler)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(permissionHandler)
        }
    }

    func toggleVoiceRecording() {
        isRecordingVoice ? stopVoiceRecording(save: true) : startVoiceRecording()
    }

    func handleVoiceButtonTap() {
        if isRecordingVoice {
            stopVoiceRecording(save: true)
        } else if isVoiceRecordArmed {
            startVoiceRecording()
        } else {
            armVoiceRecording()
        }
    }

    func armVoiceRecording() {
        guard runMode == .live else { return }
        stopCurrentSound()
        voiceRecordingStartTask?.cancel()
        isVoiceRecordArmed = true
        if hasVoiceRecording {
            applyAlarmTone(.voice)
        }
    }

    func previewSelectedSound() {
        playSound(for: alarmTone)
    }

    func appendToneToSequence(_ tone: AlarmTone) {
        guard alarmSequence.count < 3 else { return }
        alarmSequence.append(tone)
        storeAlarmSequence()
    }

    func insertToneToSequence(_ tone: AlarmTone, at index: Int) {
        guard tone != .voice || runMode == .live else { return }
        guard tone != .voice || hasVoiceRecording else { return }
        let clamped = min(max(index, 0), alarmSequence.count)
        alarmSequence.insert(tone, at: clamped)
        if alarmSequence.count > 3 {
            alarmSequence.removeLast()
        }
        storeAlarmSequence()
    }

    func ensureToneInSequence(_ tone: AlarmTone) {
        guard tone != .voice || runMode == .live else { return }
        guard tone != .voice || hasVoiceRecording else { return }
        guard !alarmSequence.contains(tone), alarmSequence.count < 3 else { return }
        alarmSequence.append(tone)
        storeAlarmSequence()
    }

    func removeSequenceItem(at index: Int) {
        guard alarmSequence.indices.contains(index) else { return }
        alarmSequence.remove(at: index)
        storeAlarmSequence()
    }

    func moveSequenceItem(from source: IndexSet, to destination: Int) {
        alarmSequence.move(fromOffsets: source, toOffset: destination)
        storeAlarmSequence()
    }

    private func applyAlarmTone(_ tone: AlarmTone) {
        guard tone != .voice || runMode == .live else { return }
        guard tone != .voice || hasVoiceRecording else { return }
        alarmTone = tone
        Self.storeAlarmTone(tone)
        intervalMinutes = Self.storedInterval(for: tone)
        refreshVisibleRunState()
        sendStateToWatch()
    }

    private func setRunMode(_ mode: AlarmRunMode) {
        guard runMode != mode else { return }
        stopRunningAlarm(resetVisibleState: true)
        stopVoiceRecording(save: true)
        isVoiceRecordArmed = false
        runMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.runModeKey)

        if mode == .stop {
            alarmSequence.removeAll { $0 == .voice }
            if alarmTone == .voice {
                applyAlarmTone(.ding)
            }
            storeAlarmSequence()
        }
    }

    private func startTimer() {
        ensureToneInSequence(alarmTone)
        pauseActiveToneForSwitch()
        runningTone = alarmTone
        if let savedRun = pausedRuns.removeValue(forKey: alarmTone) {
            runningIntervalMinutes = savedRun.intervalMinutes
            runningTimeUnit = savedRun.timeUnit
            runningRemainingSeconds = savedRun.remainingSeconds
            runningLoopNumber = savedRun.loopNumber
            intervalMinutes = savedRun.intervalMinutes
            timeUnit = savedRun.timeUnit
        } else {
            runningIntervalMinutes = intervalMinutes
            runningTimeUnit = timeUnit
            runningRemainingSeconds = durationSeconds(for: intervalMinutes, unit: timeUnit)
            runningLoopNumber = 1
        }
        runningIsPaused = false
        remainingSeconds = runningRemainingSeconds
        isRunning = true
        isPaused = false
        currentLoopNumber = runningLoopNumber
        sendStateToWatch()
        scheduleCurrentSystemAlarmIfNeeded()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        if runningTone == alarmTone {
            stopRunningAlarm(resetVisibleState: true)
        } else {
            pausedRuns[alarmTone] = nil
            isRunning = false
            isPaused = false
            currentLoopNumber = 1
            resetRemainingSeconds()
        }
        sendStateToWatch()
    }

    private func stopRunningAlarm(resetVisibleState: Bool) {
        timer?.invalidate()
        timer = nil
        stopCurrentSound()
        cancelLiveNotification()
        if let tone = runningTone {
            pausedRuns[tone] = nil
        }
        runningTone = nil
        runningIsPaused = false
        runningLoopNumber = 1
        runningRemainingSeconds = durationSeconds(for: runningIntervalMinutes, unit: runningTimeUnit)
        isRunning = false
        isPaused = false
        currentLoopNumber = 1
        if resetVisibleState {
            resetRemainingSeconds()
        }
        cancelSystemAlarm()
    }

    private func pauseActiveToneForSwitch() {
        guard let activeTone = runningTone else { return }

        timer?.invalidate()
        timer = nil
        stopCurrentSound()
        pausedRuns[activeTone] = AlarmRunState(
            intervalMinutes: runningIntervalMinutes,
            remainingSeconds: runningRemainingSeconds,
            loopNumber: runningLoopNumber,
            timeUnit: runningTimeUnit
        )
        runningTone = nil
        runningIsPaused = true
        cancelSystemAlarm()
        cancelLiveNotification()
    }

    private func resumePausedTone(_ tone: AlarmTone) {
        guard let savedRun = pausedRuns.removeValue(forKey: tone) else { return }

        pauseActiveToneForSwitch()
        runningTone = tone
        runningIntervalMinutes = savedRun.intervalMinutes
        runningTimeUnit = savedRun.timeUnit
        runningRemainingSeconds = savedRun.remainingSeconds
        runningLoopNumber = savedRun.loopNumber
        runningIsPaused = false
        intervalMinutes = savedRun.intervalMinutes
        timeUnit = savedRun.timeUnit
        remainingSeconds = savedRun.remainingSeconds
        isRunning = true
        isPaused = false
        currentLoopNumber = savedRun.loopNumber
        scheduleCurrentSystemAlarmIfNeeded()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        sendStateToWatch()
    }

    private func pauseTimer() {
        guard runningTone == alarmTone, !runningIsPaused else { return }
        let pausedRemainingSeconds = remainingSeconds
        timer?.invalidate()
        timer = nil
        runningRemainingSeconds = pausedRemainingSeconds
        runningIsPaused = true
        isRunning = true
        isPaused = true
        pausedRuns[alarmTone] = AlarmRunState(
            intervalMinutes: runningIntervalMinutes,
            remainingSeconds: runningRemainingSeconds,
            loopNumber: runningLoopNumber,
            timeUnit: runningTimeUnit
        )
        pauseSystemAlarm(
            intervalMinutes: runningIntervalMinutes,
            remainingSeconds: runningRemainingSeconds,
            tone: alarmTone
        )
        sendStateToWatch()
    }

    private func resumeTimer() {
        guard runningTone == alarmTone, runningIsPaused else { return }
        pausedRuns[alarmTone] = nil
        runningIsPaused = false
        isRunning = true
        isPaused = false
        resumeSystemAlarm(
            intervalMinutes: runningIntervalMinutes,
            remainingSeconds: runningRemainingSeconds,
            tone: alarmTone
        )
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        sendStateToWatch()
    }

    private func tick() {
        syncSystemAlarmState()
        guard let activeTone = runningTone else { return }

        if runningRemainingSeconds > 1 {
            runningRemainingSeconds -= 1
            if activeTone == alarmTone {
                remainingSeconds = runningRemainingSeconds
                isRunning = true
            }
            if runningRemainingSeconds % 5 == 0 {
                sendStateToWatch()
            }
        } else {
            runningRemainingSeconds = 0
            if activeTone == alarmTone {
                remainingSeconds = 0
                isRunning = true
            }
            sendStateToWatch()
            if runMode == .live {
                completeLiveLoop(for: activeTone)
            }
        }
    }

    private func resetRemainingSeconds() {
        remainingSeconds = durationSeconds(for: intervalMinutes, unit: timeUnit)
    }

    private func refreshVisibleRunState() {
        if runningTone == alarmTone {
            isRunning = true
            isPaused = runningIsPaused
            remainingSeconds = runningRemainingSeconds
            currentLoopNumber = runningLoopNumber
        } else if let savedRun = pausedRuns[alarmTone] {
            isRunning = true
            isPaused = true
            remainingSeconds = savedRun.remainingSeconds
            currentLoopNumber = savedRun.loopNumber
        } else {
            isRunning = false
            isPaused = false
            currentLoopNumber = 1
            resetRemainingSeconds()
        }
    }

    private func playSound(for tone: AlarmTone) {
        do {
            try configurePlaybackSession()
            stopCurrentSound()
            if tone == .voice, hasVoiceRecording {
                player = try AVAudioPlayer(contentsOf: Self.voiceRecordingURL)
            } else if let soundURL = Bundle.main.url(forResource: tone.soundResourceName, withExtension: "caf") {
                player = try AVAudioPlayer(contentsOf: soundURL)
            } else {
                player = try AVAudioPlayer(data: Self.makeDefaultDingData(for: tone))
            }
            player?.numberOfLoops = 0
            player?.prepareToPlay()
            player?.play()
        } catch {
            AudioServicesPlaySystemSound(1005)
        }
    }

    private func stopCurrentSound() {
        player?.stop()
        player?.currentTime = 0
        player = nil
    }

    private func configurePlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    private func beginVoiceRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            recorder = try AVAudioRecorder(url: Self.voiceRecordingURL, settings: settings)
            recorder?.prepareToRecord()
            recorder?.record(forDuration: 10)
            isRecordingVoice = true
            isVoiceRecordArmed = true
            recordingStopTimer?.invalidate()
            recordingStopTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.stopVoiceRecording(save: true)
                }
            }
        } catch {
            isRecordingVoice = false
            print("Failed to record DingLoop voice alarm: \(error)")
        }
    }

    private func scheduleVoiceRecordingStart() {
        voiceRecordingStartTask?.cancel()
        voiceRecordingStartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.isVoiceRecordArmed, !self.isRecordingVoice else { return }
                self.beginVoiceRecording()
            }
        }
    }

    private func stopVoiceRecording(save: Bool) {
        voiceRecordingStartTask?.cancel()
        voiceRecordingStartTask = nil
        recordingStopTimer?.invalidate()
        recordingStopTimer = nil
        recorder?.stop()
        recorder = nil
        isRecordingVoice = false
        hasVoiceRecording = FileManager.default.fileExists(atPath: Self.voiceRecordingURL.path)
        if save {
            isVoiceRecordArmed = false
        }
        if save, hasVoiceRecording {
            applyAlarmTone(.voice)
        }
    }

    private func sendStateToWatch() {
        publishWidgetState()
    }

    private func publishWidgetState(reloadTimeline: Bool = true) {
        let activeTone = runningTone ?? alarmTone
        let visibleInterval = runningTone == nil ? intervalMinutes : runningIntervalMinutes
        let visibleUnit = runningTone == nil ? timeUnit : runningTimeUnit
        let visibleRemaining = max(0, remainingSeconds)
        let endDate = isRunning && !isPaused
            ? Date().addingTimeInterval(TimeInterval(visibleRemaining))
            : nil

        let defaults = UserDefaults(suiteName: Self.widgetAppGroupID) ?? .standard
        defaults.set(isRunning, forKey: Self.widgetIsRunningKey)
        defaults.set(isPaused, forKey: Self.widgetIsPausedKey)
        defaults.set(visibleInterval, forKey: Self.widgetIntervalKey)
        defaults.set(visibleUnit.rawValue, forKey: Self.widgetTimeUnitKey)
        defaults.set(visibleRemaining, forKey: Self.widgetRemainingKey)
        defaults.set(activeTone.rawValue, forKey: Self.widgetToneKey)
        defaults.set(endDate?.timeIntervalSince1970 ?? 0, forKey: Self.widgetEndDateKey)

        if reloadTimeline {
            WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
        }
    }

    private func scheduleCurrentSystemAlarmIfNeeded() {
        guard let tone = runningTone,
              !runningIsPaused,
              runningRemainingSeconds > 0 else { return }

        if runMode == .stop {
            scheduleSystemAlarm(
                tone: tone,
                durationSeconds: runningRemainingSeconds,
                intervalMinutes: runningIntervalMinutes,
                timeUnit: runningTimeUnit
            )
        } else {
            cancelSystemAlarm()
            scheduleLiveNotification(tone: tone, durationSeconds: runningRemainingSeconds, intervalMinutes: runningIntervalMinutes, timeUnit: runningTimeUnit)
        }
    }

    private func scheduleSystemAlarm(tone: AlarmTone, durationSeconds: Int? = nil, intervalMinutes: Int, timeUnit: AlarmTimeUnit) {
        systemAlarmGeneration += 1
        let generation = systemAlarmGeneration
        let alarmDurationSeconds = max(1, durationSeconds ?? self.durationSeconds(for: intervalMinutes, unit: timeUnit))
        currentSystemEndDate = Date().addingTimeInterval(TimeInterval(alarmDurationSeconds))

        if #available(iOS 26.0, *),
           let alarmKitController = alarmKitController as? DingLoopAlarmKitController {
            Task {
                let scheduledWithAlarmKit = await alarmKitController.schedule(
                    tone: tone,
                    durationSeconds: alarmDurationSeconds,
                    intervalMinutes: intervalMinutes,
                    timeUnit: timeUnit
                )
                guard generation == systemAlarmGeneration else { return }
                if scheduledWithAlarmKit {
                    cancelRepeatingNotification()
                } else {
                    scheduleFallbackAlarm(tone: tone, intervalMinutes: intervalMinutes, timeUnit: timeUnit)
                }
            }
        } else {
            scheduleFallbackAlarm(tone: tone, intervalMinutes: intervalMinutes, timeUnit: timeUnit)
        }
    }

    private func pauseSystemAlarm(intervalMinutes: Int, remainingSeconds: Int, tone: AlarmTone) {
        if runMode == .live {
            cancelLiveNotification()
            liveActivityController.update(
                intervalMinutes: intervalMinutes,
                timeUnit: runningTimeUnit,
                remainingSeconds: remainingSeconds,
                tone: tone,
                isPaused: true
            )
            return
        }

        persistVisibleSystemEndDate(remainingSeconds: remainingSeconds)
        if #available(iOS 26.0, *),
           let alarmKitController = alarmKitController as? DingLoopAlarmKitController,
           alarmKitController.isScheduled {
            alarmKitController.cancelScheduledAlarmKeepingRunState()
        }
        cancelRepeatingNotification()
        liveActivityController.update(
            intervalMinutes: intervalMinutes,
            timeUnit: runningTimeUnit,
            remainingSeconds: remainingSeconds,
            tone: tone,
            isPaused: true
        )
    }

    private func resumeSystemAlarm(intervalMinutes: Int, remainingSeconds: Int, tone: AlarmTone) {
        if runMode == .live {
            scheduleLiveNotification(tone: tone, durationSeconds: remainingSeconds, intervalMinutes: intervalMinutes, timeUnit: runningTimeUnit)
            liveActivityController.update(
                intervalMinutes: intervalMinutes,
                timeUnit: runningTimeUnit,
                remainingSeconds: remainingSeconds,
                tone: tone,
                isPaused: false
            )
            return
        }

        persistVisibleSystemEndDate(remainingSeconds: remainingSeconds)
        Task {
            await liveActivityController.end()
        }
        if #available(iOS 26.0, *),
           let alarmKitController = alarmKitController as? DingLoopAlarmKitController,
           alarmKitController.isScheduled {
            alarmKitController.resume()
        } else {
            scheduleSystemAlarm(
                tone: tone,
                durationSeconds: remainingSeconds,
                intervalMinutes: intervalMinutes,
                timeUnit: runningTimeUnit
            )
        }
    }

    private func updateSystemAlarm(intervalMinutes: Int, remainingSeconds: Int, tone: AlarmTone) {
        if #available(iOS 26.0, *),
           let alarmKitController = alarmKitController as? DingLoopAlarmKitController,
           alarmKitController.isScheduled {
            return
        }

        liveActivityController.update(
            intervalMinutes: intervalMinutes,
            timeUnit: runningTimeUnit,
            remainingSeconds: remainingSeconds,
            tone: tone
        )
    }

    private func cancelSystemAlarm() {
        systemAlarmGeneration += 1
        currentSystemEndDate = nil
        if #available(iOS 26.0, *),
           let alarmKitController = alarmKitController as? DingLoopAlarmKitController {
            alarmKitController.cancel()
        }
        cancelRepeatingNotification()
        Task {
            await liveActivityController.end()
        }
    }

    private func persistVisibleSystemEndDate(remainingSeconds: Int) {
        let endDate = Date().addingTimeInterval(TimeInterval(max(0, remainingSeconds)))
        currentSystemEndDate = endDate
        UserDefaults.standard.set(endDate.timeIntervalSince1970, forKey: Self.systemEndDateKey)
    }

    private func syncSystemAlarmState() {
        guard runMode == .stop, isRunning, !runningIsPaused else { return }

        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.systemLoopRunningKey) else {
            if runningRemainingSeconds <= 0 {
                stopRunningAlarm(resetVisibleState: true)
            }
            return
        }

        guard let rawValue = defaults.string(forKey: Self.systemActiveToneKey),
              let tone = AlarmTone(rawValue: rawValue) else {
            return
        }

        let timestamp = defaults.double(forKey: Self.systemEndDateKey)
        guard timestamp > 0 else { return }

        let endDate = Date(timeIntervalSince1970: timestamp)
        let seconds = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        let didStartNewAlarm = didPersistedAlarmAdvance(to: tone, endDate: endDate, remainingSeconds: seconds)

        if didStartNewAlarm {
            applyPersistedAlarm(tone: tone, remainingSeconds: seconds, endDate: endDate)
        } else if tone == runningTone {
            currentSystemEndDate = endDate
            runningRemainingSeconds = seconds
            if tone == alarmTone {
                remainingSeconds = seconds
            }
        }
    }

    private func didPersistedAlarmAdvance(to tone: AlarmTone, endDate: Date, remainingSeconds seconds: Int) -> Bool {
        guard let runningTone else { return true }

        if tone != runningTone {
            return true
        }

        guard let currentSystemEndDate else { return false }
        return runningRemainingSeconds <= 0
            && seconds > 0
            && endDate.timeIntervalSince(currentSystemEndDate) > 1
    }

    private func applyPersistedAlarm(tone: AlarmTone, remainingSeconds seconds: Int, endDate: Date) {
        let repeatedSameTone = tone == runningTone
        runningTone = tone
        runningIntervalMinutes = Self.storedInterval(for: tone)
        runningTimeUnit = timeUnit
        runningRemainingSeconds = max(0, seconds)
        runningLoopNumber = repeatedSameTone ? runningLoopNumber + 1 : 1
        runningIsPaused = false
        currentSystemEndDate = endDate

        alarmTone = tone
        intervalMinutes = runningIntervalMinutes
        remainingSeconds = runningRemainingSeconds
        currentLoopNumber = runningLoopNumber
        isRunning = true
        isPaused = false
        sendStateToWatch()
    }

    private func scheduleFallbackAlarm(tone: AlarmTone, intervalMinutes: Int, timeUnit: AlarmTimeUnit) {
        scheduleRepeatingNotification(tone: tone, intervalMinutes: intervalMinutes, timeUnit: timeUnit)
        liveActivityController.start(intervalMinutes: intervalMinutes, timeUnit: timeUnit, tone: tone)
    }

    private func completeLiveLoop(for tone: AlarmTone) {
        timer?.invalidate()
        timer = nil
        playSound(for: tone)

        guard let nextTone = nextTone(after: tone) else {
            finishLiveRunKeepingCurrentSound()
            return
        }

        runningTone = nextTone
        runningIntervalMinutes = Self.storedInterval(for: nextTone)
        runningTimeUnit = timeUnit
        runningRemainingSeconds = durationSeconds(for: runningIntervalMinutes, unit: runningTimeUnit)
        runningLoopNumber = nextTone == tone ? runningLoopNumber + 1 : 1
        runningIsPaused = false

        alarmTone = nextTone
        intervalMinutes = runningIntervalMinutes
        remainingSeconds = runningRemainingSeconds
        currentLoopNumber = runningLoopNumber
        isRunning = true
        isPaused = false
        Self.storeAlarmTone(nextTone)
        sendStateToWatch()
        scheduleCurrentSystemAlarmIfNeeded()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func nextTone(after tone: AlarmTone) -> AlarmTone? {
        guard !alarmSequence.isEmpty else { return nil }
        guard let index = alarmSequence.firstIndex(of: tone) else {
            return alarmSequence.first
        }
        return alarmSequence[(index + 1) % alarmSequence.count]
    }

    private func finishLiveRunKeepingCurrentSound() {
        timer?.invalidate()
        timer = nil
        runningTone = nil
        runningIsPaused = false
        runningLoopNumber = 1
        runningRemainingSeconds = durationSeconds(for: runningIntervalMinutes, unit: runningTimeUnit)
        isRunning = false
        isPaused = false
        currentLoopNumber = 1
        resetRemainingSeconds()
        cancelSystemAlarm()
        cancelLiveNotification()
        sendStateToWatch()
    }

    private func scheduleLiveNotification(tone: AlarmTone, durationSeconds: Int, intervalMinutes: Int, timeUnit: AlarmTimeUnit) {
        let notificationBody = "\(intervalMinutes)\(timeUnit.notificationTitle) 알림"
        Task {
            let center = UNUserNotificationCenter.current()
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else { return }

                center.removePendingNotificationRequests(withIdentifiers: [liveNotificationIdentifier])

                let content = UNMutableNotificationContent()
                content.title = "DingLoop"
                content.body = notificationBody
                content.sound = nil

                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: TimeInterval(max(1, durationSeconds)),
                    repeats: false
                )
                let request = UNNotificationRequest(
                    identifier: liveNotificationIdentifier,
                    content: content,
                    trigger: trigger
                )
                try await center.add(request)
            } catch {
                print("Failed to schedule DingLoop live notification: \(error)")
            }
        }
    }

    private func cancelLiveNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [liveNotificationIdentifier])
    }

    private func scheduleRepeatingNotification(tone: AlarmTone, intervalMinutes: Int, timeUnit: AlarmTimeUnit) {
        let notificationBody = "\(intervalMinutes)\(timeUnit.notificationTitle) 알람 · \(tone.title)"
        let triggerSeconds = max(60, durationSeconds(for: intervalMinutes, unit: timeUnit))
        Task {
            let center = UNUserNotificationCenter.current()
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else { return }

                Self.installNotificationSounds()
                center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])

                let content = UNMutableNotificationContent()
                content.title = "DingLoop"
                content.body = notificationBody
                if Self.notificationSoundURL(for: tone) != nil {
                    content.sound = UNNotificationSound(named: UNNotificationSoundName(tone.soundFileName))
                } else {
                    content.sound = .default
                }

                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: TimeInterval(triggerSeconds),
                    repeats: true
                )
                let request = UNNotificationRequest(
                    identifier: notificationIdentifier,
                    content: content,
                    trigger: trigger
                )
                try await center.add(request)
            } catch {
                print("Failed to schedule DingLoop notification: \(error)")
            }
        }
    }

    private func cancelRepeatingNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
    }

    private static func installNotificationSounds() {
        guard let soundsDirectory = notificationSoundsDirectory() else { return }

        do {
            try FileManager.default.createDirectory(
                at: soundsDirectory,
                withIntermediateDirectories: true
            )

            for tone in AlarmTone.allCases {
                guard tone != .voice else { continue }
                guard let sourceURL = Bundle.main.url(forResource: tone.soundResourceName, withExtension: "caf") else {
                    continue
                }

                let targetURL = soundsDirectory.appendingPathComponent(tone.soundFileName)
                if FileManager.default.fileExists(atPath: targetURL.path) {
                    try FileManager.default.removeItem(at: targetURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: targetURL)
            }
        } catch {
            print("Failed to install DingLoop notification sounds: \(error)")
        }
    }

    private static func notificationSoundURL(for tone: AlarmTone) -> URL? {
        if let soundsDirectory = notificationSoundsDirectory() {
            let targetURL = soundsDirectory.appendingPathComponent(tone.soundFileName)
            if FileManager.default.fileExists(atPath: targetURL.path) {
                return targetURL
            }
        }

        return Bundle.main.url(forResource: tone.soundResourceName, withExtension: "caf")
    }

    private static func notificationSoundsDirectory() -> URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    private static func storedAlarmTone() -> AlarmTone {
        guard let rawValue = UserDefaults.standard.string(forKey: selectedToneKey),
              let tone = AlarmTone(rawValue: rawValue) else {
            return .ding
        }
        return tone
    }

    private static func storedRunMode() -> AlarmRunMode {
        guard let rawValue = UserDefaults.standard.string(forKey: runModeKey),
              let mode = AlarmRunMode(rawValue: rawValue) else {
            return .stop
        }
        return mode
    }

    private static func storedTimeUnit() -> AlarmTimeUnit {
        guard let rawValue = UserDefaults.standard.string(forKey: timeUnitKey),
              let unit = AlarmTimeUnit(rawValue: rawValue) else {
            return .minutes
        }
        return unit
    }

    private static func storedAlarmSequence() -> [AlarmTone] {
        guard let raws = UserDefaults.standard.array(forKey: alarmSequenceKey) as? [String] else {
            return []
        }
        return raws.compactMap(AlarmTone.init(rawValue:))
    }

    private func storeAlarmSequence() {
        UserDefaults.standard.set(alarmSequence.map(\.rawValue), forKey: Self.alarmSequenceKey)
    }

    private static func storeAlarmTone(_ tone: AlarmTone) {
        UserDefaults.standard.set(tone.rawValue, forKey: selectedToneKey)
    }

    private static func storedInterval(for tone: AlarmTone) -> Int {
        let key = intervalKeyPrefix + tone.rawValue
        let storedValue = UserDefaults.standard.integer(forKey: key)
        guard storedValue > 0 else { return 5 }
        return min(max(storedValue, 1), 360)
    }

    private static func storeInterval(_ minutes: Int, for tone: AlarmTone) {
        let clampedValue = min(max(minutes, 1), 360)
        UserDefaults.standard.set(clampedValue, forKey: intervalKeyPrefix + tone.rawValue)
    }

    private func durationSeconds(for interval: Int, unit: AlarmTimeUnit) -> Int {
        max(1, interval * unit.secondsMultiplier)
    }

    private static func makeDefaultDingData(for tone: AlarmTone) -> Data {
        let sampleRate = 44_100
        let duration: Double
        let frequencies: [(Double, Double)]
        let decay: Double
        let gain: Double

        switch tone {
        case .ding:
            duration = 0.52
            frequencies = [(880, 1.0), (1320, 0.45)]
            decay = 5.4
            gain = 0.64
        case .pop:
            duration = 0.34
            frequencies = [(520, 1.0), (1040, 0.7)]
            decay = 8.2
            gain = 0.72
        case .chime:
            duration = 0.72
            frequencies = [(660, 0.8), (990, 0.55), (1480, 0.28)]
            decay = 4.2
            gain = 0.58
        case .voice:
            duration = 0.44
            frequencies = [(740, 0.9), (1110, 0.42)]
            decay = 5.8
            gain = 0.55
        }

        let frameCount = Int(Double(sampleRate) * duration)
        var samples = [Int16]()
        samples.reserveCapacity(frameCount)

        for frame in 0..<frameCount {
            let time = Double(frame) / Double(sampleRate)
            let envelope = exp(-decay * time)
            let mixedTone = frequencies.reduce(0.0) { partialResult, frequency in
                partialResult + sin(2 * .pi * frequency.0 * time) * frequency.1
            }
            let value = max(-1, min(1, mixedTone * envelope * gain))
            samples.append(Int16(value * Double(Int16.max)))
        }

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(UInt32(36 + samples.count * 2).littleEndianData)
        data.append(contentsOf: "WAVEfmt ".utf8)
        data.append(UInt32(16).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt32(sampleRate).littleEndianData)
        data.append(UInt32(sampleRate * 2).littleEndianData)
        data.append(UInt16(2).littleEndianData)
        data.append(UInt16(16).littleEndianData)
        data.append(contentsOf: "data".utf8)
        data.append(UInt32(samples.count * 2).littleEndianData)

        for sample in samples {
            data.append(sample.littleEndianData)
        }

        return data
    }

    private static var voiceRecordingURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dingloop-voice.m4a")
    }
}

@available(iOS 26.0, *)
@MainActor
private final class DingLoopAlarmKitController {
    private static let notificationIdentifier = "ding-things-repeating-alarm"
    private static let alarmIDKey = "DingLoop.system.alarmID"
    private static let activeToneKey = "DingLoop.system.activeTone"
    private static let endDateKey = "DingLoop.system.endDate"
    private static let systemLoopRunningKey = "DingLoop.system.isRunning"
    private static let alarmSequenceKey = "DingLoop.sequence"
    private static let intervalKeyPrefix = "DingLoop.interval."
    private static let timeUnitKey = "DingLoop.timeUnit"

    private let manager = AlarmManager.shared
    private var alarmID: Alarm.ID?

    var isScheduled: Bool {
        alarmID != nil
    }

    func schedule(tone: AlarmTone, durationSeconds: Int, intervalMinutes: Int, timeUnit: AlarmTimeUnit) async -> Bool {
        cancel()

        if let id = await Self.scheduleAlarm(
            tone: tone,
            durationSeconds: durationSeconds,
            intervalMinutes: intervalMinutes,
            timeUnit: timeUnit
        ) {
            alarmID = id
            return true
        }

        alarmID = nil
        return false
    }

    func pause() {
        guard let alarmID = currentAlarmID else { return }

        do {
            try manager.pause(id: alarmID)
        } catch {
            print("Failed to pause DingLoop AlarmKit alarm: \(error)")
        }
    }

    func resume() {
        guard let alarmID = currentAlarmID else { return }

        do {
            try manager.resume(id: alarmID)
        } catch {
            print("Failed to resume DingLoop AlarmKit alarm: \(error)")
        }
    }

    func cancel() {
        for id in currentAlarmIDs {
            do {
                try manager.cancel(id: id)
            } catch {
                print("Failed to cancel DingLoop AlarmKit alarm: \(error)")
            }
        }
        self.alarmID = nil
        Self.clearPersistedRun()
        Self.cancelNotificationBackup()
    }

    func cancelScheduledAlarmKeepingRunState() {
        for id in currentAlarmIDs {
            do {
                try manager.cancel(id: id)
            } catch {
                print("Failed to cancel paused DingLoop AlarmKit alarm: \(error)")
            }
        }
        self.alarmID = nil
        UserDefaults.standard.removeObject(forKey: Self.alarmIDKey)
        Self.cancelNotificationBackup()
    }

    static func scheduleNextAlarmFromStoredState() async {
        guard UserDefaults.standard.bool(forKey: systemLoopRunningKey),
              let nextTone = nextToneFromStoredState() else {
            clearPersistedRun()
            cancelNotificationBackup()
            return
        }

        let intervalMinutes = storedInterval(for: nextTone)
        let timeUnit = storedTimeUnit()
        guard await scheduleAlarm(
            tone: nextTone,
            durationSeconds: max(1, intervalMinutes * timeUnit.secondsMultiplier),
            intervalMinutes: intervalMinutes,
            timeUnit: timeUnit
        ) != nil else {
            scheduleNotificationBackup(tone: nextTone, intervalMinutes: intervalMinutes, timeUnit: timeUnit)
            return
        }
    }

    @discardableResult
    private static func scheduleAlarm(tone: AlarmTone, durationSeconds: Int, intervalMinutes: Int, timeUnit: AlarmTimeUnit) async -> Alarm.ID? {
        do {
            let manager = AlarmManager.shared
            let authorizationState: AlarmManager.AuthorizationState
            if manager.authorizationState == .notDetermined {
                authorizationState = try await manager.requestAuthorization()
            } else {
                authorizationState = manager.authorizationState
            }

            guard authorizationState == .authorized else {
                return nil
            }

            let id = UUID()
            let attributes = AlarmKit.AlarmAttributes(
                presentation: presentation(),
                metadata: DingLoopAlarmMetadata(
                    intervalMinutes: intervalMinutes,
                    timeUnitRawValue: timeUnit.rawValue,
                    toneName: tone.title,
                    accentName: tone.rawValue
                ),
                tintColor: tintColor(for: tone)
            )
            let configuration = AlarmManager.AlarmConfiguration.timer(
                duration: TimeInterval(max(1, durationSeconds)),
                attributes: attributes,
                stopIntent: DingLoopAlarmStopIntent(),
                sound: .named(tone.alarmKitSoundFileName)
            )

            _ = try await manager.schedule(id: id, configuration: configuration)
            persistRun(
                id: id,
                tone: tone,
                endDate: Date().addingTimeInterval(TimeInterval(max(1, durationSeconds)))
            )
            cancelNotificationBackup()
            return id
        } catch {
            print("Failed to schedule DingLoop AlarmKit alarm: \(error)")
            return nil
        }
    }

    private static func nextToneFromStoredState() -> AlarmTone? {
        let sequence = storedAlarmSequence()
        guard !sequence.isEmpty else { return nil }

        guard let activeRawValue = UserDefaults.standard.string(forKey: activeToneKey),
              let activeTone = AlarmTone(rawValue: activeRawValue),
              let index = sequence.firstIndex(of: activeTone) else {
            return sequence.first
        }

        return sequence[(index + 1) % sequence.count]
    }

    private var currentAlarmID: Alarm.ID? {
        alarmID ?? Self.persistedAlarmID()
    }

    private var currentAlarmIDs: [Alarm.ID] {
        var ids: [Alarm.ID] = []
        if let alarmID {
            ids.append(alarmID)
        }
        if let persistedID = Self.persistedAlarmID(), !ids.contains(persistedID) {
            ids.append(persistedID)
        }
        return ids
    }

    private static func persistRun(id: Alarm.ID, tone: AlarmTone, endDate: Date) {
        UserDefaults.standard.set(id.uuidString, forKey: alarmIDKey)
        UserDefaults.standard.set(tone.rawValue, forKey: activeToneKey)
        UserDefaults.standard.set(endDate.timeIntervalSince1970, forKey: endDateKey)
        UserDefaults.standard.set(true, forKey: systemLoopRunningKey)
    }

    private static func clearPersistedRun() {
        UserDefaults.standard.removeObject(forKey: alarmIDKey)
        UserDefaults.standard.removeObject(forKey: activeToneKey)
        UserDefaults.standard.removeObject(forKey: endDateKey)
        UserDefaults.standard.set(false, forKey: systemLoopRunningKey)
    }

    private static func persistedAlarmID() -> Alarm.ID? {
        guard let rawValue = UserDefaults.standard.string(forKey: alarmIDKey) else {
            return nil
        }
        return UUID(uuidString: rawValue)
    }

    private static func storedAlarmSequence() -> [AlarmTone] {
        guard let raws = UserDefaults.standard.array(forKey: alarmSequenceKey) as? [String] else {
            return []
        }
        return raws.compactMap(AlarmTone.init(rawValue:))
    }

    private static func storedInterval(for tone: AlarmTone) -> Int {
        let storedValue = UserDefaults.standard.integer(forKey: intervalKeyPrefix + tone.rawValue)
        guard storedValue > 0 else { return 5 }
        return min(max(storedValue, 1), 360)
    }

    private static func storedTimeUnit() -> AlarmTimeUnit {
        guard let rawValue = UserDefaults.standard.string(forKey: timeUnitKey),
              let unit = AlarmTimeUnit(rawValue: rawValue) else {
            return .minutes
        }
        return unit
    }

    private static func scheduleNotificationBackup(tone: AlarmTone, intervalMinutes: Int, timeUnit: AlarmTimeUnit) {
        Task {
            let center = UNUserNotificationCenter.current()
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else { return }

                cancelNotificationBackup()

                let content = UNMutableNotificationContent()
                content.title = "DingLoop"
                content.body = "\(intervalMinutes)\(timeUnit.notificationTitle) 알람 · \(tone.title)"
                content.sound = UNNotificationSound(named: UNNotificationSoundName(tone.soundFileName))

                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: TimeInterval(max(60, intervalMinutes * timeUnit.secondsMultiplier)),
                    repeats: true
                )
                let request = UNNotificationRequest(
                    identifier: notificationIdentifier,
                    content: content,
                    trigger: trigger
                )
                try await center.add(request)
            } catch {
                print("Failed to schedule DingLoop notification backup: \(error)")
            }
        }
    }

    private static func cancelNotificationBackup() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
    }

    private static func presentation() -> AlarmPresentation {
        let stopButton = AlarmButton(
            text: "Stop",
            textColor: .white,
            systemImageName: "stop.fill"
        )
        let pauseButton = AlarmButton(
            text: "Pause",
            textColor: .white,
            systemImageName: "pause.fill"
        )
        let resumeButton = AlarmButton(
            text: "Resume",
            textColor: .white,
            systemImageName: "play.fill"
        )

        return AlarmPresentation(
            alert: AlarmPresentation.Alert(
                title: "",
                stopButton: stopButton
            ),
            countdown: AlarmPresentation.Countdown(
                title: "DingLoop",
                pauseButton: pauseButton
            ),
            paused: AlarmPresentation.Paused(
                title: "Paused",
                resumeButton: resumeButton
            )
        )
    }

    private static func tintColor(for tone: AlarmTone) -> Color {
        switch tone {
        case .ding:
            Color(red: 1.0, green: 0.17, blue: 0.06)
        case .pop:
            Color(red: 1.0, green: 0.82, blue: 0.18)
        case .chime:
            Color(red: 0.22, green: 0.52, blue: 1.0)
        case .voice:
            Color(red: 0.89, green: 0.89, blue: 0.86)
        }
    }
}

@available(iOS 26.0, *)
struct DingLoopAlarmStopIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop DingLoop Alarm"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await DingLoopAlarmKitController.scheduleNextAlarmFromStoredState()
        return .result()
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}
