import Foundation

/// Summary of estimate-vs-official errors (docs/10-nav-engine.md §3).
public struct AccuracyStats: Hashable, Sendable {
    public static let minimumDaysForJudgement = 30

    public let count: Int
    /// Mean absolute percentage error.
    public let meanAbsError: Decimal?
    public let medianAbsError: Decimal?
    /// Largest absolute error, signed.
    public let worstError: Decimal?
    /// Share of days with |error| ≤ 0.25%, in percent.
    public let withinQuarterPercent: Decimal?

    public var hasEnoughHistory: Bool { count >= Self.minimumDaysForJudgement }

    public init(_ rows: [Reconciliation]) {
        count = rows.count
        let errors = rows.map(\.pctError)
        let absErrors = errors.map { abs($0) }.sorted()
        guard !absErrors.isEmpty else {
            meanAbsError = nil; medianAbsError = nil; worstError = nil; withinQuarterPercent = nil
            return
        }
        meanAbsError = absErrors.reduce(0, +) / Decimal(absErrors.count)
        let mid = absErrors.count / 2
        medianAbsError = absErrors.count.isMultiple(of: 2) ? (absErrors[mid - 1] + absErrors[mid]) / 2 : absErrors[mid]
        worstError = errors.max { abs($0) < abs($1) }
        withinQuarterPercent = Decimal(absErrors.filter { $0 <= 0.25 }.count) / Decimal(absErrors.count) * 100
    }
}
