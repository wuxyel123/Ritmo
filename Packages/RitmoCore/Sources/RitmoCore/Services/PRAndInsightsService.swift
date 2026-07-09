import Foundation
import SwiftData

// MARK: - PRService
/// Calcola i Personal Record da tutti i set registrati
public final class PRService {

    public init() {}

    /// Calcola tutti i PR raggruppati per esercizio
    public func calculateAllPRs(from sessions: [WorkoutSession]) -> [String: PersonalRecord] {
        var prMap: [String: PersonalRecord] = [:]

        for session in sessions {
            for set in session.sets {
                guard
                    let exercise = set.exercise,
                    set.weightKg > 0,
                    let reps = set.reps, reps > 0
                else { continue }

                let name = exercise.name
                let candidate = PersonalRecord(
                    exerciseName: name,
                    weightKg: set.weightKg,
                    reps: reps,
                    achievedDate: session.startTime
                )

                // Aggiorna il PR se l'1RM stimato è maggiore
                if let existing = prMap[name] {
                    if candidate.estimatedOneRepMax > existing.estimatedOneRepMax {
                        prMap[name] = candidate
                    }
                } else {
                    prMap[name] = candidate
                }
            }
        }

        return prMap
    }

    /// Progressione nel tempo di un esercizio specifico (per grafici)
    public func progression(
        for exerciseName: String,
        in sessions: [WorkoutSession]
    ) -> [ExerciseDataPoint] {
        sessions
            .sorted { $0.startTime < $1.startTime }
            .compactMap { session -> ExerciseDataPoint? in
                let relevantSets = session.sets.filter {
                    $0.exercise?.name == exerciseName &&
                    $0.weightKg > 0 &&
                    ($0.reps ?? 0) > 0 &&
                    $0.setType == .normal // ignora warmup per PR
                }
                guard !relevantSets.isEmpty else { return nil }
                let best = relevantSets.max { a, b in
                    PersonalRecord(exerciseName: exerciseName, weightKg: a.weightKg, reps: a.reps ?? 0, achievedDate: session.startTime).estimatedOneRepMax <
                    PersonalRecord(exerciseName: exerciseName, weightKg: b.weightKg, reps: b.reps ?? 0, achievedDate: session.startTime).estimatedOneRepMax
                }!
                return ExerciseDataPoint(
                    date: session.startTime,
                    weightKg: best.weightKg,
                    reps: best.reps ?? 0,
                    estimatedOneRepMax: PersonalRecord(
                        exerciseName: exerciseName,
                        weightKg: best.weightKg,
                        reps: best.reps ?? 0,
                        achievedDate: session.startTime
                    ).estimatedOneRepMax
                )
            }
    }

    /// Volume per gruppo muscolare negli ultimi N giorni
    public func volumeByMuscleGroup(
        from sessions: [WorkoutSession],
        days: Int = 7
    ) -> [MuscleGroup: Double] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        var volumeMap: [MuscleGroup: Double] = [:]

        for session in sessions where session.startTime >= cutoff {
            for set in session.sets {
                guard let group = set.exercise?.muscleGroup else { continue }
                volumeMap[group, default: 0] += set.volume
            }
        }
        return volumeMap
    }
}

public struct ExerciseDataPoint: Identifiable {
    public let id = UUID()
    public let date: Date
    public let weightKg: Double
    public let reps: Int
    public let estimatedOneRepMax: Double
}

// MARK: - InsightsService
/// Genera insight e correlazioni cross-source.
///
/// REGOLA DI TONO (richiesta esplicita dell'utente): gli insight riportano
/// SOLO i dati — niente consigli, giudizi o lezioni ("aggiungi trazioni",
/// "rischio infortuni", "continua così"). Se il volume push supera il pull,
/// il testo dice quello e basta, con i numeri.
public final class InsightsService {

    public init() {}

