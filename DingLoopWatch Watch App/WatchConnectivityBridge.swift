import Foundation
import WatchConnectivity

final class WatchConnectivityBridge: NSObject, WCSessionDelegate {
    var onPhoneState: (([String: Any]) -> Void)?
    var onCommand: (([String: Any]) -> Void)?

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    func activate() {
        session?.delegate = self
        session?.activate()
    }

    func sendToPhone(_ payload: [String: Any]) {
        if session?.isReachable == true {
            session?.sendMessage(payload, replyHandler: nil)
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        onPhoneState?(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        onCommand?(message)
    }
}
