import Foundation

// MARK: - DateValuePoint (for charts)
public struct DateValuePoint: Identifiable {
    public let id = UUID()
    public let date: Date
    public let value: Double
    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

// MARK: - NutritionDay
public struct NutritionDay: Identifiable, Codable {
    public let id: UUID
    public let date: Date
    public var calories: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var fiber: Double
    public var waterMl: Double

    public init(
        id: UUID = UUID(),
        date: Date,
        calories: Double = 0,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        fiber: Double = 0,
        waterMl: Double = 0
    ) {
        self.id = id
        self.date = date
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.waterMl = waterMl
    }

    /// Percentuale obiettivo raggiunta (0-1), richiede UserGoals
    public func calorieProgress(goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return min(calories / goal, 1.0)
    }

    public func proteinProgress(goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return min(protein / goal, 1.0)
    }

    public func carbsProgress(goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return min(carbs / goal, 1.0)
    }

    public func fatProgress(goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return min(fat / goal, 1.0)
    }

    public func fiberProgress(goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return min(fiber / goal, 1.0)
    }

    public func waterProgress(goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return min(waterMl / goal, 1.0)
    }
}

// MARK: - BodyMetric
public struct BodyMetric: Identifiable, Codable {
    public let id: UUID
    public let date: Date
    public let weightKg: Double?
    public let bodyFatPercentage: Double?
    public let bmi: Double?
    public let leanBodyMassKg: Double?

    public init(
        id: UUID = UUID(),
        date: Date,
        weightKg: Double? = nil,
        bodyFatPercentage: Double? = nil,
        bmi: Double? = nil,
        leanBodyMassKg: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
        self.bodyFatPercentage = bodyFatPercentage
        self.bmi = bmi
        self.leanBodyMassKg = leanBodyMassKg
    }
}

// MARK: - SleepSession
public struct SleepSession: Identifiable, Codable {
    public let id: UUID
    public let startTime: Date
    public let endTime: Date
    public let stages: [SleepStage]
    /// Minutes the bedtime deviated from recent averages; nil = no history (no consistency penalty)
    public let bedtimeDeviationMinutes: Double?
    /// User-reported night wake-ups (manual logging only — watch-tracked
    /// nights have real awake stages instead). nil = not reported.
    public let manualWakeCount: Int?
    /// How long the user typically stays awake per wake-up (Settings → Sonno).
    /// Only used for reported wake counts; nil falls back to 10 minutes.
    public let manualAwakeMinutesPerWake: Double?

    public init(
        id: UUID = UUID(),
        startTime: Date,
        endTime: Date,
        stages: [SleepStage] = [],
        bedtimeDeviationMinutes: Double? = nil,
        manualWakeCount: Int? = nil,
        manualAwakeMinutesPerWake: Double? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.stages = stages
        self.bedtimeDeviationMinutes = bedtimeDeviationMinutes
        self.manualWakeCount = manualWakeCount
        self.manualAwakeMinutesPerWake = manualAwakeMinutesPerWake
    }

    public var totalHours: Double {
        endTime.timeIntervalSince(startTime) / 3600
    }

    public var deepSleepHours: Double {
        stages.filter { $0.type == .deep }.reduce(0) { $0 + $1.durationHours }
    }

    public var remSleepHours: Double {
        stages.filter { $0.type == .rem }.reduce(0) { $0 + $1.durationHours }
    }

