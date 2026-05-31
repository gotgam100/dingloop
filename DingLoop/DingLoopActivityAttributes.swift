import ActivityKit
import Foundation

struct DingLoopActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var startDate: Date
        var endDate: Date
        var isRunning: Bool
    }

    var intervalMinutes: Int
    var toneName: String
    var accentName: String
}
