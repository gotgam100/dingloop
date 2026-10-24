import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

struct DingLoopHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DingLoopHomeWidget", provider: DingLoopHomeWidgetProvider()) { entry in
            DingLoopHomeWidgetView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("DingLoop")
        .description("Quickly return to your loop alarm.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct DingLoopHomeWidgetEntry: TimelineEntry {
    let date: Date
    let isRunning: Bool
    let isPaused: Bool
    let intervalMinutes: Int
    let timeUnitRawValue: String
    let remainingSeconds: Int
    let toneName: String
    let endDate: Date?
}

private struct DingLoopHomeWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DingLoopHomeWidgetEntry {
        DingLoopHomeWidgetEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (DingLoopHomeWidgetEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DingLoopHomeWidgetEntry>) -> Void) {
        let entry = readEntry()
        let policy: TimelineReloadPolicy
        if let endDate = entry.endDate, entry.isRunning, !entry.isPaused {
            policy = .after(endDate)
        } else {
            policy = .never
        }
        completion(Timeline(entries: [entry], policy: policy))
    }

    private func readEntry() -> DingLoopHomeWidgetEntry {
        let defaults = UserDefaults(suiteName: widgetAppGroupID) ?? .standard
        let toneName = defaults.string(forKey: widgetToneKey) ?? "ding"
        let intervalMinutes = max(1, defaults.integer(forKey: widgetIntervalKey))
        let timeUnitRawValue = defaults.string(forKey: widgetTimeUnitKey) ?? "minutes"
        let remainingSeconds = defaults.integer(forKey: widgetRemainingKey)
        let endTimestamp = defaults.double(forKey: widgetEndDateKey)
        let endDate = endTimestamp > 0 ? Date(timeIntervalSince1970: endTimestamp) : nil

        return DingLoopHomeWidgetEntry(
            date: Date(),
            isRunning: defaults.bool(forKey: widgetIsRunningKey),
            isPaused: defaults.bool(forKey: widgetIsPausedKey),
            intervalMinutes: intervalMinutes,
            timeUnitRawValue: timeUnitRawValue,
            remainingSeconds: max(0, remainingSeconds),
            toneName: toneName,
            endDate: endDate
        )
    }
}

private struct DingLoopHomeWidgetView: View {
    let entry: DingLoopHomeWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if family == .systemMedium {
                mediumLayout
            } else {
                smallLayout
            }
        }
    }

    private var smallLayout: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                widgetDial(size: size * 0.82, lineWidth: 11)

                if entry.isRunning {
                    widgetCornerDot(size: size * 0.09)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
    }

    private var mediumLayout: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.height * 0.9, proxy.size.width * 0.44)

            ZStack {
                widgetDial(size: size, lineWidth: 13)

                if entry.isRunning {
                    widgetCornerDot(size: size * 0.08)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, 8)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
    }

    private func widgetDial(size: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.07),
                            Color.white.opacity(0.02),
                            Color.black.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.52
                    )
                )
                .frame(width: size, height: size)

            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
                .frame(width: size, height: size)
                .shadow(color: .white.opacity(0.08), radius: 8, x: 0, y: 0)

            Circle()
                .stroke(Color.black.opacity(0.58), lineWidth: max(1, lineWidth * 0.36))
                .frame(width: size - lineWidth * 1.2, height: size - lineWidth * 1.2)

            if entry.isRunning {
                Circle()
                    .trim(from: 0, to: max(0.012, widgetProgress))
                    .stroke(
                        widgetAccentColor(for: entry.toneName),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: size, height: size)

                widgetCountdownText
                    .font(.system(size: size * 0.19, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .multilineTextAlignment(.center)
                    .frame(width: size * 0.72, height: size * 0.24, alignment: .center)

                Circle()
                    .fill(entry.isPaused ? Color.white.opacity(0.9) : Color.black)
                    .frame(width: max(4, size * 0.035), height: max(4, size * 0.035))
                    .offset(y: size * 0.17)
            } else {
                idleAlarmMark(size: size)
            }
        }
    }

    private func widgetCornerDot(size: CGFloat) -> some View {
        Circle()
            .fill(widgetAccentColor(for: entry.toneName))
            .frame(width: max(8, size), height: max(8, size))
            .shadow(color: widgetAccentColor(for: entry.toneName).opacity(0.36), radius: 8, x: 0, y: 0)
    }

    private func idleAlarmMark(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.82), lineWidth: max(2, size * 0.035))
                .frame(width: size * 0.34, height: size * 0.34)

            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: max(5, size * 0.045), height: max(5, size * 0.045))

            Rectangle()
                .fill(Color.white.opacity(0.9))
                .frame(width: max(2, size * 0.018), height: size * 0.13)
                .offset(y: -size * 0.06)

            Rectangle()
                .fill(Color.white.opacity(0.74))
                .frame(width: size * 0.11, height: max(2, size * 0.018))
                .offset(x: size * 0.055)

            Circle()
                .stroke(Color.white.opacity(0.48), lineWidth: max(1, size * 0.015))
                .frame(width: size * 0.42, height: size * 0.42)
        }
    }

    @ViewBuilder
    private var widgetCountdownText: some View {
        if let endDate = entry.endDate, entry.isRunning, !entry.isPaused, endDate > Date() {
            Text(timerInterval: Date()...endDate, countsDown: true)
        } else {
            Text(formatRemainingSeconds(entry.remainingSeconds))
        }
    }

    private var widgetProgress: Double {
        let total = max(1, entry.intervalMinutes * widgetUnitMultiplier(entry.timeUnitRawValue))
        let remaining = max(0, min(total, entry.remainingSeconds))
        return Double(total - remaining) / Double(total)
    }
}

