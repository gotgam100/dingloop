import AVFoundation
import AlarmKit
import AudioToolbox
import SwiftUI
import UIKit
import UserNotifications

enum AlarmTone: String, CaseIterable, Identifiable {
    case ding
    case pop
    case chime
    case voice

    var id: String { rawValue }

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
}

/// Short messages the screen shows for a moment.
enum LoopHint: Equatable {
    case lowVolume
    case holdToRecord
    case recording
    case recordingTooShort
}

/// Runs the loop: plays each tone itself at its interval, in order, and keeps going
/// while the screen is locked by holding a silent background audio stream.
/// The loop stops when the person stops it, removes its Live Activity, or quits the app.
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
            if !isRunning {
                resetRemainingSeconds()
            }
        }
    }
    @Published var alarmTone: AlarmTone = .ding
    @Published var alarmSequence: [AlarmTone] = []
    @Published var timeUnit: AlarmTimeUnit = .minutes {
        didSet {
            UserDefaults.standard.set(timeUnit.rawValue, forKey: Self.timeUnitKey)
            resetRemainingSeconds()
        }
    }
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var remainingSeconds = 5 * 60
    @Published var currentLoopNumber = 1
    @Published var isRecordingVoice = false
    @Published var hasVoiceRecording = false
    @Published private(set) var hint: LoopHint?
    /// The loop box slot whose tone is counting down now (nil when stopped).
    @Published private(set) var activeLoopIndex: Int?

    private static let selectedToneKey = "DingLoop.selectedTone"
    private static let timeUnitKey = "DingLoop.timeUnit"
    private static let alarmSequenceKey = "DingLoop.sequence"
    private static let intervalKeyPrefix = "DingLoop.interval."
    private static let maxRecordingSeconds: TimeInterval = 10
    private static let minRecordingSeconds: TimeInterval = 0.5

    private let audio = DingLoopAudioWorker()
    private let liveActivityController = LiveActivityController()
    private var timer: Timer?
    private var hintTask: Task<Void, Never>?

    // The running loop. Its tones are fixed when it starts (the dock is frozen meanwhile).
    private var loopTones: [AlarmTone] = []
    private var loopIndex = 0
    private var toneEndDate: Date?
    private var pausedRemainingSeconds = 0
    // What the Live Activity currently shows (nil = none).
    private var shownLoopIsPaused: Bool?

    private var recordingStartedAt: Date?
    private var recordingStopTimer: Timer?

    init() {
        alarmTone = Self.storedAlarmTone()
        timeUnit = Self.storedTimeUnit()
        alarmSequence = Self.storedAlarmSequence()
        hasVoiceRecording = FileManager.default.fileExists(atPath: Self.voiceRecordingURL.path)
        if !hasVoiceRecording {
            alarmSequence.removeAll { $0 == .voice }
            if alarmTone == .voice {
                alarmTone = .ding
            }
        }
        intervalMinutes = Self.storedInterval(for: alarmTone)
        resetRemainingSeconds()

        // A loop never survives a relaunch, so clear anything an earlier run left behind.
        liveActivityController.end()
        liveActivityController.onDismissedByUser = { [weak self] in
            self?.stopLoop()
        }
        Self.cancelLegacySystemAlarms()
    }

    // MARK: - Loop

    func toggleTimer() {
        isRunning ? stopLoop() : startLoop()
    }

    func togglePause() {
        guard isRunning else { return }
        isPaused ? resumeLoop() : pauseLoop()
    }

    private func startLoop() {
        guard !isRunning, !isRecordingVoice else { return }

        // An empty loop box loops the selected tone, and shows it in the box.
        if alarmSequence.isEmpty {
            alarmSequence = [alarmTone]
            storeAlarmSequence()
        }
        loopTones = alarmSequence
        loopIndex = loopTones.firstIndex(of: alarmTone) ?? 0
        currentLoopNumber = 1
        isRunning = true
        isPaused = false
        beginCurrentTone(from: Date())
        startTicking()
        refreshBackgroundRun()
        warnIfVolumeIsLow()
    }

    func stopLoop() {
        guard isRunning else { return }
        timer?.invalidate()
        timer = nil
        toneEndDate = nil
        loopTones = []
        activeLoopIndex = nil
        isRunning = false
        isPaused = false
        currentLoopNumber = 1
        stopCurrentSound()
        resetRemainingSeconds()
        refreshBackgroundRun()
    }

    private func pauseLoop() {
        guard isRunning, !isPaused else { return }
        timer?.invalidate()
        timer = nil
        pausedRemainingSeconds = currentRemainingSeconds(at: Date())
        toneEndDate = nil
        isPaused = true
        remainingSeconds = pausedRemainingSeconds
        refreshBackgroundRun()
    }

    private func resumeLoop() {
        guard isRunning, isPaused else { return }
        toneEndDate = Date().addingTimeInterval(TimeInterval(pausedRemainingSeconds))
        isPaused = false
        startTicking()
        refreshBackgroundRun()
    }

    /// Shows the tone at `loopIndex` on the dial and starts its interval at `start`.
    private func beginCurrentTone(from start: Date) {
        let tone = loopTones[loopIndex]
        activeLoopIndex = loopIndex
        alarmTone = tone
        Self.storeAlarmTone(tone)
        intervalMinutes = Self.storedInterval(for: tone)
        let seconds = durationSeconds(for: intervalMinutes, unit: timeUnit)
        toneEndDate = start.addingTimeInterval(TimeInterval(seconds))
        remainingSeconds = seconds
    }

    private func startTicking() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard isRunning, !isPaused, let endDate = toneEndDate else { return }
        let now = Date()
        guard now >= endDate else {
            remainingSeconds = currentRemainingSeconds(at: now)
            return
        }

        playSound(for: loopTones[loopIndex])
        loopIndex = (loopIndex + 1) % loopTones.count
        if loopIndex == 0 {
            currentLoopNumber += 1
        }
        // Start the next interval where the last one ended so the loop does not drift,
        // unless the app fell far behind.
        beginCurrentTone(from: now.timeIntervalSince(endDate) < 2 ? endDate : now)
    }

    private func currentRemainingSeconds(at date: Date) -> Int {
        guard let toneEndDate else { return remainingSeconds }
        return max(0, Int(ceil(toneEndDate.timeIntervalSince(date))))
    }

    /// Keeps the app alive while the loop sounds, and mirrors the loop in the Live Activity.
    private func refreshBackgroundRun() {
        audio.setKeepAlive(isRunning && !isPaused)

        guard isRunning else {
            if shownLoopIsPaused != nil {
                shownLoopIsPaused = nil
                liveActivityController.end()
            }
            return
        }
        // Only start, pause and resume change it: all done in the app. iOS drops
        // Live Activity updates sent from the background, so none are sent per tone.
        guard shownLoopIsPaused != isPaused else { return }
        shownLoopIsPaused = isPaused
        liveActivityController.showLoop(sequence: loopTones, isPaused: isPaused)
    }

    private func warnIfVolumeIsLow() {
        // The loop plays at media volume, not ringer volume.
        if AVAudioSession.sharedInstance().outputVolume < 0.2 {
            showHint(.lowVolume, for: 3)
        }
    }

    // MARK: - Editing (frozen while a loop runs)

    func selectAlarmTone(_ tone: AlarmTone) {
        guard !isRunning, !isRecordingVoice else { return }
        guard tone != .voice || hasVoiceRecording else {
            showHint(.holdToRecord, for: 2)
            return
        }
        alarmTone = tone
        Self.storeAlarmTone(tone)
        intervalMinutes = Self.storedInterval(for: tone)
        resetRemainingSeconds()
        playSound(for: tone)
    }

    func insertToneToSequence(_ tone: AlarmTone, at index: Int) {
        guard !isRunning else { return }
        guard tone != .voice || hasVoiceRecording else { return }
        let clamped = min(max(index, 0), alarmSequence.count)
        alarmSequence.insert(tone, at: clamped)
        if alarmSequence.count > 3 {
            alarmSequence.removeLast()
        }
        storeAlarmSequence()
    }

    func removeSequenceItem(at index: Int) {
        guard !isRunning, alarmSequence.indices.contains(index) else { return }
        alarmSequence.remove(at: index)
        storeAlarmSequence()
    }

    // MARK: - Voice recording (hold the Voice chip)

    /// Starts recording the moment the Voice chip is touched, so a hold keeps its first word.
    /// A quick tap releases before `beginHoldRecording()` and the take is thrown away.
    func voicePressBegan() {
        guard !isRunning, !isRecordingVoice, recordingStartedAt == nil,
              AVAudioApplication.shared.recordPermission == .granted else { return }

        stopCurrentSound()
        recordingStartedAt = Date()
        recordingStopTimer?.invalidate()
        recordingStopTimer = Timer.scheduledTimer(withTimeInterval: Self.maxRecordingSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.finishRecording()
            }
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        // Record to a draft so a tap or a too-short take never replaces the saved voice.
        try? FileManager.default.removeItem(at: Self.draftRecordingURL)
        audio.startRecording(to: Self.draftRecordingURL, settings: settings, duration: Self.maxRecordingSeconds) { [weak self] started in
            guard let self, !started else { return }
            self.recordingStopTimer?.invalidate()
            self.recordingStopTimer = nil
            self.recordingStartedAt = nil
            self.isRecordingVoice = false
            self.clearHint()
        }
    }

    /// The chip has been held long enough: show that it is recording.
    /// Asks for the microphone first if needed; the person then holds again.
    func beginHoldRecording() {
        guard !isRunning else { return }
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            guard recordingStartedAt != nil else { return }
            isRecordingVoice = true
            showHint(.recording, for: nil)
        case .undetermined:
            AVAudioApplication.requestRecordPermission { _ in }
        default:
            break
        }
    }

    /// The chip was released: keep the take if it was a hold, drop it if it was a tap.
    func endHoldRecording() {
        guard recordingStartedAt != nil else { return }
        if isRecordingVoice {
            finishRecording()
        } else {
            discardRecording()
        }
    }

    /// The Voice chip started moving: it is being dragged into the loop box, not recorded.
    func cancelVoicePress() {
        guard recordingStartedAt != nil else { return }
        isRecordingVoice = false
        clearHint()
        discardRecording()
    }

    private func discardRecording() {
        recordingStopTimer?.invalidate()
        recordingStopTimer = nil
        recordingStartedAt = nil
        audio.stopRecording { _ in
            try? FileManager.default.removeItem(at: Self.draftRecordingURL)
        }
    }

    private func finishRecording() {
        guard let startedAt = recordingStartedAt else { return }
        recordingStopTimer?.invalidate()
        recordingStopTimer = nil
        let length = Date().timeIntervalSince(startedAt)
        recordingStartedAt = nil
        isRecordingVoice = false
        clearHint()

        audio.stopRecording { [weak self] wasRecording in
            guard let self, wasRecording else { return }
            guard length >= Self.minRecordingSeconds else {
                try? FileManager.default.removeItem(at: Self.draftRecordingURL)
                self.showHint(.recordingTooShort, for: 2)
                return
            }
            do {
                if FileManager.default.fileExists(atPath: Self.voiceRecordingURL.path) {
                    try FileManager.default.removeItem(at: Self.voiceRecordingURL)
                }
                try FileManager.default.moveItem(at: Self.draftRecordingURL, to: Self.voiceRecordingURL)
            } catch {
                print("Failed to save DingLoop voice recording: \(error)")
                return
            }
            self.hasVoiceRecording = true
            self.selectAlarmTone(.voice)
        }
    }

    // MARK: - Hints

    private func showHint(_ newHint: LoopHint, for seconds: Double?) {
        hintTask?.cancel()
        hint = newHint
        guard let seconds else { return }
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.hint = nil
        }
    }

    private func clearHint() {
        hintTask?.cancel()
        hint = nil
    }

    // MARK: - Sound

    private func playSound(for tone: AlarmTone) {
        let source: DingLoopAudioWorker.Source
        if tone == .voice, hasVoiceRecording {
            source = .file(Self.voiceRecordingURL)
        } else if let soundURL = Bundle.main.url(forResource: tone.soundResourceName, withExtension: "caf") {
            source = .file(soundURL)
        } else {
            source = .data(Self.makeDefaultDingData(for: tone))
        }
        audio.play(source)
    }

    private func stopCurrentSound() {
        audio.stopPlayback()
    }

    // MARK: - Upgrading from 1.1

    /// Version 1.1 scheduled AlarmKit alarms and repeating notifications for its stop mode.
    /// Nothing in this version cancels them anymore, so clear any left behind.
    private static func cancelLegacySystemAlarms() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["ding-things-repeating-alarm", "dingloop-live-notification"])
        center.removeDeliveredNotifications(withIdentifiers: ["ding-things-repeating-alarm", "dingloop-live-notification"])

        let manager = AlarmManager.shared
        if let alarms = try? manager.alarms {
            for alarm in alarms {
                try? manager.cancel(id: alarm.id)
            }
        }
        for key in ["DingLoop.runMode", "DingLoop.system.alarmID", "DingLoop.system.activeTone",
                    "DingLoop.system.endDate", "DingLoop.system.isRunning"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Storage

    private func resetRemainingSeconds() {
        remainingSeconds = durationSeconds(for: intervalMinutes, unit: timeUnit)
    }

    private func durationSeconds(for interval: Int, unit: AlarmTimeUnit) -> Int {
        max(1, interval * unit.secondsMultiplier)
    }

    private static func storedAlarmTone() -> AlarmTone {
        guard let rawValue = UserDefaults.standard.string(forKey: selectedToneKey),
              let tone = AlarmTone(rawValue: rawValue) else {
            return .ding
        }
        return tone
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
        let storedValue = UserDefaults.standard.integer(forKey: intervalKeyPrefix + tone.rawValue)
        guard storedValue > 0 else { return 5 }
        return min(max(storedValue, 1), 360)
    }

    private static func storeInterval(_ minutes: Int, for tone: AlarmTone) {
        let clampedValue = min(max(minutes, 1), 360)
        UserDefaults.standard.set(clampedValue, forKey: intervalKeyPrefix + tone.rawValue)
    }

    private static var voiceRecordingURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dingloop-voice.m4a")
    }

    private static var draftRecordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dingloop-voice-draft.m4a")
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
}

