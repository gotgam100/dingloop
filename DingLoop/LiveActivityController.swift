import ActivityKit
import Foundation

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

    // MARK: - Loop (live mode)

    /// Shows the running loop: which tones loop and whether it is paused.
    /// Call it only when the loop starts, pauses or resumes — all done with the app on screen.
    func showLoop(sequence: [AlarmTone], isPaused: Bool) {
        let tones = sequence.isEmpty ? [AlarmTone.ding] : sequence
        let now = Date()
        let state = DingLoopActivityAttributes.ContentState(
            startDate: now,
            endDate: now,
            intervalMinutes: 0,
            timeUnitRawValue: AlarmTimeUnit.seconds.rawValue,
            toneName: tones.map(\.title).joined(separator: " · "),
            accentName: tones[0].rawValue,
            remainingSeconds: 0,
            isRunning: !isPaused,
            isPaused: isPaused,
            toneSequence: tones.map(\.rawValue),
            isLoop: true
        )
        let attributes = DingLoopActivityAttributes(
            intervalMinutes: 0,
            timeUnitRawValue: AlarmTimeUnit.seconds.rawValue,
            toneName: state.toneName,
            accentName: state.accentName
        )
        apply(state, attributes: attributes)
    }

    // MARK: - Single countdown (stop-mode fallback when AlarmKit is unavailable)

    func start(
        intervalMinutes: Int,
        timeUnit: AlarmTimeUnit,
        tone: AlarmTone,
        remainingSeconds: Int? = nil,
        isPaused: Bool = false
    ) {
        update(
            intervalMinutes: intervalMinutes,
            timeUnit: timeUnit,
            remainingSeconds: remainingSeconds ?? intervalMinutes * timeUnit.secondsMultiplier,
            tone: tone,
            isPaused: isPaused
        )
    }

    func update(intervalMinutes: Int, timeUnit: AlarmTimeUnit, remainingSeconds: Int, tone: AlarmTone, isPaused: Bool = false) {
        let now = Date()
        let seconds = max(0, remainingSeconds)
        let state = DingLoopActivityAttributes.ContentState(
            startDate: now,
            endDate: now.addingTimeInterval(TimeInterval(seconds)),
            intervalMinutes: intervalMinutes,
            timeUnitRawValue: timeUnit.rawValue,
            toneName: tone.title,
            accentName: tone.rawValue,
            remainingSeconds: seconds,
            isRunning: true,
            isPaused: isPaused,
            toneSequence: [tone.rawValue],
            isLoop: false
        )
        let attributes = DingLoopActivityAttributes(
            intervalMinutes: intervalMinutes,
            timeUnitRawValue: timeUnit.rawValue,
            toneName: tone.title,
            accentName: tone.rawValue
        )
        apply(state, attributes: attributes)
    }

    // MARK: - Ending

    /// Ends the activities showing right now. Ones started after this call are left alone.
    func end() {
        let showing = Activity<DingLoopActivityAttributes>.activities
        activity = nil
        guard !showing.isEmpty else { return }

        for activity in showing {
            let finalContent = activity.content
            Task {
                await activity.end(finalContent, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - Internals

    private func apply(_ state: DingLoopActivityAttributes.ContentState, attributes: DingLoopActivityAttributes) {
        if activity != nil, !ActivityAuthorizationInfo().areActivitiesEnabled {
            activity = nil
            onDismissedByUser?()
            return
        }

        let content = ActivityContent(state: state, staleDate: nil)
        if let activity, activity.activityState == .active {
            Task {
                await activity.update(content)
            }
            return
        }

        end()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }
        do {
            let newActivity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            activity = newActivity
            observe(newActivity)
        } catch {
            print("Failed to start DingLoop Live Activity: \(error)")
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