private extension DingLoopHomeWidgetEntry {
    static var placeholder: DingLoopHomeWidgetEntry {
        DingLoopHomeWidgetEntry(
            date: Date(),
            isRunning: false,
            isPaused: false,
            intervalMinutes: 5,
            timeUnitRawValue: "minutes",
            remainingSeconds: 300,
            toneName: "ding",
            endDate: nil
        )
    }
}

private let widgetAppGroupID = "group.com.baekmac.dingloop"
private let widgetIsRunningKey = "DingLoop.widget.isRunning"
private let widgetIsPausedKey = "DingLoop.widget.isPaused"
private let widgetIntervalKey = "DingLoop.widget.intervalMinutes"
private let widgetTimeUnitKey = "DingLoop.widget.timeUnit"
private let widgetRemainingKey = "DingLoop.widget.remainingSeconds"
private let widgetToneKey = "DingLoop.widget.tone"
private let widgetEndDateKey = "DingLoop.widget.endDate"

private func widgetAccentColor(for name: String) -> Color {
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

private func widgetUnitMultiplier(_ rawValue: String) -> Int {
    rawValue == "seconds" ? 1 : 60
}

private func compactUnitTitle(_ rawValue: String) -> String {
    rawValue == "seconds" ? "s" : "m"
}

private func fullUnitTitle(_ rawValue: String) -> String {
    rawValue == "seconds" ? "sec" : "min"
}

struct DingLoopLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DingLoopActivityAttributes.self) { context in
            Group {
                if context.state.isLoop {
                    LoopLockScreenView(context: context)
                } else {
                    LockScreenLiveActivityView(context: context)
                }
            }
            .activityBackgroundTint(.black.opacity(0.92))
            .activitySystemActionForegroundColor(dingActivityAccentColor(for: context.state.accentName))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Group {
                        if context.state.isLoop {
                            ToneSequenceMarks(sequence: context.state.toneSequence, size: 9)
                        } else {
                            IslandActivityMark(accent: dingActivityAccentColor(for: context.state.accentName))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 10)
                }

