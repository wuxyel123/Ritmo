import AppIntents
import SwiftData
import RitmoCore

// MARK: - App Intents (Siri / Shortcuts)
//
// These live in the app target (not the widget extension) so they run in the
// app's own process, where HealthKit and the SwiftData store are available.
// Interactive widget buttons are deliberately NOT built on these: HealthKit
// is unavailable in the widget extension process.

// MARK: Log water

struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Registra acqua"
    static let description = IntentDescription("Aggiunge acqua al diario di oggi in Apple Salute.")

    @Parameter(title: "Millilitri", default: 250)
    var amount: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Registra \(\.$amount) ml di acqua")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ml = min(max(amount, 50), 2000)
        do {
            try await HealthKitRepository().writeWater(ml: Double(ml))
            return .result(dialog: IntentDialog("Registrati \(ml) ml di acqua 💧"))
        } catch {
            // Most likely cause: HealthKit write permission not granted yet.
            return .result(dialog: IntentDialog(
                "Non riesco a scrivere su Apple Salute. Apri Ritmo e verifica i permessi di Salute."))
        }
    }
}

// MARK: Day score

struct GetDayScoreIntent: AppIntent {
    static let title: LocalizedStringResource = "Punteggio di oggi"
    static let description = IntentDescription("Il punteggio giornaliero Ritmo e il consiglio del giorno.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let repo = HealthKitRepository()
        let context = RitmoStore.container.mainContext
        let goals = UserGoals.canonical(in: context)

        let snapshot = await repo.fetchDailySnapshot(for: .now, goals: goals)
        let recovery = await repo.fetchRecovery()
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let load = sessions.isEmpty ? nil : TrainingLoad.compute(from: sessions)
        let plan = DailyRecommendation.compute(recovery: recovery.overall > 0 ? recovery : nil,
                                               load: load)

        if let plan {
            return .result(dialog: IntentDialog(
                "Il tuo punteggio di oggi è \(snapshot.dayScore) su 100. \(plan.kind.title): \(plan.reason)"))
        }
        return .result(dialog: IntentDialog("Il tuo punteggio di oggi è \(snapshot.dayScore) su 100."))
    }
}

// MARK: Shortcuts provider

struct RitmoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogWaterIntent(),
            phrases: [
                "Registra acqua su \(.applicationName)",
                "Aggiungi acqua su \(.applicationName)",
                "Log water in \(.applicationName)"
            ],
            shortTitle: "Registra acqua",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: GetDayScoreIntent(),
            phrases: [
                "Com'è il mio punteggio su \(.applicationName)",
                "Punteggio di oggi su \(.applicationName)",
                "What's my score in \(.applicationName)"
            ],
            shortTitle: "Punteggio di oggi",
            systemImageName: "chart.bar.fill"
        )
    }
}
