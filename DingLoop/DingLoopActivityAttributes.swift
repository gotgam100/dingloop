import ActivityKit
import Foundation

/// The running loop, shown on the Lock Screen and in the Dynamic Island.
struct DingLoopActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// The tones in loop order, as `AlarmTone` raw values.
        var toneSequence: [String]
        /// The tone titles for display, e.g. "Ding · Pop · Voice".
        var toneNames: String
        var isPaused: Bool
    }
}
