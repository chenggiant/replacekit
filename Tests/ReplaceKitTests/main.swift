import Darwin
import ReplaceKitCore
import ReplaceKitMac

var failures = 0

@MainActor
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("PASS: \(message)")
    } else {
        failures += 1
        print("FAIL: \(message)")
    }
}

check(true, "core module loads")
check(true, "mac module loads")

if failures > 0 {
    exit(1)
}
