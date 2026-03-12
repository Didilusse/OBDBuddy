import SwiftUI

struct GaugeCardView: View {
    let title: String
    let value: Double
    let unit: String
    let range: ClosedRange<Double>
    var warningThreshold: Double? = nil
    var formatStyle: GaugeFormatStyle = .integer

    private var progress: Double {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private var isWarning: Bool {
        guard let threshold = warningThreshold else { return false }
        return value >= threshold
    }

    private var accentColor: Color {
        isWarning ? .red : .blue
    }

    private var formattedValue: String {
        switch formatStyle {
        case .integer:
            return String(format: "%.0f", value)
        case .oneDecimal:
            return String(format: "%.1f", value)
        case .twoDecimal:
            return String(format: "%.2f", value)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formattedValue)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(isWarning ? .red : .primary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.15), value: formattedValue)

                Text(unit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress)
                .tint(accentColor)
                .animation(.easeInOut(duration: 0.15), value: progress)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    VStack(spacing: 16) {
        GaugeCardView(title: "RPM", value: 3500, unit: "rpm", range: 0...7000)
        GaugeCardView(title: "Coolant Temp", value: 220, unit: "°F", range: 100...230, warningThreshold: 212)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