    /// Genera la lista di insight per la settimana corrente
    public func generateInsights(
        sessions: [WorkoutSession],
        nutritionHistory: [NutritionDay],
        sleepHistory: [SleepSession],
        activityHistory: [DailyActivity],
        goals: UserGoals
    ) -> [FitInsight] {
        var insights: [FitInsight] = []

        insights += muscleBalanceInsights(sessions: sessions)
        insights += trainingLoadInsights(sessions: sessions)
        insights += recoveryInsights(sessions: sessions, sleepHistory: sleepHistory)
        insights += sleepQualityInsights(sleepHistory: sleepHistory)
        insights += nutritionInsights(nutritionHistory: nutritionHistory, goals: goals)
        insights += proteinPostWorkoutInsights(sessions: sessions, nutritionHistory: nutritionHistory)
        insights += sleepPerformanceInsights(sessions: sessions, sleepHistory: sleepHistory)

        return insights.sorted { $0.priority.rawValue > $1.priority.rawValue }
    }

    // MARK: - Insight generators

    private func muscleBalanceInsights(sessions: [WorkoutSession]) -> [FitInsight] {
        let prService = PRService()
        let volumeMap = prService.volumeByMuscleGroup(from: sessions, days: 14)
        guard !volumeMap.isEmpty else { return [] }

        var insights: [FitInsight] = []

        // Rapporto push/pull
        let pushVolume = (volumeMap[.chest] ?? 0) + (volumeMap[.shoulders] ?? 0) + (volumeMap[.triceps] ?? 0)
        let pullVolume = (volumeMap[.back] ?? 0) + (volumeMap[.biceps] ?? 0)

        if pushVolume > 0 && pullVolume > 0 {
            let ratio = pushVolume / pullVolume
            if ratio > 1.5 {
                insights.append(FitInsight(
                    id: UUID(),
                    title: "Volume push maggiore del pull",
                    messageKey: "Ultimi 14 giorni: il volume push è il %@%% del volume pull (%@ kg contro %@ kg).",
                    messageArgs: ["\(Int(ratio * 100))", "\(Int(pushVolume))", "\(Int(pullVolume))"],
                    type: .warning,
                    priority: .high,
                    category: .workout,
                    icon: "⚖️"
                ))
            } else if ratio < 0.7 {
                insights.append(FitInsight(
                    id: UUID(),
                    title: "Volume pull maggiore del push",
                    messageKey: "Ultimi 14 giorni: il volume pull è il %@%% del volume push (%@ kg contro %@ kg).",
                    messageArgs: ["\(Int(100 / ratio))", "\(Int(pullVolume))", "\(Int(pushVolume))"],
                    type: .suggestion,
                    priority: .medium,
                    category: .workout,
                    icon: "⚖️"
                ))
            }
        }

        // Gambe vs upper body
        let legVolume = (volumeMap[.quads] ?? 0) + (volumeMap[.hamstrings] ?? 0) + (volumeMap[.glutes] ?? 0)
        let upperVolume = pushVolume + pullVolume
        if upperVolume > 0 && legVolume < upperVolume * 0.2 {
            insights.append(FitInsight(
                id: UUID(),
                title: "Volume gambe inferiore al busto",
                messageKey: "Ultime 2 settimane: volume gambe %@ kg, busto %@ kg (%@%% del busto).",
                messageArgs: ["\(Int(legVolume))", "\(Int(upperVolume))",
                              "\(Int(legVolume / upperVolume * 100))"],
                type: .warning,
                priority: .high,
                category: .workout,
                icon: "🦵"
            ))
        }

        return insights
    }

