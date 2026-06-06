import ActivityKit
import Foundation

@MainActor
final class LiveActivityController {
    private var activity: Activity<DingLoopActivityAttributes>?

    func start(
        intervalMinutes: Int,
        timeUnit: AlarmTimeUnit,
        tone: AlarmTone,
        remainingSeconds: Int? = nil,
        isPaused: Bool = false
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        Task {
            await end()

            let now = Date()
            let visibleSeconds = max(0, remainingSeconds ?? intervalMinutes * timeUnit.secondsMultiplier)
            let attributes = DingLoopActivityAttributes(
                intervalMinutes: intervalMinutes,
                timeUnitRawValue: timeUnit.rawValue,
                toneName: tone.title,
                accentName: tone.rawValue
            )
            let state = DingLoopActivityAttributes.ContentState(
                startDate: now,
                endDate: now.addingTimeInterval(TimeInterval(visibleSeconds)),
                intervalMinutes: intervalMinutes,
                timeUnitRawValue: timeUnit.rawValue,
                toneName: tone.title,
                accentName: tone.rawValue,
                remainingSeconds: visibleSeconds,
                isRunning: true,
                isPaused: isPaused
            )

            do {
                activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
            } catch {
                print("Failed to start DingLoop Live Activity: \(error)")
            }
        }
    }

    func update(intervalMinutes: Int, timeUnit: AlarmTimeUnit, remainingSeconds: Int, tone: AlarmTone, isPaused: Bool = false) {
        guard let activity else {
            start(
                intervalMinutes: intervalMinutes,
                timeUnit: timeUnit,
                tone: tone,
                remainingSeconds: remainingSeconds,
                isPaused: isPaused
            )
            return
        }

        Task {
            let now = Date()
            let state = DingLoopActivityAttributes.ContentState(
                startDate: now,
                endDate: now.addingTimeInterval(TimeInterval(max(0, remainingSeconds))),
                intervalMinutes: intervalMinutes,
                timeUnitRawValue: timeUnit.rawValue,
                toneName: tone.title,
                accentName: tone.rawValue,
                remainingSeconds: max(0, remainingSeconds),
                isRunning: true,
                isPaused: isPaused
            )
            let content = ActivityContent(state: state, staleDate: nil)
            await activity.update(content)
        }
    }

    func end() async {
        let now = Date()
        let activities = Activity<DingLoopActivityAttributes>.activities
        let activeActivities = activity.map { trackedActivity in
            activities.contains { $0.id == trackedActivity.id } ? activities : activities + [trackedActivity]
        } ?? activities

        self.activity = nil

        for activity in activeActivities {
            let state = DingLoopActivityAttributes.ContentState(
                startDate: now,
                endDate: now,
                intervalMinutes: activity.attributes.intervalMinutes,
                timeUnitRawValue: activity.attributes.timeUnitRawValue,
                toneName: activity.attributes.toneName,
                accentName: activity.attributes.accentName,
                remainingSeconds: 0,
                isRunning: false,
                isPaused: false
            )
            await activity.end(
                ActivityContent(state: state, staleDate: now),
                dismissalPolicy: .immediate
            )
        }
    }
}