    /// Sleep quality 0-100, broken into its 5 weighted components so both the
    /// total and the per-component points can be shown (single source of
    /// truth for iOS + watchOS, which previously each computed this inline).
    /// duration 40 | deep% 20 | rem% 20 | continuity 10 | schedule consistency 10
    public var scoreBreakdown: SleepScoreBreakdown {
        let total = max(totalHours, 0.01)
        let awakeH = stages.filter { $0.type == .awake }.reduce(0) { $0 + $1.durationHours }

        let durationScore    = min(totalHours / 8.0, 1.0) * 40
        let deepScore        = min((deepSleepHours / total) / 0.15, 1.0) * 20
        let remScore         = min((remSleepHours  / total) / 0.20, 1.0) * 20
        // 0% awake = 10 pts, 15%+ awake = 0 pts. WASO of 15-30 min in an 8h
        // night is normal/healthy, and HealthKit's staging tends to flag
        // brief motion blips as "awake" — the old 5% cutoff (~24 min) zeroed
        // this out for essentially normal sleep. Older manual logs have no
        // awake stages: reconstruct the awake time from the reported wake
        // count × the user's average awake minutes, then score it identically,
        // so a night scores the same however it was recorded.
        let continuityScore: Double
        let reportedAwakeH: Double = {
            guard awakeH == 0, let wakes = manualWakeCount, wakes > 0 else { return awakeH }
            let perWake = manualAwakeMinutesPerWake ?? 10
            return Double(wakes) * perWake / 60
        }()
        if reportedAwakeH > 0 {
            continuityScore = max(0.0, 1.0 - (reportedAwakeH / total) / 0.15) * 10
        } else {
            continuityScore = 10
        }
        let consistencyScore: Double
        if let dev = bedtimeDeviationMinutes {
            // ≤30 min deviation = 10 pts, 90+ min deviation = 0 pts (ordinary
            // weekday/weekend bedtime drift is often 30-45 min on its own)
            consistencyScore = max(0.0, 1.0 - max(0.0, dev - 30) / 60.0) * 10
        } else {
            consistencyScore = 10
        }
        return SleepScoreBreakdown(duration: Int(durationScore), deep: Int(deepScore), rem: Int(remScore),
                                   continuity: Int(continuityScore), consistency: Int(consistencyScore))
    }

    public var qualityScore: Int { scoreBreakdown.total }
}

public struct SleepScoreBreakdown {
    public let duration: Int      // out of 40
    public let deep: Int          // out of 20
    public let rem: Int           // out of 20
    public let continuity: Int    // out of 10
    public let consistency: Int   // out of 10

    public var total: Int { duration + deep + rem + continuity + consistency }
}

public struct SleepStage: Identifiable, Codable {
    public let id: UUID
    public let startTime: Date
    public let endTime: Date
    public let type: SleepStageType

    public var durationHours: Double {
        endTime.timeIntervalSince(startTime) / 3600
    }

    public init(id: UUID = UUID(), startTime: Date, endTime: Date, type: SleepStageType) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.type = type
    }
}

public enum SleepStageType: String, Codable {
    case awake = "Sveglio"
    case rem = "REM"
    case core = "Core"
    case deep = "Profondo"
    case unspecified = "Sonno"
}

// MARK: - SleepQuality

public enum SleepQuality: Int, Codable, CaseIterable, Sendable {
    // Declaration order = display order (allCases follows it). Raw values are
    // STORAGE IDs for already-logged nights — 0 and 5 were added when the
    // scale grew from 4 to 6 levels, so they sit out of sequence on purpose.
    // Never renumber the existing ones.
    case pessimo = 0
    case scarso = 1
    case sufficiente = 2
    case buono = 3
    case moltoBuono = 5
    case ottimo = 4

    public var label: String {
        switch self {
        case .pessimo:     return "Pessimo"
        case .scarso:      return "Scarso"
        case .sufficiente: return "Sufficiente"
        case .buono:       return "Buono"
        case .moltoBuono:  return "Molto buono"
        case .ottimo:      return "Ottimo"
        }
    }

    public var emoji: String {
        switch self {
        case .pessimo:     return "😫"
        case .scarso:      return "😞"
        case .sufficiente: return "😐"
        case .buono:       return "🙂"
        case .moltoBuono:  return "😊"
        case .ottimo:      return "🤩"
        }
    }

    /// Position on the 6-level scale (0-based, display order).
    public var scaleIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// Maps the 6 levels to a 0-30 recovery score.
    public var baseRecoveryScore: Double {
        Double(scaleIndex + 1) / Double(Self.allCases.count) * 30
    }

    /// (deep fraction, REM fraction) of total sleep duration for Apple Health stage writing.
    /// Core = 1 - deep - rem. Based on typical sleep architecture scaled by quality.
    public var sleepStageFractions: (deep: Double, rem: Double) {
        switch self {
        case .pessimo:     return (0.03, 0.07)   // barely restorative
        case .scarso:      return (0.05, 0.10)
        case .sufficiente: return (0.12, 0.15)
        case .buono:       return (0.18, 0.20)
        case .moltoBuono:  return (0.22, 0.23)
        case .ottimo:      return (0.25, 0.25)   // excellent: ~50% restorative
        }
    }
}

