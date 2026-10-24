import ActivityKit
import AlarmKit
import Foundation

struct DingLoopActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var startDate: Date
        var endDate: Date
        var intervalMinutes: Int
        var timeUnitRawValue: String
        var toneName: String
        var accentName: String
        var remainingSeconds: Int
        var isRunning: Bool
        var isPaused: Bool
        /// Live loop: the tones in order, as `AlarmTone` raw values.
        var toneSequence: [String]
        /// Live loop: show which tones loop and whether it is paused,
        /// instead of a single countdown.
        var isLoop: Bool
    }

    var intervalMinutes: Int
    var timeUnitRawValue: String
    var toneName: String
    var accentName: String
}

@available(iOS 26.0, *)
struct DingLoopAlarmMetadata: AlarmMetadata {
    var intervalMinutes: Int
    var timeUnitRawValue: String
    var toneName: String
    var accentName: String
}
