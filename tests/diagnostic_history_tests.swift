import Foundation
@main struct DiagnosticsChecks {
    static func main() {
        var history = DiagnosticHistory()
        func sample(_ time: Double, _ reports: UInt64, _ clients: Int = 2, _ overflows: UInt64 = 0, _ ignored: UInt64 = 0) {
            history.record(time: time, wall: Date(timeIntervalSince1970: time), reports: reports, clients: clients, overflows: overflows, ignored: ignored)
        }
        sample(0, 100);sample(0.5, 150)
        precondition(history.samples.count == 1)
        sample(2, 300, 3, 4, 6)
        let first = history.samples.last!
        precondition(first.reportsPerSecond == 100 && first.clients == 3 && first.overflows == 2 && first.ignored == 3)
        sample(3, 0, 1)
        precondition(history.samples.count == 1 && history.samples[0].reportsPerSecond == 0, "Restart produced a counter spike")
        for time in 4...250 {sample(Double(time), UInt64(time * 100))}
        precondition(history.samples.count == 120 && history.samples.last!.reportsPerSecond == 100)
        history.disconnect();precondition(history.samples.isEmpty)
        sample(251, 999999)
        precondition(history.samples.last!.reportsPerSecond == 0, "Reconnection counted historical reports")
        print("Diagnostic rate, restart, reconnect and bounded-history checks passed")
    }
}
