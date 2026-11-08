import Foundation

// Plain value types the engine and screens work with. SwiftData models (Phase 2+) map to these.

public enum AssetType: String, Sendable, CaseIterable, Codable {
    /// `hedged`: stock bought with an offsetting short future (arbitrage), so price moves cancel out.
    case equity, hedged, debt, cash, derivative, foreignEquity, fundUnits, other

    /// Shares of a business the fund chose to own (Indian or foreign stock, REIT units), as opposed to cash management.
    public var isOwnedCompany: Bool { self == .equity || self == .foreignEquity || self == .other }

    /// Assets the v1 estimator treats as flat (r = 0) rather than unsupported.
    public var isFlatResidual: Bool { self == .cash || self == .debt || self == .hedged }

    public var label: String {
        switch self {
        case .equity: "Equity"
        case .hedged: "Hedged equity (arbitrage)"
        case .debt: "Debt"
        case .cash: "Cash & equivalents"
        case .derivative: "Derivatives"
        case .foreignEquity: "Foreign equity"
        case .fundUnits: "Fund units"
        case .other: "Other"
        }
    }
}

public enum MarketCap: String, Sendable, CaseIterable, Codable {
    case large, mid, small

    public var label: String {
        switch self {
        case .large: "Large cap"
        case .mid: "Mid cap"
        case .small: "Small cap"
        }
    }
}

public enum FundPlan: String, Sendable, Codable { case direct, regular }

public struct SecurityInfo: Identifiable, Hashable, Sendable, Codable {
    public var id: String { isin }
    public let isin: String
    public let name: String
    public let symbol: String
    public let sector: String
    public let marketCap: MarketCap?

    public init(isin: String, name: String, symbol: String, sector: String, marketCap: MarketCap?) {
        self.isin = isin
        self.name = name
        self.symbol = symbol
        self.sector = sector
        self.marketCap = marketCap
    }
}

public struct FundInfo: Identifiable, Hashable, Sendable {
    public var id: String { code }
    /// AMFI scheme code when known, otherwise the scheme ISIN (imported funds before Phase 3).
    public let code: String
    public let name: String
    public let amc: String
    public let category: String
    public let plan: FundPlan
    public let isEstimable: Bool

    public init(code: String, name: String, amc: String, category: String, plan: FundPlan, isEstimable: Bool) {
        self.code = code
        self.name = name
        self.amc = amc
        self.category = category
        self.plan = plan
        self.isEstimable = isEstimable
    }
}

/// One row of an AMC monthly disclosure. `security` is nil when the row could not be mapped.
public struct DisclosedHolding: Identifiable, Hashable, Sendable, Codable {
    public var id: String { security?.isin ?? rawName }
    public let rawName: String
    public let security: SecurityInfo?
    public let assetType: AssetType
    /// Percent of net assets, e.g. 7.25 means 7.25%.
    public let weight: Decimal
    public let quantity: Decimal?

    public init(rawName: String, security: SecurityInfo?, assetType: AssetType, weight: Decimal, quantity: Decimal?) {
        self.rawName = rawName
        self.security = security
        self.assetType = assetType
        self.weight = weight
        self.quantity = quantity
    }
}

/// One month's published portfolio of a fund. Never edited once saved.
public struct Disclosure: Identifiable, Hashable, Sendable, Codable {
    public var id: String { "\(fundCode)-\(disclosureDate.timeIntervalSince1970)" }
    public let fundCode: String
    public let disclosureDate: Date
    public let holdings: [DisclosedHolding]
    /// Fund name as printed in the file, the file it came from, and when it was imported.
    public let sourceTitle: String?
    public let sourceFile: String?
    public let importedAt: Date?

    public init(fundCode: String, disclosureDate: Date, holdings: [DisclosedHolding],
                sourceTitle: String? = nil, sourceFile: String? = nil, importedAt: Date? = nil) {
        self.fundCode = fundCode
        self.disclosureDate = disclosureDate
        self.holdings = holdings
        self.sourceTitle = sourceTitle
        self.sourceFile = sourceFile
        self.importedAt = importedAt
    }
}

public struct Quote: Hashable, Sendable {
    public let isin: String
    public let price: Decimal
    /// Exchange-reported previous close (already adjusted for splits/bonuses).
    public let previousClose: Decimal
    public let exchangeTime: Date

    public init(isin: String, price: Decimal, previousClose: Decimal, exchangeTime: Date) {
        self.isin = isin
        self.price = price
        self.previousClose = previousClose
        self.exchangeTime = exchangeTime
    }

    public var change: Decimal { previousClose == 0 ? 0 : (price / previousClose - 1) * 100 }
}

public struct NAVPoint: Hashable, Sendable {
    public let date: Date
    public let nav: Decimal

    public init(date: Date, nav: Decimal) {
        self.date = date
        self.nav = nav
    }
}

public struct Reconciliation: Identifiable, Hashable, Sendable {
    public var id: String { "\(fundCode)-\(valuationDate.timeIntervalSince1970)" }
    public let fundCode: String
    public let valuationDate: Date
    public let estimatedNAV: Decimal
    public let officialNAV: Decimal
    public let coverage: Decimal
    public let holdingsDate: Date
    public let modelVersion: String

    public init(fundCode: String, valuationDate: Date, estimatedNAV: Decimal, officialNAV: Decimal, coverage: Decimal, holdingsDate: Date, modelVersion: String) {
        self.fundCode = fundCode
        self.valuationDate = valuationDate
        self.estimatedNAV = estimatedNAV
        self.officialNAV = officialNAV
        self.coverage = coverage
        self.holdingsDate = holdingsDate
        self.modelVersion = modelVersion
    }

    public var absError: Decimal { estimatedNAV - officialNAV }
    public var pctError: Decimal { officialNAV == 0 ? 0 : absError / officialNAV * 100 }
}

public enum ProviderStatus: String, Sendable, CaseIterable {
    case connected, updating, stale, authRequired, unavailable, importRequired

    public var label: String {
        switch self {
        case .connected: "Connected"
        case .updating: "Updating"
        case .stale: "Stale"
        case .authRequired: "Requires authentication"
        case .unavailable: "Unavailable"
        case .importRequired: "Import required"
        }
    }
}

public struct DataSourceHealth: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let detail: String
    public let status: ProviderStatus
    public let lastSuccess: Date?
    public let latestDataDate: Date?
    public let records: Int?
    public let warning: String?

    public init(name: String, detail: String, status: ProviderStatus, lastSuccess: Date?, latestDataDate: Date?, records: Int?, warning: String?) {
        self.name = name
        self.detail = detail
        self.status = status
        self.lastSuccess = lastSuccess
        self.latestDataDate = latestDataDate
        self.records = records
        self.warning = warning
    }
}

extension Decimal {
    public var double: Double { NSDecimalNumber(decimal: self).doubleValue }

    public func rounded(_ scale: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}
