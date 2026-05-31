import AVFoundation
import AudioToolbox
import SwiftUI
import UserNotifications

enum AlarmTone: String, CaseIterable, Identifiable {
    case ding
    case pop
    case chime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ding: "Ding"
        case .pop: "Pop"
        case .chime: "Chime"
        }
    }

    var soundFileName: String {
        switch self {
        case .ding: "ding-tone.caf"
        case .pop: "pop-tone.caf"
        case .chime: "chime-tone.caf"
        }
    }
}

private struct AlarmRunState {
    var intervalMinutes: Int
    var remainingSeconds: Int
    var loopNumber: Int
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
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var remainingSeconds = 5 * 60
    @Published var currentLoopNumber = 1

    private let notificationIdentifier = "ding-things-repeating-alarm"
    private static let selectedToneKey = "DingLoop.selectedTone"
    private static let intervalKeyPrefix = "DingLoop.interval."
    private var timer: Timer?
    private var player: AVAudioPlayer?
    private var runningTone: AlarmTone?
    private var runningIntervalMinutes = 5
    private var runningRemainingSeconds = 5 * 60
    private var runningIsPaused = false
    private var runningLoopNumber = 1
    private var pausedRuns: [AlarmTone: AlarmRunState] = [:]
    private let watchSync = PhoneWatchSync()
    private let liveActivityController = LiveActivityController()

    init() {
        alarmTone = Self.storedAlarmTone()
        intervalMinutes = Self.storedInterval(for: alarmTone)
        resetRemainingSeconds()
        watchSync.onWatchMessage = { [weak self] payload in
            Task { @MainActor in
                self?.applyWatchMessage(payload)
            }
        }
        watchSync.activate()
    }

