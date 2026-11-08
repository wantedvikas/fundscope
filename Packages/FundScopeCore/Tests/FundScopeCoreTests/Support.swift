import Foundation
@testable import FundScopeCore

/// Builds an IST date for tests.
func ist(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    MarketCalendar().calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

func security(_ id: String, sector: String = "Banking", cap: MarketCap = .large) -> SecurityInfo {
    SecurityInfo(isin: id, name: id, symbol: id, sector: sector, marketCap: cap)
}

func equity(_ id: String, _ weight: Decimal, qty: Decimal? = nil, sector: String = "Banking") -> DisclosedHolding {
    DisclosedHolding(rawName: id, security: security(id, sector: sector), assetType: .equity, weight: weight, quantity: qty)
}

func other(_ name: String, _ type: AssetType, _ weight: Decimal) -> DisclosedHolding {
    DisclosedHolding(rawName: name, security: nil, assetType: type, weight: weight, quantity: nil)
}
