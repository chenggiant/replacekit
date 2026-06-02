import ApplicationServices

public struct AccessibilityTrust: Sendable {
    public init() {}

    public func isTrusted(prompt: Bool) -> Bool {
        let options = [
            "AXTrustedCheckOptionPrompt": prompt,
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
