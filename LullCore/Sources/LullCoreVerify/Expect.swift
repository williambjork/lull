import Foundation

/// Minimal assertion harness.
///
/// The toolchain this project was built with ships neither XCTest nor Swift
/// Testing, so the domain logic is verified by running an executable:
/// `swift run LullCoreVerify`. Swap this for a real test target whenever the
/// project is opened in a full Xcode install; the assertions translate directly.
final class Expect {
    private(set) var failures: [String] = []
    private(set) var checks = 0
    private var currentSuite = ""

    func suite(_ name: String, _ body: () throws -> Void) {
        currentSuite = name
        print("\n▸ \(name)")
        do {
            try body()
        } catch {
            failures.append("\(name): threw unexpected error \(error)")
            print("  ✗ threw unexpected error: \(error)")
        }
    }

    func check(_ condition: Bool, _ message: String) {
        checks += 1
        if condition {
            print("  ✓ \(message)")
        } else {
            failures.append("\(currentSuite): \(message)")
            print("  ✗ \(message)")
        }
    }

    func equal<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        checks += 1
        if actual == expected {
            print("  ✓ \(message)")
        } else {
            failures.append("\(currentSuite): \(message) — expected \(expected), got \(actual)")
            print("  ✗ \(message) — expected \(expected), got \(actual)")
        }
    }

    func close(_ actual: Double, _ expected: Double, tolerance: Double = 0.001, _ message: String) {
        check(abs(actual - expected) <= tolerance, "\(message) (expected ≈\(expected), got \(actual))")
    }

    func throwsError<T>(_ message: String, _ body: () throws -> T) {
        checks += 1
        do {
            _ = try body()
            failures.append("\(currentSuite): \(message) — no error thrown")
            print("  ✗ \(message) — no error thrown")
        } catch {
            print("  ✓ \(message)")
        }
    }

    func report() -> Int32 {
        print("\n" + String(repeating: "─", count: 60))
        if failures.isEmpty {
            print("All \(checks) checks passed.")
            return 0
        }
        print("\(failures.count) of \(checks) checks failed:")
        for failure in failures { print("  • \(failure)") }
        return 1
    }
}
