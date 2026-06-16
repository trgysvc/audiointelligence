import Foundation

/// Shared red/green tolerance-table sink for validation suites.
/// Lock-protected so async tests can record rows under Swift 6 concurrency.
final class ValidationTable: @unchecked Sendable {
    struct Row: Sendable {
        let metric: String
        let expected: String
        let measured: String
        let delta: String
        let tolerance: String
        let pass: Bool
    }

    private let title: String
    private let lock = NSLock()
    private var rows: [Row] = []

    init(_ title: String) { self.title = title }

    /// Numeric check against an expected value with an absolute tolerance.
    @discardableResult
    func check(_ metric: String, expected: Double, measured: Double, tol: Double) -> Bool {
        let delta = measured - expected
        let pass = abs(delta) <= tol
        lock.lock()
        rows.append(Row(
            metric: metric,
            expected: String(format: "%.2f", expected),
            measured: String(format: "%.2f", measured),
            delta: String(format: "%+.2f", delta),
            tolerance: "±\(String(format: "%.2f", tol))",
            pass: pass
        ))
        lock.unlock()
        return pass
    }

    /// Exact/categorical check.
    @discardableResult
    func checkExact(_ metric: String, expected: String, measured: String, pass: Bool) -> Bool {
        lock.lock()
        rows.append(Row(metric: metric, expected: expected, measured: measured, delta: "—", tolerance: "exact", pass: pass))
        lock.unlock()
        return pass
    }

    func printTable() {
        lock.lock(); let rows = self.rows; lock.unlock()
        guard !rows.isEmpty else { return }
        let mW = max(34, rows.map { $0.metric.count }.max() ?? 0)
        func pad(_ s: String, _ w: Int) -> String { s.count >= w ? s : s + String(repeating: " ", count: w - s.count) }
        print("\n┌─ \(title) ──────────────────────────────────")
        print("│ \(pad("METRIC", mW))  \(pad("EXPECTED", 9))  \(pad("MEASURED", 9))  \(pad("Δ", 8))  \(pad("TOL", 8))  RESULT")
        print("├──────────────────────────────────────────────────────────────────────────")
        for r in rows {
            print("│ \(pad(r.metric, mW))  \(pad(r.expected, 9))  \(pad(r.measured, 9))  \(pad(r.delta, 8))  \(pad(r.tolerance, 8))  \(r.pass ? "✅ PASS" : "❌ FAIL")")
        }
        let passed = rows.filter { $0.pass }.count
        print("└─ \(passed)/\(rows.count) PASSED ──────────────────────────────────────────────────\n")
    }
}
