import Foundation
import StoreKit

// MARK: - ProStore
//
// Ritmo Pro: the analysis tier. The free tier — daily score, recommendation,
// workout list, sleep and recovery, the Watch app — never touches a paywall.
//
// Founding users keep Pro permanently. Anyone whose FIRST download of Ritmo
// happened before `foundingWindowEnd` is entitled for good, with nothing to
// buy and nothing to restore: they took a chance on an unknown app and their
// feedback is what made it worth charging for.
//
// The cohort is decided by `AppTransaction.originalPurchaseDate` — Apple's own
// record of when that Apple ID first downloaded the app. Deliberately NOT a
// date written at first launch: that resets on reinstall and moves with the
// device clock, so it would both punish honest users and reward dishonest ones.

@MainActor
public final class ProStore: ObservableObject {

    public static let shared = ProStore()

    /// Must match the product created in App Store Connect.
    public static let yearlyProductID = "com.alessandrodiscalzi.ritmo.pro.yearly"

    /// Everyone who installed before this keeps Pro forever.
    ///
    /// SET THIS to your launch date plus the founding window (six months) and
    /// then leave it alone — moving it later would revoke entitlements people
    /// were promised. It is intentionally a hard-coded date rather than a
    /// remote flag: a founding user's entitlement must not depend on a server
    /// that may not exist in five years.
    public static let foundingWindowEnd: Date = {
        var c = DateComponents()
        c.year = 2027; c.month = 1; c.day = 1
        return Calendar(identifier: .gregorian).date(from: c) ?? .distantPast
    }()

#if DEBUG
    /// Debug builds are always entitled, so development never runs into a
    /// paywall. Set to false when you actually want to see the locked state
    /// and test the paywall itself. Release builds ignore this entirely — it
    /// is compiled out, so there is no back door in the shipped app.
    public static var debugForcePro = true
#endif

    @Published public private(set) var isPro = false
    @Published public private(set) var isFoundingUser = false
    @Published public private(set) var product: Product?
    @Published public private(set) var isWorking = false
    @Published public private(set) var lastError: String?

    private var updateListener: Task<Void, Never>?
    private static let appGroupID = "group.alessandrodiscalzi.com.ritmo"
    private static let cachedFoundingKey = "proFoundingUser"
    private static let cachedProKey = "proEntitled"

    private init() {
        // Restore the last known answer immediately so the UI never flashes a
        // paywall at an entitled user while StoreKit is still waking up.
        let defaults = UserDefaults(suiteName: Self.appGroupID)
        isFoundingUser = defaults?.bool(forKey: Self.cachedFoundingKey) ?? false
        isPro = defaults?.bool(forKey: Self.cachedProKey) ?? false
        updateListener = listenForTransactions()
    }

    deinit { updateListener?.cancel() }

    // MARK: Entitlement

    public func refresh() async {
#if DEBUG
        if Self.debugForcePro {
            isFoundingUser = true
            isPro = true
            await loadProduct()
            return
        }
#endif
        isFoundingUser = await resolveFoundingStatus()
        let subscribed = await hasActiveSubscription()
        isPro = isFoundingUser || subscribed

        let defaults = UserDefaults(suiteName: Self.appGroupID)
        defaults?.set(isFoundingUser, forKey: Self.cachedFoundingKey)
        defaults?.set(isPro, forKey: Self.cachedProKey)

        if product == nil { await loadProduct() }
    }

    /// Whether this Apple ID's first download predates the founding window.
    ///
    /// Failure is treated generously: a cached answer if we have one, else
    /// entitled. Someone offline on first launch, or hitting a StoreKit
    /// outage, must not be told to pay for something they already own.
    private func resolveFoundingStatus() async -> Bool {
        do {
            let result = try await AppTransaction.shared
            guard case .verified(let transaction) = result else {
                return cachedFounding(default: true)
            }
            return transaction.originalPurchaseDate < Self.foundingWindowEnd
        } catch {
            return cachedFounding(default: true)
        }
    }

    private func cachedFounding(default fallback: Bool) -> Bool {
        let defaults = UserDefaults(suiteName: Self.appGroupID)
        guard defaults?.object(forKey: Self.cachedFoundingKey) != nil else { return fallback }
        return defaults?.bool(forKey: Self.cachedFoundingKey) ?? fallback
    }

    private func hasActiveSubscription() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.yearlyProductID,
                  transaction.revocationDate == nil else { continue }
            if let expiry = transaction.expirationDate, expiry < .now { continue }
            return true
        }
        return false
    }

    // MARK: Store

    private func loadProduct() async {
        product = try? await Product.products(for: [Self.yearlyProductID]).first
    }

    public func purchase() async {
        guard let product else {
            lastError = AppLocalization.string("Abbonamento non disponibile al momento. Riprova più tardi.")
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                }
                await refresh()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Required by App Review, and the only way back for someone who changed
    /// device or reinstalled.
    public func restore() async {
        isWorking = true
        defer { isWorking = false }
        try? await AppStore.sync()
        await refresh()
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.refresh()
            }
        }
    }
}

// MARK: - Pro features
//
// Named so the gating reads as a decision rather than a scattering of
// booleans, and so the free tier is legible in one place.

public enum ProFeature: String, CaseIterable, Identifiable, Sendable {
    public var id: String { rawValue }

    case statistics          // the Statistiche hub
    case calculators         // meet, RPE, pace, pace-from-HR
    case insights            // correlations and trends
    case integrations        // Hevy, Strava, OpenPowerlifting

    public var title: String {
        switch self {
        case .statistics:   return "Statistiche complete"
        case .calculators:  return "Calcolatori"
        case .insights:     return "Insights"
        case .integrations: return "Hevy, Strava e OpenPowerlifting"
        }
    }

    public var detail: String {
        switch self {
        case .statistics:
            return "Serie, tonnellaggio, frequenza, progressione esercizi, record e forza relativa."
        case .calculators:
            return "Tentativi e riscaldamento gara, RPE, passo di corsa e passo previsto dalla FC."
        case .insights:
            return "Correlazioni tra sonno, carico e performance."
        case .integrations:
            return "Importa serie e ripetizioni da Hevy, gare da Strava, massimali da OpenPowerlifting."
        }
    }

    public var icon: String {
        switch self {
        case .statistics:   return "chart.bar.xaxis"
        case .calculators:  return "function"
        case .insights:     return "chart.line.uptrend.xyaxis"
        case .integrations: return "link"
        }
    }
}
