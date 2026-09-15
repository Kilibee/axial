import SwiftUI

struct AxisMeter: View {
    let value: Int
    let label: String
    var body: some View {
        VStack(spacing: 3) {
            GeometryReader {geometry in
                let half = geometry.size.width / 2
                let fraction = min(abs(Double(value)) / 350, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15)).frame(height: 6)
                    Capsule().fill(value < 0 ? Color.orange : Color.accentColor)
                        .frame(width: half * fraction, height: 6)
                        .offset(x: value < 0 ? half * (1 - fraction) : half)
                    Rectangle().fill(Color.primary.opacity(0.65)).frame(width: 1, height: 12).offset(x: half - 0.5)
                }.frame(height: 12)
            }.frame(height: 12)
            HStack {Text("−");Spacer();Text("0");Spacer();Text("+")}
                .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
        }.accessibilityElement(children: .ignore).accessibilityLabel(label)
            .accessibilityValue(value > 0 ? "+\(value)" : "\(value)")
    }
}
