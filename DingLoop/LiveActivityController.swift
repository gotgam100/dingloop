import ActivityKit
import Foundation

@MainActor
final class LiveActivityController {
    private var activity: Activity<DingLoopActivityAttributes>?

    func start(intervalMinutes: Int, tone: AlarmTone) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        Task {
            await end()

            let now = Date()
            let attributes = DingLoopActivityAttributes(
                intervalMinutes: intervalMinutes,
                toneName: tone.title,
                accentName: tone.rawValue
            )
            let state = DingLoopActivityAttributes.ContentState(
                startDate: now,
                endDate: now.addingTimeInterval(TimeInterval(intervalMinutes * 60)),
                isRunning: true
            )

            do {
                activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: state.endDate),
                    pushType: nil
                )
            } catch {
                print("Failed to start DingLoop Live Activity: \(error)")
            }
        }
    }

    func update(intervalMinutes: Int, remainingSeconds: Int, tone: AlarmTone) {
        guard let activity else { return }

        Task {
            let now = Date()
            let state = DingLoopActivityAttributes.ContentState(
                startDate: now,
                endDate: now.addingTimeInterval(TimeInterval(max(0, remainingSeconds))),
                isRunning: true
            )
            let content = ActivityContent(state: state, staleDate: state.endDate)
            await activity.update(content)
        }
    }

    func end() async {
        guard let activity else { return }
        self.activity = nil
        let now = Date()
        let state = DingLoopActivityAttributes.ContentState(
            startDate: now,
            endDate: now,
            isRunning: false
        )
        await activity.end(
            ActivityContent(state: state, staleDate: now),
            dismissalPolicy: .immediate
        )
    }
}
