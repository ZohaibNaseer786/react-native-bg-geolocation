import ActivityKit
import SwiftUI
import WidgetKit

struct LiveTrackingWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BGLiveTrackingAttributes.self) { context in
            LiveTrackingLockScreenView(context: context)
                .activityBackgroundTint(Color(red: 0.055, green: 0.075, blue: 0.09))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "bggeolocation://tracking"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(
                        trackingStatus(context),
                        systemImage: trackingSymbol(context)
                    )
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(trackingColor(context))
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(distanceText(context.state.distance))
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .monospacedDigit()
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 18) {
                        MetricView(
                            icon: "location.fill",
                            value: accuracyText(context.state.accuracy),
                            label: "Accuracy"
                        )
                        MetricView(
                            icon: "speedometer",
                            value: speedText(context.state.speed),
                            label: "Speed"
                        )
                        MetricView(
                            icon: "clock.fill",
                            value: context.state.updatedAt.formatted(date: .omitted, time: .shortened),
                            label: "Updated"
                        )
                    }
                }
            } compactLeading: {
                Image(systemName: trackingSymbol(context))
                    .foregroundStyle(trackingColor(context))
            } compactTrailing: {
                Text(speedText(context.state.speed))
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: trackingSymbol(context))
                    .foregroundStyle(trackingColor(context))
            }
            .widgetURL(URL(string: "bggeolocation://tracking"))
            .keylineTint(trackingColor(context))
        }
    }
}

private struct LiveTrackingLockScreenView: View {
    let context: ActivityViewContext<BGLiveTrackingAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(trackingColor(context).opacity(0.18))
                    Image(systemName: trackingSymbol(context))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(trackingColor(context))
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                    Text(
                        context.isStale
                            ? "Open the app to resume location updates"
                            : context.attributes.subtitle
                    )
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(trackingStatus(context))
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(trackingColor(context))
                    Text(context.state.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            HStack(spacing: 0) {
                MetricView(
                    icon: "speedometer",
                    value: speedText(context.state.speed),
                    label: "Speed"
                )
                Spacer()
                MetricView(
                    icon: "location.fill",
                    value: accuracyText(context.state.accuracy),
                    label: "Accuracy"
                )
                Spacer()
                MetricView(
                    icon: "point.topleft.down.to.point.bottomright.curvepath",
                    value: distanceText(context.state.distance),
                    label: "Distance"
                )
            }
        }
        .padding(16)
    }
}

private struct MetricView: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(Color.cyan)
                Text(value)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

private func trackingStatus(
    _ context: ActivityViewContext<BGLiveTrackingAttributes>
) -> String {
    context.isStale ? "Updates paused" : context.state.status
}

private func trackingSymbol(
    _ context: ActivityViewContext<BGLiveTrackingAttributes>
) -> String {
    if context.isStale {
        return "exclamationmark.triangle.fill"
    }
    return context.state.isMoving
        ? "location.north.circle.fill"
        : "pause.circle.fill"
}

private func trackingColor(
    _ context: ActivityViewContext<BGLiveTrackingAttributes>
) -> Color {
    if context.isStale {
        return .orange
    }
    return context.state.isMoving ? .green : .yellow
}

private func speedText(_ metersPerSecond: Double) -> String {
    "\(Int((metersPerSecond * 3.6).rounded())) km/h"
}

private func accuracyText(_ meters: Double) -> String {
    meters > 0 ? "±\(Int(meters.rounded())) m" : "--"
}

private func distanceText(_ meters: Double) -> String {
    if meters >= 1000 {
        return String(format: "%.1f km", meters / 1000)
    }
    return "\(Int(meters.rounded())) m"
}