// MARK: - DailyActivity
public struct DailyActivity: Identifiable, Codable {
    public let id: UUID
    public let date: Date
    public var steps: Int
    public var activeCalories: Double
    public var restingCalories: Double
    public var exerciseMinutes: Int
    public var standHours: Int
    public var flightsClimbed: Int
    public var distanceKm: Double
    public var mindfulMinutes: Int
    public var vo2Max: Double?
    public var heartRateAvg: Double?
    public var heartRateResting: Double?
    public var hrv: Double?
    public var spO2: Double?          // % (e.g. 98.0)
    public var respiratoryRate: Double? // breaths/min

    public init(
        id: UUID = UUID(),
        date: Date,
        steps: Int = 0,
        activeCalories: Double = 0,
        restingCalories: Double = 0,
        exerciseMinutes: Int = 0,
        standHours: Int = 0,
        flightsClimbed: Int = 0,
        distanceKm: Double = 0,
        mindfulMinutes: Int = 0,
        vo2Max: Double? = nil,
        heartRateAvg: Double? = nil,
        heartRateResting: Double? = nil,
        hrv: Double? = nil,
        spO2: Double? = nil,
        respiratoryRate: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.steps = steps
        self.activeCalories = activeCalories
        self.restingCalories = restingCalories
        self.exerciseMinutes = exerciseMinutes
        self.standHours = standHours
        self.flightsClimbed = flightsClimbed
        self.distanceKm = distanceKm
        self.mindfulMinutes = mindfulMinutes
        self.vo2Max = vo2Max
        self.heartRateAvg = heartRateAvg
        self.heartRateResting = heartRateResting
        self.hrv = hrv
        self.spO2 = spO2
        self.respiratoryRate = respiratoryRate
    }

    public var totalCalories: Double { activeCalories + restingCalories }

    public func stepsProgress(goal: Int) -> Double {
        guard goal > 0 else { return 0 }
        return min(Double(steps) / Double(goal), 1.0)
    }
}

// MARK: - PersonalRecord
public struct PersonalRecord: Identifiable, Codable {
    public let id: UUID
    public let exerciseName: String
    public let weightKg: Double
    public let reps: Int
    public let achievedDate: Date
    public let estimatedOneRepMax: Double

    public init(
        id: UUID = UUID(),
        exerciseName: String,
        weightKg: Double,
        reps: Int,
        achievedDate: Date
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.weightKg = weightKg
        self.reps = reps
        self.achievedDate = achievedDate
        self.estimatedOneRepMax = weightKg * (1 + Double(reps) / 30.0)
    }
}

// MARK: - Heart Rate Data (workout detail)

public struct HRSample: Identifiable, Sendable {
    public let id = UUID()
    public let date: Date
    public let bpm: Double
    public init(date: Date, bpm: Double) { self.date = date; self.bpm = bpm }
}

public struct HRZones {
    public let z1: Double; public let z2: Double; public let z3: Double
    public let z4: Double; public let z5: Double
    public var total: Double { z1 + z2 + z3 + z4 + z5 }
    public init(z1: Double = 0, z2: Double = 0, z3: Double = 0, z4: Double = 0, z5: Double = 0) {
        self.z1 = z1; self.z2 = z2; self.z3 = z3; self.z4 = z4; self.z5 = z5
    }
    public static func calculate(from samples: [HRSample], maxHR: Double = 190) -> HRZones {
        let sorted = samples.sorted { $0.date < $1.date }
        var z = (0.0, 0.0, 0.0, 0.0, 0.0)
        for i in 0..<max(0, sorted.count - 1) {
            let dt = min(max(sorted[i+1].date.timeIntervalSince(sorted[i].date), 0), 60)
            let pct = sorted[i].bpm / maxHR
            if pct < 0.60 { z.0 += dt } else if pct < 0.70 { z.1 += dt }
            else if pct < 0.80 { z.2 += dt } else if pct < 0.90 { z.3 += dt }
            else { z.4 += dt }
        }
        return HRZones(z1: z.0, z2: z.1, z3: z.2, z4: z.3, z5: z.4)
    }
}

