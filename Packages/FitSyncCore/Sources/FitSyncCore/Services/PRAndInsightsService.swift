import Foundation
import SwiftData

// MARK: - PRService
/// Calcola i Personal Record da tutti i set importati da Hevy
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
/// Genera insight e correlazioni cross-source
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
        insights += recoveryInsights(sessions: sessions, sleepHistory: sleepHistory)
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
                    title: "Troppo Push, poco Pull",
                    message: "In 14 giorni hai fatto \(Int(ratio * 100))% più volume push che pull. Rischio infortuni alla spalla. Aggiungi rematori o trazioni.",
                    type: .warning,
                    priority: .high,
                    category: .workout,
                    icon: "⚖️"
                ))
            } else if ratio < 0.7 {
                insights.append(FitInsight(
                    id: UUID(),
                    title: "Pull dominante",
                    message: "Hai più volume pull che push. Bilancia con più esercizi per petto e spalle.",
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
                title: "Skip leg day detected 🦵",
                message: "Nelle ultime 2 settimane hai allenato le gambe molto meno del busto. Le gambe sono il motore della forza totale.",
                type: .warning,
                priority: .high,
                category: .workout,
                icon: "🦵"
            ))
        }

        return insights
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
                title: "Recupero insufficiente",
                message: "Stai dormendo in media \(String(format: "%.1f", avgSleep))h. Con meno di 7h il testosterone cala del 10-15% e i progressi rallentano.",
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
        let last7 = Array(nutritionHistory.prefix(7))
        guard !last7.isEmpty else { return [] }

        let avgProtein = last7.map { $0.protein }.reduce(0, +) / Double(last7.count)
        if avgProtein < goals.dailyProteinG * 0.8 {
            insights.append(FitInsight(
                id: UUID(),
                title: "Proteine insufficienti",
                message: "Media settimanale: \(Int(avgProtein))g su \(Int(goals.dailyProteinG))g obiettivo. Con meno proteine perdi massa muscolare anche con l'allenamento.",
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
                title: "Idratazione bassa",
                message: "Bevi in media \(Int(avgWater / 1000 * 10) / 10)L al giorno. L'obiettivo è \(Int(goals.dailyWaterMl / 100) / 10)L.",
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

        for day in nutritionHistory.prefix(14) {
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
                title: "Proteine nei giorni di riposo",
                message: "Mangi \(Int(workoutProtein - restProtein))g in meno di proteine nei giorni senza allenamento. Il muscolo si ricostruisce anche a riposo — mantieni l'apporto costante.",
                type: .tip,
                priority: .medium,
                category: .nutrition,
                icon: "💡"
            )]
        }
        return []
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
                title: "Il sonno migliora le tue performance",
                message: "Con 7.5h+ di sonno il tuo volume di allenamento è \(Int(diff))% più alto. Dormire è parte dell'allenamento.",
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
    public let message: String
    public let type: InsightType
    public let priority: InsightPriority
    public let category: InsightCategory
    public let icon: String

    public init(
        id: UUID = UUID(),
        title: String,
        message: String,
        type: InsightType,
        priority: InsightPriority,
        category: InsightCategory,
        icon: String
    ) {
        self.id = id
        self.title = title
        self.message = message
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
