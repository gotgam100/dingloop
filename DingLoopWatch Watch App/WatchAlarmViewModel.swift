import Foundation
import SwiftUI
import WatchKit

@MainActor
final class WatchAlarmViewModel: ObservableObject {
    @Published var intervalMinutes = 5 {
        didSet {
            let clampedValue = min(max(intervalMinutes, 1), 360)
            guard intervalMinutes == clampedValue else {
                intervalMinutes = clampedValue
                return
            }

            resetRemainingSeconds()
        }
    }
    @Published var remainingSeconds = 5 * 60
    @Published var isRunning = false

    private var timer: Timer?
    private let connectivity = WatchConnectivityBridge()

    init() {
        connectivity.onPhoneState = { [weak self] payload in
            Task { @MainActor in
                self?.applyPhoneState(payload)
            }
        }
        connectivity.onCommand = { [weak self] payload in
            Task { @MainActor in
                self?.applyCommand(payload)
            }
        }
        connectivity.activate()
    }

    var remainingText: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    var statusText: String {
        isRunning ? "\(intervalMinutes)분마다 알려주는 중" : "아이폰과 함께 사용할 수 있어요"
    }

    func increaseInterval() {
        intervalMinutes = min(360, intervalMinutes + 1)
        sendState()
    }

    func decreaseInterval() {
        intervalMinutes = max(1, intervalMinutes - 1)
        sendState()
    }

    func toggleTimer() {
        isRunning ? stopTimer() : startTimer()
        sendState()
    }

    private func startTimer() {
        resetRemainingSeconds()
        isRunning = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        resetRemainingSeconds()
    }

    private func tick() {
        guard isRunning else { return }
        if remainingSeconds > 1 {
            remainingSeconds -= 1
        } else {
            WKInterfaceDevice.current().play(.notification)
            resetRemainingSeconds()
            sendState()
        }
    }

    private func resetRemainingSeconds() {
        remainingSeconds = intervalMinutes * 60
    }

    private func applyPhoneState(_ payload: [String: Any]) {
        if let interval = payload["intervalMinutes"] as? Int {
            intervalMinutes = interval
        }
        if let remaining = payload["remainingSeconds"] as? Int {
            remainingSeconds = remaining
        }
        if let running = payload["isRunning"] as? Bool {
            isRunning = running
            running ? ensureTimerRunning() : stopTimer()
        }
    }

    private func applyCommand(_ payload: [String: Any]) {
        if let interval = payload["intervalMinutes"] as? Int {
            intervalMinutes = interval
        }
        if let running = payload["isRunning"] as? Bool {
            running ? startTimer() : stopTimer()
        }
    }

    private func ensureTimerRunning() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func sendState() {
        connectivity.sendToPhone([
            "intervalMinutes": intervalMinutes,
            "remainingSeconds": remainingSeconds,
            "isRunning": isRunning
        ])
    }
}