    private func trainingLoadInsights(sessions: [WorkoutSession]) -> [FitInsight] {
        guard !sessions.isEmpty else { return [] }
        let load = TrainingLoad.compute(from: sessions)
        let pct = Int((load.ratio * 100).rounded())

        switch load.status {
        case .veryHigh:
            return [FitInsight(
                id: UUID(),
                title: "Carico oltre il 150% della media",
                messageKey: "Il carico degli ultimi 7 giorni è al %@%% della tua media di 4 settimane.",
                messageArgs: ["\(pct)"],
                type: .warning,
                priority: .high,
                category: .workout,
                icon: "🔥"
            )]
        case .high:
            return [FitInsight(
                id: UUID(),
                title: "Carico tra il 130% e il 150% della media",
                messageKey: "Il carico degli ultimi 7 giorni è al %@%% della tua media di 4 settimane.",
                messageArgs: ["\(pct)"],
                type: .suggestion,
                priority: .medium,
                category: .workout,
                icon: "📈"
            )]
        case .low:
            return [FitInsight(
                id: UUID(),
                title: "Carico sotto l'80% della media",
                messageKey: "Il carico degli ultimi 7 giorni è al %@%% della tua media di 4 settimane.",
                messageArgs: ["\(pct)"],
                type: .tip,
                priority: .low,
                category: .workout,
                icon: "🌱"
            )]
        case .optimal:
            return []
        }
    }

    private func recoveryInsights(
        sessions: [WorkoutSession],
        sleepHistory: [SleepSession]
    ) -> [FitInsight] {
        var insights: [FitInsight] = []
        let avgSleep = sleepHistory.map { $0.totalHours }.reduce(0, +) / Double(max(sleepHistory.count, 1))

        if avgSleep < 6.5 && !sessions.isEmpty {
            insights.append(FitInsight(
                id: UUID(),
                title: "Sonno medio sotto le 6,5 ore",
                messageKey: "Stai dormendo in media %@h a notte.",
                messageArgs: [String(format: "%.1f", avgSleep)],
                type: .warning,
                priority: .high,
                category: .recovery,
                icon: "😴"
            ))
        }

        return insights
    }

    private func nutritionInsights(
        nutritionHistory: [NutritionDay],
        goals: UserGoals
    ) -> [FitInsight] {
        var insights: [FitInsight] = []
        let last7 = Array(nutritionHistory.prefix(7)).filter { $0.calories > 50 }
        guard !last7.isEmpty else { return [] }

        let avgProtein = last7.map { $0.protein }.reduce(0, +) / Double(last7.count)
        if avgProtein < goals.dailyProteinG * 0.8 {
            insights.append(FitInsight(
                id: UUID(),
                title: "Proteine sotto l'obiettivo",
                messageKey: "Media settimanale (%@ giorni tracciati): %@g di proteine su %@g di obiettivo.",
                messageArgs: ["\(last7.count)", "\(Int(avgProtein))", "\(Int(goals.dailyProteinG))"],
                type: .warning,
                priority: .high,
                category: .nutrition,
                icon: "🥩"
            ))
        }

        let avgWater = last7.map { $0.waterMl }.reduce(0, +) / Double(last7.count)
        if avgWater < goals.dailyWaterMl * 0.7 {
            insights.append(FitInsight(
                id: UUID(),
                title: "Acqua sotto l'obiettivo",
                messageKey: "Bevi in media %@L al giorno. L'obiettivo è %@L.",
                messageArgs: [String(format: "%.1f", avgWater / 1000), String(format: "%.1f", goals.dailyWaterMl / 1000)],
                type: .suggestion,
                priority: .medium,
                category: .nutrition,
                icon: "💧"
            ))
        }

        return insights
    }

