import ActivityKit
import SwiftUI
import WidgetKit

struct DingLoopLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DingLoopActivityAttributes.self) { context in
            LockScreenLiveActivityView(context: context)
                .activityBackgroundTint(.black.opacity(0.92))
                .activitySystemActionForegroundColor(dingActivityAccentColor(for: context.attributes.accentName))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandActivityMark(accent: dingActivityAccentColor(for: context.attributes.accentName))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 10)
                }

                DynamicIslandExpandedRegion(.center) {
                    countdownText(context)
                        .font(.title3.monospacedDigit().weight(.black))
                        .foregroundStyle(dingActivityAccentColor(for: context.attributes.accentName))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .frame(minWidth: 98)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.attributes.intervalMinutes)m")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 10)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(
                        timerInterval: context.state.startDate...context.state.endDate,
                        countsDown: false
                    )
                    .tint(dingActivityAccentColor(for: context.attributes.accentName))
                    .padding(.horizontal, 24)
                }
            } compactLeading: {
                IslandActivityMark(accent: dingActivityAccentColor(for: context.attributes.accentName))
            } compactTrailing: {
                Text("\(context.attributes.intervalMinutes)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(dingActivityAccentColor(for: context.attributes.accentName))
                    .lineLimit(1)
            } minimal: {
                IslandActivityMark(accent: dingActivityAccentColor(for: context.attributes.accentName))
            }
            .keylineTint(dingActivityAccentColor(for: context.attributes.accentName))
        }
    }

    private func countdownText(_ context: ActivityViewContext<DingLoopActivityAttributes>) -> some View {
        Text(timerInterval: context.state.startDate...context.state.endDate, countsDown: true)
            .multilineTextAlignment(.center)
    }
}

private struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<DingLoopActivityAttributes>

    var body: some View {
        let accent = dingActivityAccentColor(for: context.attributes.accentName)

        HStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.12), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: 0.74)
                        .stroke(accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle()
                        .fill(accent)
                        .frame(width: 14, height: 14)
                }
                .frame(width: 58, height: 58)

                Text("\(context.attributes.intervalMinutes) min")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer(minLength: 34)

            Text(timerInterval: context.state.startDate...context.state.endDate, countsDown: true)
                .font(.title.monospacedDigit().weight(.black))
                .foregroundStyle(accent)
                .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: 310)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 10)
        .padding(.horizontal, 18)
    }
}

private struct LiveActivityMark: View {
    let accent: Color

    var body: some View {
        ZStack {
            Rectangle()
                .fill(accent)
                .frame(width: 13, height: 13)
                .rotationEffect(.degrees(45))
            Circle()
                .stroke(.white.opacity(0.32), lineWidth: 1)
                .frame(width: 22, height: 22)
        }
    }
}

private struct IslandActivityMark: View {
    let accent: Color

    var body: some View {
        ZStack {
            Rectangle()
                .fill(accent)
                .frame(width: 8, height: 8)
                .rotationEffect(.degrees(45))
            Circle()
                .stroke(.white.opacity(0.26), lineWidth: 1)
                .frame(width: 14, height: 14)
        }
        .frame(width: 16, height: 16)
    }
}

private func dingActivityAccentColor(for name: String) -> Color {
    switch name {
    case "pop":
        Color(red: 1.0, green: 0.82, blue: 0.18)
    case "chime":
        Color(red: 0.22, green: 0.52, blue: 1.0)
    default:
        Color(red: 1.0, green: 0.17, blue: 0.06)
    }
}