    var remainingText: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var statusText: String {
        if isRunning {
            return "\(intervalMinutes)분마다 한 번씩 소리가 나요."
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
        playDefaultSound(for: alarmTone)
    }

    func cycleAlarmTone() {
        let tones = AlarmTone.allCases
        guard let index = tones.firstIndex(of: alarmTone) else {
            applyAlarmTone(.ding)
            previewDefaultSound()
            return
        }

        applyAlarmTone(tones[(index + 1) % tones.count])
        previewDefaultSound()
    }

    private func applyAlarmTone(_ tone: AlarmTone) {
        alarmTone = tone
        Self.storeAlarmTone(tone)
        intervalMinutes = Self.storedInterval(for: tone)
        refreshVisibleRunState()
        sendStateToWatch()
    }

    private func startTimer() {
        pauseActiveToneForSwitch()
        runningTone = alarmTone
        if let savedRun = pausedRuns.removeValue(forKey: alarmTone) {
            runningIntervalMinutes = savedRun.intervalMinutes
            runningRemainingSeconds = savedRun.remainingSeconds
            runningLoopNumber = savedRun.loopNumber
            intervalMinutes = savedRun.intervalMinutes
        } else {
            runningIntervalMinutes = intervalMinutes
            runningRemainingSeconds = intervalMinutes * 60
            runningLoopNumber = 1
        }
        runningIsPaused = false
        remainingSeconds = runningRemainingSeconds
        isRunning = true
        isPaused = false
        currentLoopNumber = runningLoopNumber
        sendStateToWatch()
        scheduleRepeatingNotification(tone: alarmTone, intervalMinutes: intervalMinutes)
        liveActivityController.start(intervalMinutes: intervalMinutes, tone: alarmTone)
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
        if let tone = runningTone {
            pausedRuns[tone] = nil
        }
        runningTone = nil
        runningIsPaused = false
        runningLoopNumber = 1
        runningRemainingSeconds = runningIntervalMinutes * 60
        isRunning = false
        isPaused = false
        currentLoopNumber = 1
        if resetVisibleState {
            resetRemainingSeconds()
        }
        cancelRepeatingNotification()
        Task {
            await liveActivityController.end()
        }
    }

    private func pauseActiveToneForSwitch() {
        guard let activeTone = runningTone else { return }

        timer?.invalidate()
        timer = nil
        stopCurrentSound()
        pausedRuns[activeTone] = AlarmRunState(
            intervalMinutes: runningIntervalMinutes,
            remainingSeconds: runningRemainingSeconds,
            loopNumber: runningLoopNumber
        )
        runningTone = nil
        runningIsPaused = true
        cancelRepeatingNotification()
        Task {
            await liveActivityController.end()
        }
    }

    private func resumePausedTone(_ tone: AlarmTone) {
        guard let savedRun = pausedRuns.removeValue(forKey: tone) else { return }

        pauseActiveToneForSwitch()
        runningTone = tone
        runningIntervalMinutes = savedRun.intervalMinutes
        runningRemainingSeconds = savedRun.remainingSeconds
        runningLoopNumber = savedRun.loopNumber
        runningIsPaused = false
        intervalMinutes = savedRun.intervalMinutes
        remainingSeconds = savedRun.remainingSeconds
        isRunning = true
        isPaused = false
        currentLoopNumber = savedRun.loopNumber
        scheduleRepeatingNotification(tone: tone, intervalMinutes: savedRun.intervalMinutes)
        liveActivityController.start(intervalMinutes: savedRun.intervalMinutes, tone: tone)
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
        timer?.invalidate()
        timer = nil
        runningIsPaused = true
        isRunning = true
        isPaused = true
        pausedRuns[alarmTone] = AlarmRunState(
            intervalMinutes: runningIntervalMinutes,
            remainingSeconds: runningRemainingSeconds,
            loopNumber: runningLoopNumber
        )
        cancelRepeatingNotification()
        liveActivityController.update(
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
        scheduleRepeatingNotification(tone: alarmTone, intervalMinutes: runningIntervalMinutes)
        liveActivityController.update(
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
            playAlarmSound(for: activeTone)
            runningLoopNumber += 1
            runningRemainingSeconds = runningIntervalMinutes * 60
            if activeTone == alarmTone {
                remainingSeconds = runningRemainingSeconds
                isRunning = true
                currentLoopNumber = runningLoopNumber
            }
            liveActivityController.update(
                intervalMinutes: runningIntervalMinutes,
                remainingSeconds: runningRemainingSeconds,
                tone: activeTone
            )
            sendStateToWatch()
        }
    }

    private func resetRemainingSeconds() {
        remainingSeconds = intervalMinutes * 60
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

    private func playAlarmSound(for tone: AlarmTone) {
        playDefaultSound(for: tone)
    }

    private func playDefaultSound(for tone: AlarmTone) {
        do {
            try configurePlaybackSession()
            stopCurrentSound()
            if let soundURL = Bundle.main.url(forResource: tone.soundFileName, withExtension: nil) {
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

    private func sendStateToWatch() {
        watchSync.send(
            intervalMinutes: intervalMinutes,
            remainingSeconds: remainingSeconds,
            isRunning: isRunning,
            soundChoice: alarmTone.rawValue
        )
    }

    private func applyWatchMessage(_ payload: [String: Any]) {
        if let interval = payload["intervalMinutes"] as? Int {
            intervalMinutes = interval
        }

        if let running = payload["isRunning"] as? Bool {
            if running != isRunning {
                running ? startTimer() : stopTimer()
            }
        }
    }

    private func scheduleRepeatingNotification(tone: AlarmTone, intervalMinutes: Int) {
        Task {
            let center = UNUserNotificationCenter.current()
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else { return }

                center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])

                let content = UNMutableNotificationContent()
                content.title = "DingLoop"
                content.body = "\(intervalMinutes)분 알람 · \(tone.title)"
                content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: tone.soundFileName))

                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: TimeInterval(intervalMinutes * 60),
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

    private static func storedAlarmTone() -> AlarmTone {
        guard let rawValue = UserDefaults.standard.string(forKey: selectedToneKey),
              let tone = AlarmTone(rawValue: rawValue) else {
            return .ding
        }
        return tone
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

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}
