import Foundation

public enum ReplacementMutation: Sendable {
    case add(TextReplacement)
    case update(originalShortcut: String, replacement: TextReplacement)
    case delete(shortcut: String)
}

public enum SnapshotProtection: Equatable, Sendable {
    case required
    case unprotectedOnce
}

public protocol SnapshotWriting: Sendable {
    func write(
        replacements: [TextReplacement],
        configuration: ReplaceKitConfiguration,
        reason: SnapshotReason
    ) throws
}

extension SnapshotStore: SnapshotWriting {
    public func write(
        replacements: [TextReplacement],
        configuration: ReplaceKitConfiguration,
        reason: SnapshotReason
    ) throws {
        _ = try writeSnapshot(
            replacements: replacements,
            configuration: configuration,
            reason: reason
        )
    }
}

public struct ApplyResult: Sendable {
    public let observed: [TextReplacement]

    public init(observed: [TextReplacement]) {
        self.observed = observed
    }
}

public enum ApplyCoordinatorError: Error {
    case changedBasis(ReplacementDiff)
    case snapshotUnavailable(String)
    case partialResult(observed: [TextReplacement], message: String)
    case postconditionFailed(expected: [TextReplacement], observed: [TextReplacement])
}

public actor ApplyCoordinator {
    private let reader: any TextReplacementReading
    private let writer: any TextReplacementWriting
    private let snapshots: any SnapshotWriting

    public init(
        reader: any TextReplacementReading,
        writer: any TextReplacementWriting,
        snapshots: any SnapshotWriting
    ) {
        self.reader = reader
        self.writer = writer
        self.snapshots = snapshots
    }

    public func apply(
        _ mutation: ReplacementMutation,
        configuration: ReplaceKitConfiguration,
        protection: SnapshotProtection = .required
    ) async throws -> ApplyResult {
        let before = try reader.fetchAll()
        try protect(before, configuration: configuration, protection: protection)
        let expected = try applying(mutation, to: before)
        do {
            try await execute(mutation)
        } catch {
            throw ApplyCoordinatorError.partialResult(
                observed: (try? reader.fetchAll()) ?? [],
                message: error.localizedDescription
            )
        }
        return try await verifiedResult(expected: expected)
    }

    public func apply(
        proposed: [TextReplacement],
        previewBasis: [TextReplacement],
        configuration: ReplaceKitConfiguration,
        protection: SnapshotProtection = .required
    ) async throws -> ApplyResult {
        try TextReplacement.validateUnique(proposed)
        let current = try reader.fetchAll()
        guard !ReplacementDiff.basisChanged(preview: previewBasis, observed: current) else {
            throw ApplyCoordinatorError.changedBasis(.compare(current: current, proposed: proposed))
        }

        try protect(current, configuration: configuration, protection: protection)
        let diff = ReplacementDiff.compare(current: current, proposed: proposed)
        let mutations =
            diff.deleted.map { ReplacementMutation.delete(shortcut: $0.shortcut) } +
            diff.edited.map {
                ReplacementMutation.update(
                    originalShortcut: $0.before.shortcut,
                    replacement: $0.after
                )
            } +
            diff.added.map(ReplacementMutation.add)
        do {
            for mutation in mutations {
                try await execute(mutation)
            }
        } catch {
            throw ApplyCoordinatorError.partialResult(
                observed: (try? reader.fetchAll()) ?? [],
                message: error.localizedDescription
            )
        }
        return try await verifiedResult(expected: proposed)
    }

    private func protect(
        _ replacements: [TextReplacement],
        configuration: ReplaceKitConfiguration,
        protection: SnapshotProtection
    ) throws {
        guard protection == .required else { return }
        do {
            try snapshots.write(
                replacements: replacements,
                configuration: configuration,
                reason: .beforeEdit
            )
        } catch {
            throw ApplyCoordinatorError.snapshotUnavailable(String(describing: error))
        }
    }

    private func execute(_ mutation: ReplacementMutation) async throws {
        switch mutation {
        case let .add(replacement):
            try await writer.add(replacement)
        case let .update(shortcut, replacement):
            try await writer.update(originalShortcut: shortcut, replacement: replacement)
        case let .delete(shortcut):
            try await writer.delete(shortcut: shortcut)
        }
    }

    private func applying(
        _ mutation: ReplacementMutation,
        to replacements: [TextReplacement]
    ) throws -> [TextReplacement] {
        var values = Dictionary(uniqueKeysWithValues: replacements.map { ($0.shortcut, $0) })
        switch mutation {
        case let .add(replacement):
            values[replacement.shortcut] = replacement
        case let .update(shortcut, replacement):
            values.removeValue(forKey: shortcut)
            values[replacement.shortcut] = replacement
        case let .delete(shortcut):
            values.removeValue(forKey: shortcut)
        }
        let result = values.values.sorted { $0.shortcut < $1.shortcut }
        try TextReplacement.validateUnique(result)
        return result
    }

    private func verifiedResult(expected: [TextReplacement]) async throws -> ApplyResult {
        let expected = expected.sorted { $0.shortcut < $1.shortcut }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while clock.now < deadline {
            let observed = try reader.fetchAll().sorted { $0.shortcut < $1.shortcut }
            if observed == expected {
                return ApplyResult(observed: observed)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        let observed = try reader.fetchAll().sorted { $0.shortcut < $1.shortcut }
        throw ApplyCoordinatorError.postconditionFailed(expected: expected, observed: observed)
    }
}