/// Owns AVAudioSession, playback and recording on one serial background queue,
/// so session changes never block the main thread.
private final class DingLoopAudioWorker: @unchecked Sendable {
    enum Source {
        case file(URL)
        case data(Data)
    }

    private enum SessionMode {
        case playback
        case recording
    }

    private let queue = DispatchQueue(label: "com.baekmac.dingloop.audio", qos: .userInitiated)
    // Touched only on `queue`.
    private var sessionMode: SessionMode?
    private var player: AVAudioPlayer?
    private var recorder: AVAudioRecorder?
    private var keepAlivePlayer: AVAudioPlayer?
    private var wantsKeepAlive = false

    init() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: rawType) == .ended else { return }
            self?.queue.async { [weak self] in
                self?.startKeepAlivePlayerIfNeeded()
            }
        }
    }

    /// Plays silence on a loop while `enabled`, which keeps the app alive in the background.
    func setKeepAlive(_ enabled: Bool) {
        queue.async { [self] in
            guard wantsKeepAlive != enabled else { return }
            wantsKeepAlive = enabled
            if enabled {
                startKeepAlivePlayerIfNeeded()
            } else {
                keepAlivePlayer?.stop()
                keepAlivePlayer = nil
            }
        }
    }

    private func startKeepAlivePlayerIfNeeded() {
        guard wantsKeepAlive else { return }
        do {
            if recorder == nil {
                try activateSession(.playback)
            }
            if keepAlivePlayer == nil {
                let silentPlayer = try AVAudioPlayer(data: Self.silentWAV(seconds: 1))
                silentPlayer.numberOfLoops = -1
                keepAlivePlayer = silentPlayer
            }
            keepAlivePlayer?.play()
        } catch {
            print("DingLoop background audio failed: \(error)")
        }
    }

    private static func silentWAV(seconds: Double) -> Data {
        let sampleRate: UInt32 = 44_100
        let sampleCount = UInt32(Double(sampleRate) * seconds)
        let dataSize = sampleCount * 2
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            data.append(Data(bytes: &little, count: MemoryLayout<T>.size))
        }
        data.append(contentsOf: "RIFF".utf8)
        append(UInt32(36) + dataSize)
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(sampleRate)
        append(sampleRate * 2)
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: "data".utf8)
        append(dataSize)
        data.append(Data(count: Int(dataSize)))
        return data
    }

    func play(_ source: Source) {
        queue.async { [self] in
            stopPlayer()
            do {
                try activateSession(.playback)
                let newPlayer: AVAudioPlayer
                switch source {
                case .file(let url):
                    newPlayer = try AVAudioPlayer(contentsOf: url)
                case .data(let data):
                    newPlayer = try AVAudioPlayer(data: data)
                }
                newPlayer.numberOfLoops = 0
                newPlayer.prepareToPlay()
                newPlayer.play()
                player = newPlayer
            } catch {
                print("Failed to play DingLoop sound: \(error)")
                AudioServicesPlaySystemSound(1005)
            }
        }
    }

    func stopPlayback() {
        queue.async { [self] in
            stopPlayer()
        }
    }

    func startRecording(
        to url: URL,
        settings: [String: Any],
        duration: TimeInterval,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        queue.async { [self] in
            stopPlayer()
            recorder?.stop()
            recorder = nil

            var started = false
            do {
                try activateSession(.recording)
                let newRecorder = try AVAudioRecorder(url: url, settings: settings)
                newRecorder.prepareToRecord()
                started = newRecorder.record(forDuration: duration)
                recorder = started ? newRecorder : nil
            } catch {
                print("Failed to record DingLoop voice alarm: \(error)")
            }
            Task { @MainActor in completion(started) }
        }
    }

    /// Calls back with whether a recording was in progress.
    func stopRecording(completion: @escaping @MainActor (Bool) -> Void) {
        queue.async { [self] in
            let wasRecording = recorder != nil
            recorder?.stop()
            recorder = nil
            startKeepAlivePlayerIfNeeded()
            Task { @MainActor in completion(wasRecording) }
        }
    }

    private func stopPlayer() {
        player?.stop()
        player = nil
    }

    /// Changes the category only when switching between playback and recording.
    private func activateSession(_ mode: SessionMode) throws {
        let session = AVAudioSession.sharedInstance()
        if sessionMode != mode {
            switch mode {
            case .playback:
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            case .recording:
                try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            }
            sessionMode = mode
        }
        // Re-activating is cheap off the main thread and recovers from interruptions.
        try session.setActive(true)
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}
