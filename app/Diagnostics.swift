import Foundation
import SwiftUI
import Charts

struct DiagnosticSample: Identifiable, Codable, Equatable {
    var id: Date {time}
    let time: Date
    let reportsPerSecond: Double
    let clients: Int
    let overflows: Double
    let ignored: Double
}
struct DiagnosticHistory {
    private(set) var samples: [DiagnosticSample] = []
    private var previous: (time: Double, reports: UInt64, overflows: UInt64, ignored: UInt64)?
    mutating func disconnect() {previous = nil; samples.removeAll(keepingCapacity: true)}
    mutating func record(time: Double, wall: Date, reports: UInt64, clients: Int, overflows: UInt64, ignored: UInt64) {
        guard let old = previous else {
            previous = (time, reports, overflows, ignored)
            samples.append(DiagnosticSample(time: wall, reportsPerSecond: 0, clients: clients, overflows: 0, ignored: 0))
            return
        }
        let interval = time - old.time
        guard interval >= 1 else {return}
        if reports < old.reports || overflows < old.overflows || ignored < old.ignored {
            disconnect();record(time: time, wall: wall, reports: reports, clients: clients, overflows: overflows, ignored: ignored);return
        }
        samples.append(DiagnosticSample(time: wall, reportsPerSecond: Double(reports - old.reports) / interval, clients: clients, overflows: Double(overflows - old.overflows) / interval, ignored: Double(ignored - old.ignored) / interval))
        if samples.count > 120 {samples.removeFirst(samples.count - 120)}
        previous = (time, reports, overflows, ignored)
    }
}
struct DiagnosticChart: View {
    let title: String
    let unit: String
    let samples: [DiagnosticSample]
    let value: KeyPath<DiagnosticSample, Double>
    let color: Color
    private var end: Date {samples.last?.time ?? Date()}
    private var latest: Double {samples.last.map {$0[keyPath: value]} ?? 0}
    private var maximum: Double {max(1, (samples.map {$0[keyPath: value]}.max() ?? 0) * 1.1)}
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Text(latest, format: .number.precision(.fractionLength(0...1))).monospacedDigit().font(.headline)
                    if !unit.isEmpty {Text(unit).foregroundStyle(.secondary).font(.caption)}
                }
                plot
            }.padding(6)
        }
    }
    private var plot: some View {
                Chart(samples) {sample in
                    AreaMark(x: .value("Time", sample.time), y: .value(title, sample[keyPath: value]))
                        .foregroundStyle(color.opacity(0.12)).interpolationMethod(.stepEnd)
                    LineMark(x: .value("Time", sample.time), y: .value(title, sample[keyPath: value]))
                        .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.5)).interpolationMethod(.stepEnd)
                }
                .chartXScale(domain: end.addingTimeInterval(-119)...end)
                .chartYScale(domain: 0...maximum)
                .chartXAxis {AxisMarks(values: .automatic(desiredCount: 3)) {tick in
                    AxisGridLine()
                    AxisValueLabel(anchor: .top) {if let date = tick.as(Date.self) {Text(date, format: .dateTime.minute().second())}}
                }}
                .chartYAxis {AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                    AxisGridLine();AxisTick();AxisValueLabel(anchor: .trailing)
                }}
                .frame(height: 95)
    }
}
extension DiagnosticSample {var clientCount: Double {Double(clients)}}
struct DiagnosticsCharts: View, Equatable {
    let samples: [DiagnosticSample]
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            DiagnosticChart(title: "Input reports", unit: "/s", samples: samples, value: \.reportsPerSecond, color: .blue)
            DiagnosticChart(title: "Connected clients", unit: "", samples: samples, value: \.clientCount, color: .teal)
            DiagnosticChart(title: "Queue overflows", unit: "/s", samples: samples, value: \.overflows, color: .orange)
            DiagnosticChart(title: "Ignored reports", unit: "/s", samples: samples, value: \.ignored, color: .red)
        }
    }
}