                DynamicIslandExpandedRegion(.center) {
                    if context.state.isLoop {
                        Text(context.state.toneName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                    } else {
                        countdownText(context)
                            .font(.title3.monospacedDigit().weight(.black))
                            .foregroundStyle(dingActivityAccentColor(for: context.state.accentName))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                            .frame(minWidth: 98)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Group {
                        if context.state.isLoop {
                            LoopStatusIcon(isPaused: context.state.isPaused)
                                .font(.callout.weight(.bold))
                        } else {
                            Text(context.state.toneName)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isLoop {
                        Text(loopStatusTitle(isPaused: context.state.isPaused))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    } else if context.state.isPaused {
                        Capsule()
                            .fill(dingActivityAccentColor(for: context.state.accentName).opacity(0.32))
                            .frame(height: 4)
                            .padding(.horizontal, 24)
                    } else {
                        ProgressView(
                            timerInterval: context.state.startDate...context.state.endDate,
                            countsDown: false
                        )
                        .tint(dingActivityAccentColor(for: context.state.accentName))
                        .padding(.horizontal, 24)
                    }
                }
            } compactLeading: {
                if context.state.isLoop {
                    ToneSequenceMarks(sequence: context.state.toneSequence, size: 7)
                } else {
                    IslandActivityMark(accent: dingActivityAccentColor(for: context.state.accentName))
                }
            } compactTrailing: {
                if context.state.isLoop {
                    LoopStatusIcon(isPaused: context.state.isPaused)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.85))
                } else {
                    countdownText(context)
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(dingActivityAccentColor(for: context.state.accentName))
                        .lineLimit(1)
                        .frame(maxWidth: 44)
                }
            } minimal: {
                if context.state.isLoop {
                    ToneSequenceMarks(sequence: Array(context.state.toneSequence.prefix(1)), size: 8)
                } else {
                    IslandActivityMark(accent: dingActivityAccentColor(for: context.state.accentName))
                }
            }
            .keylineTint(dingActivityAccentColor(for: context.state.accentName))
        }
    }

    @ViewBuilder
    private func countdownText(_ context: ActivityViewContext<DingLoopActivityAttributes>) -> some View {
        if context.state.isPaused {
            Text(formatRemainingSeconds(context.state.remainingSeconds))
                .multilineTextAlignment(.center)
        } else {
            Text(timerInterval: context.state.startDate...context.state.endDate, countsDown: true)
                .multilineTextAlignment(.center)
        }
    }

    private func formatRemainingSeconds(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
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

private struct LoopStatusIcon: View {
    let isPaused: Bool

    var body: some View {
        Image(systemName: isPaused ? "pause.fill" : "repeat")
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
                    .fill(dingActivityAccentColor(for: tone))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(45))
                    .padding(size * 0.2)
            }
        }
    }
}

private struct LoopLockScreenView: View {
    let context: ActivityViewContext<DingLoopActivityAttributes>

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                ToneSequenceMarks(sequence: context.state.toneSequence, size: 11)
                Text(context.state.toneName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 24)

            HStack(spacing: 6) {
                LoopStatusIcon(isPaused: context.state.isPaused)
                    .font(.body.weight(.bold))
                Text(loopStatusTitle(isPaused: context.state.isPaused))
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(.white.opacity(context.state.isPaused ? 0.6 : 0.9))
        }
        .frame(maxWidth: 310)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 12)
        .padding(.horizontal, 18)
    }
}

@available(iOSApplicationExtension 26.0, *)
struct DingLoopAlarmKitWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmKit.AlarmAttributes<DingLoopAlarmMetadata>.self) { context in
            AlarmKitLockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.92))
                .activitySystemActionForegroundColor(dingActivityAccentColor(for: context.attributes.metadata?.accentName ?? "ding"))
        } dynamicIsland: { context in
            let metadata = context.attributes.metadata
            let accent = dingActivityAccentColor(for: metadata?.accentName ?? "ding")
            let isAlert = alarmKitIsAlert(context)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if isAlert {
                        Text("DingLoop")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white.opacity(0.94))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 8)
                    } else {
                        IslandActivityMark(accent: accent)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.trailing, 10)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    if isAlert {
                        Color.clear.frame(height: 1)
                    } else {
                        alarmKitCountdownText(context)
                            .font(.title3.monospacedDigit().weight(.black))
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                            .frame(minWidth: 98)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if isAlert {
                        Text("00:00")
                            .font(.title3.monospacedDigit().weight(.black))
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.trailing, 8)
                    } else {
                        Text("\(metadata?.intervalMinutes ?? 0)\(compactUnitTitle(metadata?.timeUnitRawValue ?? "minutes"))")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 10)
                    }
                }
            } compactLeading: {
                if isAlert {
                    Text("DL")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.white)
                } else {
                    IslandActivityMark(accent: accent)
                }
            } compactTrailing: {
                Text("\(metadata?.intervalMinutes ?? 0)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
            } minimal: {
                IslandActivityMark(accent: accent)
            }
            .keylineTint(accent)
        }
    }
}

