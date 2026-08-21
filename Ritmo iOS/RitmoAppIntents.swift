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
    // App Store Connect rejects the word "Apple" anywhere in App Intents
    // metadata, so the Health app is named without it here. The runtime
    // dialogs below are not extracted as metadata and can say "Apple Salute".
    static let description = IntentDescription("Aggiunge acqua al diario di oggi in Salute.")

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
            let text = String(format: AppLocalization.string("Registrati %@ ml di acqua 💧"), "\(ml)")
            return .result(dialog: IntentDialog("\(text)"))
        } catch {
            // Most likely cause: HealthKit write permission not granted yet.
            let text = AppLocalization.string("Non riesco a scrivere su Apple Salute. Apri Ritmo e verifica i permessi di Salute.")
            return .result(dialog: IntentDialog("\(text)"))
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
                                               load: load,
                                               hasWorkedOutToday: snapshot.hasWorkedOutToday,
                                               sessions: sessions,
                                               weeklyWorkoutGoal: goals.weeklyWorkouts)

        // Composed + localized by hand: IntentDialog's literal interpolation
        // would bake the Italian kind title / reason into the spoken answer.
        let scoreText = String(format: AppLocalization.string("Il tuo punteggio di oggi è %@ su 100."),
                               "\(snapshot.dayScore)")
        if let plan {
            let title = AppLocalization.string(plan.kind.title)
            return .result(dialog: IntentDialog("\(scoreText) \(title): \(plan.reason)"))
        }
        return .result(dialog: IntentDialog("\(scoreText)"))
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
                "Log water in \(.applicationName)",
                "Enregistre de l'eau sur \(.applicationName)",
                "Registra agua en \(.applicationName)",
                "Wasser eintragen in \(.applicationName)",
                "Regista água no \(.applicationName)"
            ],
            shortTitle: "Registra acqua",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: GetDayScoreIntent(),
            phrases: [
                "Com'è il mio punteggio su \(.applicationName)",
                "Punteggio di oggi su \(.applicationName)",
                "What's my score in \(.applicationName)",
                "Quel est mon score sur \(.applicationName)",
                "Cuál es mi puntuación en \(.applicationName)",
                "Wie ist mein Score in \(.applicationName)",
                "Qual é a minha pontuação no \(.applicationName)"
            ],
            shortTitle: "Punteggio di oggi",
            systemImageName: "chart.bar.fill"
        )
    }
}