public struct WorkoutHeartRateData {
    public let samples: [HRSample]
    public let avgBPM: Double
    public let maxBPM: Double
    public let minBPM: Double
    public let zones: HRZones
    public init(samples: [HRSample], maxHR: Double = 190) {
        self.samples = samples
        let bpms = samples.map(\.bpm)
        avgBPM = bpms.isEmpty ? 0 : bpms.reduce(0, +) / Double(bpms.count)
        maxBPM = bpms.max() ?? 0; minBPM = bpms.min() ?? 0
        zones = HRZones.calculate(from: samples, maxHR: maxHR)
    }
}

// MARK: - DailySnapshot (usato da Widget e Watch)
/// Struttura leggera per Widget e Watch — tutto in un unico oggetto
public struct DailySnapshot: Codable {
    public let date: Date
    public let calories: Double
    public let calorieGoal: Double
    public let protein: Double
    public let proteinGoal: Double
    public let carbs: Double
    public let carbsGoal: Double
    public let fat: Double
    public let fatGoal: Double
    public let fiber: Double
    public let fiberGoal: Double
    public let waterMl: Double
    public let waterGoal: Double
    public let steps: Int
    public let stepGoal: Int
    // Walking companions to the step count, Apple Health style. Optional so
    // snapshots cached by older builds still decode (missing key → nil)
    // instead of failing and falling back to placeholder numbers.
    public let distanceKm: Double?
    public let flightsClimbed: Int?
    public let activeCalories: Double
    public let activeCalorieGoal: Double
    public let sleepHours: Double
    public let sleepScore: Int
    public let dayScore: Int          // Score composito 0-100
    public let hasWorkedOutToday: Bool
    // Score breakdown (max values in parentheses)
    public let movementScore: Double  // 0-40
    public let recoveryScore: Double  // 0-30
    public let nutritionScore: Double // 0-20
    public let workoutBonus: Double   // 0-10

    public init(
        date: Date = .now,
        calories: Double = 0,
        calorieGoal: Double = 2200,
        protein: Double = 0,
        proteinGoal: Double = 160,
        carbs: Double = 0,
        carbsGoal: Double = 220,
        fat: Double = 0,
        fatGoal: Double = 70,
        fiber: Double = 0,
        fiberGoal: Double = 30,
        waterMl: Double = 0,
        waterGoal: Double = 2500,
        steps: Int = 0,
        stepGoal: Int = 10000,
        distanceKm: Double? = nil,
        flightsClimbed: Int? = nil,
        activeCalories: Double = 0,
        activeCalorieGoal: Double = 600,
        sleepHours: Double = 0,
        sleepScore: Int = 0,
        dayScore: Int = 0,
        hasWorkedOutToday: Bool = false,
        movementScore: Double = 0,
        recoveryScore: Double = 15,
        nutritionScore: Double = 10,
        workoutBonus: Double = 0
    ) {
        self.date = date
        self.calories = calories
        self.calorieGoal = calorieGoal
        self.protein = protein
        self.proteinGoal = proteinGoal
        self.carbs = carbs
        self.carbsGoal = carbsGoal
        self.fat = fat
        self.fatGoal = fatGoal
        self.fiber = fiber
        self.fiberGoal = fiberGoal
        self.waterMl = waterMl
        self.waterGoal = waterGoal
        self.steps = steps
        self.stepGoal = stepGoal
        self.distanceKm = distanceKm
        self.flightsClimbed = flightsClimbed
        self.activeCalories = activeCalories
        self.activeCalorieGoal = activeCalorieGoal
        self.sleepHours = sleepHours
        self.sleepScore = sleepScore
        self.dayScore = dayScore
        self.hasWorkedOutToday = hasWorkedOutToday
        self.movementScore = movementScore
        self.recoveryScore = recoveryScore
        self.nutritionScore = nutritionScore
        self.workoutBonus = workoutBonus
    }

    public static var placeholder: DailySnapshot {
        DailySnapshot(
            calories: 1640, calorieGoal: 2200,
            protein: 142, proteinGoal: 160,
            carbs: 180, carbsGoal: 220,
            fat: 58, fatGoal: 70,
            fiber: 22, fiberGoal: 30,
            waterMl: 1800, waterGoal: 2500,
            steps: 7200, stepGoal: 10000,
            distanceKm: 5.4, flightsClimbed: 8,
            activeCalories: 420,
            sleepHours: 7.2, sleepScore: 74,
            dayScore: 78,
            hasWorkedOutToday: true,
            movementScore: 28, recoveryScore: 22, nutritionScore: 18, workoutBonus: 10
        )
    }
}