@available(iOSApplicationExtension 26.0, *)
private struct AlarmKitLockScreenView: View {
    let context: ActivityViewContext<AlarmKit.AlarmAttributes<DingLoopAlarmMetadata>>

    var body: some View {
        let metadata = context.attributes.metadata
        let accent = dingActivityAccentColor(for: metadata?.accentName ?? "ding")

        if alarmKitIsAlert(context) {
            HStack(spacing: 18) {
                Text("DingLoop")
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)

                Spacer(minLength: 18)

                Text("00:00")
                    .font(.title.monospacedDigit().weight(.black))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            .frame(maxWidth: 310)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 10)
            .padding(.horizontal, 18)
        } else {
            HStack(spacing: 0) {
                Text("\(metadata?.intervalMinutes ?? 0) \(fullUnitTitle(metadata?.timeUnitRawValue ?? "minutes"))")
                    .font(.title2.monospacedDigit().weight(.heavy))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 34)

                alarmKitCountdownText(context)
                    .font(.title.monospacedDigit().weight(.black))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            .frame(maxWidth: 310)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 10)
            .padding(.horizontal, 18)
        }
    }
}

@available(iOSApplicationExtension 26.0, *)
private func alarmKitIsAlert(_ context: ActivityViewContext<AlarmKit.AlarmAttributes<DingLoopAlarmMetadata>>) -> Bool {
    switch context.state.mode {
    case .alert:
        true
    default:
        false
    }
}

@available(iOSApplicationExtension 26.0, *)
@ViewBuilder
private func alarmKitCountdownText(_ context: ActivityViewContext<AlarmKit.AlarmAttributes<DingLoopAlarmMetadata>>) -> some View {
    switch context.state.mode {
    case .countdown(let countdown):
        Text(timerInterval: countdown.startDate...countdown.fireDate, countsDown: true)
            .multilineTextAlignment(.center)
    case .paused(let paused):
        Text(formatRemainingSeconds(Int(max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration))))
            .multilineTextAlignment(.center)
    case .alert:
        Text("00:00")
            .multilineTextAlignment(.center)
    @unknown default:
        Text("--:--")
            .multilineTextAlignment(.center)
    }
}

private func formatRemainingSeconds(_ seconds: Int) -> String {
    let clamped = max(0, seconds)
    return String(format: "%02d:%02d", clamped / 60, clamped % 60)
}

@ViewBuilder
private func lockScreenCountdownText(_ context: ActivityViewContext<DingLoopActivityAttributes>, accent: Color) -> some View {
    if context.state.isPaused {
        Text(formatRemainingSeconds(context.state.remainingSeconds))
            .font(.title.monospacedDigit().weight(.black))
            .foregroundStyle(accent)
            .multilineTextAlignment(.center)
    } else {
        Text(timerInterval: context.state.startDate...context.state.endDate, countsDown: true)
            .font(.title.monospacedDigit().weight(.black))
            .foregroundStyle(accent)
            .multilineTextAlignment(.trailing)
    }
}

private struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<DingLoopActivityAttributes>

    var body: some View {
        let accent = dingActivityAccentColor(for: context.state.accentName)

        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.toneName)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(context.state.intervalMinutes) \(fullUnitTitle(context.state.timeUnitRawValue))")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 34)

            lockScreenCountdownText(context, accent: accent)
        }
        .frame(maxWidth: 310)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 10)
        .padding(.horizontal, 18)
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
    case "voice":
        Color(red: 0.89, green: 0.89, blue: 0.86)
    default:
        Color(red: 1.0, green: 0.17, blue: 0.06)
    }
}
