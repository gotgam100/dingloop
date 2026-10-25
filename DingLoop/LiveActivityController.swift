import ActivityKit
import Foundation

/// Shows the running loop on the Lock Screen and in the Dynamic Island:
/// which tones loop and whether it is paused.
@MainActor
final class LiveActivityController {
    /// Called when the person removes the Live Activity (swipes it away on the
    /// Lock Screen) or turns off Live Activities for DingLoop while it is showing.
    var onDismissedByUser: (() -> Void)?

    private var activity: Activity<DingLoopActivityAttributes>?
    // Activities the system ended on its own (e.g. the 8-hour limit); their later
    // dismissal is not the person's choice.
    private var systemEndedActivityIDs: Set<String> = []

    init() {
        Task { [weak self] in
            for await enabled in ActivityAuthorizationInfo().activityEnablementUpdates {
                guard let self else { return }
                if !enabled, self.activity != nil {
                    self.activity = nil
                    self.onDismissedByUser?()
                }
            }
        }
    }

    /// Call only when the loop starts, pauses or resumes — all done with the app on screen.
    func showLoop(sequence: [AlarmTone], isPaused: Bool) {
        let tones = sequence.isEmpty ? [AlarmTone.ding] : sequence
        let state = DingLoopActivityAttributes.ContentState(
            toneSequence: tones.map(\.rawValue),
            toneNames: tones.map(\.title).joined(separator: " · "),
            isPaused: isPaused
        )
        let content = ActivityContent(state: state, staleDate: nil)

        if activity != nil, !ActivityAuthorizationInfo().areActivitiesEnabled {
            activity = nil
            onDismissedByUser?()
            return
        }

        if let activity, activity.activityState == .active {
            Task {
                await activity.update(content)
            }
            return
        }

        end()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            let newActivity = try Activity.request(
                attributes: DingLoopActivityAttributes(),
                content: content,
                pushType: nil
            )
            activity = newActivity
            observe(newActivity)
        } catch {
            print("Failed to start DingLoop Live Activity: \(error)")
        }
    }

    /// Ends the activities showing right now. Ones started after this call are left alone.
    func end() {
        let showing = Activity<DingLoopActivityAttributes>.activities
        activity = nil
        for activity in showing {
            let finalContent = activity.content
            Task {
                await activity.end(finalContent, dismissalPolicy: .immediate)
            }
        }
    }

    private func observe(_ observed: Activity<DingLoopActivityAttributes>) {
        Task { [weak self] in
            for await state in observed.activityStateUpdates {
                guard let self else { return }
                switch state {
                case .ended:
                    // Ended while we still track it: either the person turned Live Activities
                    // off (stop the loop) or the system's time limit.
                    guard self.activity?.id == observed.id else { break }
                    self.activity = nil
                    if ActivityAuthorizationInfo().areActivitiesEnabled {
                        self.systemEndedActivityIDs.insert(observed.id)
                    } else {
                        self.onDismissedByUser?()
                    }
                case .dismissed:
                    // Swiped away by the person while it was showing.
                    let wasTracked = self.activity?.id == observed.id
                    self.systemEndedActivityIDs.remove(observed.id)
                    if wasTracked {
                        self.activity = nil
                        self.onDismissedByUser?()
                    }
                default:
                    break
                }
            }
        }
    }
}