    private func proteinPostWorkoutInsights(
        sessions: [WorkoutSession],
        nutritionHistory: [NutritionDay]
    ) -> [FitInsight] {
        var workoutDays: [Date] = []
        var restDays: [Date] = []
        let calendar = Calendar.current

        let last14Sessions = sessions.filter {
            $0.startTime >= calendar.date(byAdding: .day, value: -14, to: .now)!
        }

        for day in nutritionHistory.prefix(14) where day.calories > 50 {
            let isWorkoutDay = last14Sessions.contains {
                calendar.isDate($0.startTime, inSameDayAs: day.date)
            }
            if isWorkoutDay { workoutDays.append(day.date) }
            else { restDays.append(day.date) }
        }

        guard workoutDays.count >= 3, restDays.count >= 3 else { return [] }

        let workoutProtein = nutritionHistory
            .filter { day in workoutDays.contains { calendar.isDate($0, inSameDayAs: day.date) } }
            .map { $0.protein }.reduce(0, +) / Double(workoutDays.count)

        let restProtein = nutritionHistory
            .filter { day in restDays.contains { calendar.isDate($0, inSameDayAs: day.date) } }
            .map { $0.protein }.reduce(0, +) / Double(restDays.count)

        if workoutProtein > restProtein * 1.3 {
            return [FitInsight(
                id: UUID(),
                title: "Meno proteine nei giorni di riposo",
                messageKey: "Nei giorni senza allenamento assumi in media %@g di proteine in meno rispetto ai giorni di allenamento.",
                messageArgs: ["\(Int(workoutProtein - restProtein))"],
                type: .tip,
                priority: .medium,
                category: .nutrition,
                icon: "💡"
            )]
        }
        return []
    }

    private func sleepQualityInsights(sleepHistory: [SleepSession]) -> [FitInsight] {
        guard sleepHistory.count >= 3 else { return [] }
        var insights: [FitInsight] = []
        let sorted = sleepHistory.sorted { $0.startTime > $1.startTime }

        // Very short last night
        if let last = sorted.first, last.totalHours < 5 {
            insights.append(FitInsight(
                title: "Notte sotto le 5 ore",
                messageKey: "Hai dormito %@h la scorsa notte.",
                messageArgs: [String(format: "%.1f", last.totalHours)],
                type: .warning, priority: .high, category: .recovery, icon: "⚠️"
            ))
        }

        // Irregular schedule (≥5 sessions)
        if sleepHistory.count >= 5 {
            func minutesSinceNoon(_ d: Date) -> Double {
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                let m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
                return m < 720 ? m + 1440 : m
            }
            let bedtimes = sorted.map { minutesSinceNoon($0.startTime) }
            let mean = bedtimes.reduce(0, +) / Double(bedtimes.count)
            let stdDev = sqrt(bedtimes.map { pow($0 - mean, 2) }.reduce(0, +) / Double(bedtimes.count))
            if stdDev > 45 {
                insights.append(FitInsight(
                    title: "Orario di sonno variabile",
                    messageKey: "Il tuo orario di addormentamento varia in media di ±%@ minuti.",
                    messageArgs: ["\(Int(stdDev))"],
                    type: .warning, priority: .medium, category: .recovery, icon: "🕐"
                ))
            }
        }

        // Low deep / REM (only sessions with stage data)
        let withStages = sleepHistory.filter { !$0.stages.isEmpty }
        if withStages.count >= 3 {
            let total    = withStages.map { $0.totalHours }.reduce(0, +)
            let deepPct  = total > 0 ? withStages.map { $0.deepSleepHours }.reduce(0, +) / total * 100 : 0
            let remPct   = total > 0 ? withStages.map { $0.remSleepHours  }.reduce(0, +) / total * 100 : 0

            if deepPct > 0 && deepPct < 10 {
                insights.append(FitInsight(
                    title: "Sonno profondo sotto il 15%",
                    messageKey: "Il tuo sonno profondo medio è il %@%% del totale (riferimento ≥15%%).",
                    messageArgs: ["\(Int(deepPct))"],
                    type: .suggestion, priority: .medium, category: .recovery, icon: "💤"
                ))
            }
            if remPct > 0 && remPct < 15 {
                insights.append(FitInsight(
                    title: "Sonno REM sotto il 20%",
                    messageKey: "Il tuo sonno REM medio è il %@%% del totale (riferimento ≥20%%).",
                    messageArgs: ["\(Int(remPct))"],
                    type: .suggestion, priority: .medium, category: .recovery, icon: "🧠"
                ))
            }
        }

        // Positive trend — last 3 nights vs prior 4
        if sorted.count >= 7 {
            let recentAvg = sorted.prefix(3).map { $0.totalHours }.reduce(0, +) / 3
            let priorCount = Double(min(sorted.count - 3, 4))
            let priorAvg  = sorted.dropFirst(3).prefix(4).map { $0.totalHours }.reduce(0, +) / priorCount
            if recentAvg >= 7 && recentAvg > priorAvg + 0.5 {
                insights.append(FitInsight(
                    title: "Sonno in aumento",
                    messageKey: "Nelle ultime 3 notti hai dormito in media %@h, più della media delle notti precedenti.",
                    messageArgs: [String(format: "%.1f", recentAvg)],
                    type: .positive, priority: .low, category: .recovery, icon: "🌙"
                ))
            }
        }

        return insights
    }

