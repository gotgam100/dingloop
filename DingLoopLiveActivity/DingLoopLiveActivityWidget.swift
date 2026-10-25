import ActivityKit
import SwiftUI
import WidgetKit

/// The running loop: which tones loop, and whether it is looping or paused.
/// Swiping it away on the Lock Screen stops the loop.
struct DingLoopLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DingLoopActivityAttributes.self) { context in
            LoopLockScreenView(state: context.state)
                .activityBackgroundTint(.black.opacity(0.92))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ToneSequenceMarks(sequence: context.state.toneSequence, size: 9)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 10)
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.toneNames)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    LoopStatusIcon(isPaused: context.state.isPaused)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 10)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Text(loopStatusTitle(isPaused: context.state.isPaused))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            } compactLeading: {
                ToneSequenceMarks(sequence: context.state.toneSequence, size: 7)
            } compactTrailing: {
                LoopStatusIcon(isPaused: context.state.isPaused)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
            } minimal: {
                ToneSequenceMarks(sequence: Array(context.state.toneSequence.prefix(1)), size: 8)
            }
            .keylineTint(toneColor(for: context.state.toneSequence.first ?? "ding"))
        }
    }
}

private struct LoopLockScreenView: View {
    let state: DingLoopActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                ToneSequenceMarks(sequence: state.toneSequence, size: 11)
                Text(state.toneNames)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 24)

            HStack(spacing: 6) {
                LoopStatusIcon(isPaused: state.isPaused)
                    .font(.body.weight(.bold))
                Text(loopStatusTitle(isPaused: state.isPaused))
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(.white.opacity(state.isPaused ? 0.6 : 0.9))
        }
        .frame(maxWidth: 310)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 12)
        .padding(.horizontal, 18)
    }
}

/// The loop's tones in order, as small colored diamonds.
private struct ToneSequenceMarks: View {
    let sequence: [String]
    let size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.55) {
            ForEach(Array(sequence.enumerated()), id: \.offset) { _, tone in
                Rectangle()
                    .fill(toneColor(for: tone))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(45))
                    .padding(size * 0.2)
            }
        }
    }
}

private struct LoopStatusIcon: View {
    let isPaused: Bool

    var body: some View {
        Image(systemName: isPaused ? "pause.fill" : "repeat")
    }
}

/// "Looping" / "Paused" in the phone's language.
private func loopStatusTitle(isPaused: Bool) -> String {
    let isKorean = Locale.preferredLanguages.first?.hasPrefix("ko") == true
    if isPaused {
        return isKorean ? "일시정지" : "Paused"
    }
    return isKorean ? "반복 중" : "Looping"
}

private func toneColor(for name: String) -> Color {
    switch name {
    case "pop":
        Color(red: 1.0, green: 0.82, blue: 0.18)
    case "chime":
        Color(red: 0.22, green: 0.52, blue: 1.0)
    case "voice":
        Color(red: 0.89, green: 0.89, blue: 0.86)
    default:
        Color(red: 1.0, green: 0.17, blue: 0.06)
    }
}
