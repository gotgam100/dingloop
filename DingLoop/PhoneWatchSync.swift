import Foundation
import WatchConnectivity

final class PhoneWatchSync: NSObject, WCSessionDelegate {
    var onWatchMessage: (([String: Any]) -> Void)?

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    func activate() {
        session?.delegate = self
        session?.activate()
    }

    func send(intervalMinutes: Int, remainingSeconds: Int, isRunning: Bool, soundChoice: String) {
        let payload: [String: Any] = [
            "intervalMinutes": intervalMinutes,
            "remainingSeconds": remainingSeconds,
            "isRunning": isRunning,
            "soundChoice": soundChoice
        ]

        do {
            try session?.updateApplicationContext(payload)
        } catch {
            session?.sendMessage(payload, replyHandler: nil)
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
    }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        onWatchMessage?(message)
    }
}