    private func sleepPerformanceInsights(
        sessions: [WorkoutSession],
        sleepHistory: [SleepSession]
    ) -> [FitInsight] {
        guard sessions.count >= 5, sleepHistory.count >= 5 else { return [] }
        let calendar = Calendar.current

        var goodSleepVolume: Double = 0
        var poorSleepVolume: Double = 0
        var goodCount = 0
        var poorCount = 0

        for session in sessions {
            if let sleep = sleepHistory.first(where: {
                calendar.isDate($0.endTime, inSameDayAs: session.startTime)
            }) {
                if sleep.totalHours >= 7.5 {
                    goodSleepVolume += session.totalVolumeKg
                    goodCount += 1
                } else {
                    poorSleepVolume += session.totalVolumeKg
                    poorCount += 1
                }
            }
        }

        guard goodCount > 0 && poorCount > 0 else { return [] }
        let goodAvg = goodSleepVolume / Double(goodCount)
        let poorAvg = poorSleepVolume / Double(poorCount)
        let diff = ((goodAvg - poorAvg) / poorAvg) * 100

        if diff > 8 {
            return [FitInsight(
                id: UUID(),
                title: "Volume più alto dopo 7,5h+ di sonno",
                messageKey: "Nei giorni dopo almeno 7,5 ore di sonno il tuo volume di allenamento è in media il %@%% più alto.",
                messageArgs: ["\(Int(diff))"],
                type: .positive,
                priority: .low,
                category: .recovery,
                icon: "📈"
            )]
        }
        return []
    }
}

// MARK: - FitInsight Model

public struct FitInsight: Identifiable {
    public let id: UUID
    public let title: String
    public let messageKey: String
    public let messageArgs: [String]
    public let type: InsightType
    public let priority: InsightPriority
    public let category: InsightCategory
    public let icon: String

    public init(
        id: UUID = UUID(),
        title: String,
        messageKey: String,
        messageArgs: [String] = [],
        type: InsightType,
        priority: InsightPriority,
        category: InsightCategory,
        icon: String
    ) {
        self.id = id
        self.title = title
        self.messageKey = messageKey
        self.messageArgs = messageArgs
        self.type = type
        self.priority = priority
        self.category = category
        self.icon = icon
    }
}

public enum InsightType {
    case warning, suggestion, tip, positive

    public var color: String {
        switch self {
        case .warning: return "orange"
        case .suggestion: return "blue"
        case .tip: return "purple"
        case .positive: return "green"
        }
    }
}

public enum InsightPriority: Int {
    case low = 1, medium = 2, high = 3
}

public enum InsightCategory {
    case workout, nutrition, recovery, body

    public var displayName: String {
        switch self {
        case .workout: return "Allenamento"
        case .nutrition: return "Nutrizione"
        case .recovery: return "Recupero"
        case .body: return "Corpo"
        }
    }
}
