import Foundation
import SwiftData

// MARK: - WorkoutSession
@Model
public final class WorkoutSession {
    public var id: UUID
    public var title: String
    public var startTime: Date
    public var endTime: Date
    public var notes: String
    public var source: DataSource
    public var activeCalories: Double
    public var distanceMeters: Double
    public var hkActivityType: Int
    public var hkWorkoutUUID: String?
    /// User-provided Rate of Perceived Exertion (1–10). Overrides the auto effort estimate.
    public var userRPE: Int?

    @Relationship(deleteRule: .cascade)
    public var sets: [WorkoutSet]

    public init(
        id: UUID = UUID(),
        title: String,
        startTime: Date,
        endTime: Date,
        notes: String = "",
        source: DataSource = .manual,
        activeCalories: Double = 0,
        distanceMeters: Double = 0,
        hkActivityType: Int = 0,
        hkWorkoutUUID: String? = nil,
        userRPE: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.notes = notes
        self.source = source
        self.activeCalories = activeCalories
        self.distanceMeters = distanceMeters
        self.hkActivityType = hkActivityType
        self.hkWorkoutUUID = hkWorkoutUUID
        self.userRPE = userRPE
        self.sets = []
    }

    public var durationMinutes: Int {
        Int(endTime.timeIntervalSince(startTime) / 60)
    }

    public var totalVolumeKg: Double {
        sets.reduce(0) { $0 + ($1.weightKg * Double($1.reps ?? 0)) }
    }

    public var muscleGroups: [MuscleGroup] {
        Array(Set(sets.compactMap { $0.exercise?.muscleGroup })).sorted { $0.rawValue < $1.rawValue }
    }
}

// MARK: - WorkoutSet
@Model
public final class WorkoutSet {
    public var id: UUID
    public var setIndex: Int
    public var setType: SetType
    public var weightKg: Double
    public var reps: Int?
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    public var rpe: Double?
    public var exerciseNotes: String
    public var supersetId: String?

    @Relationship(inverse: \WorkoutSession.sets)
    public var session: WorkoutSession?

    @Relationship
    public var exercise: Exercise?

    public init(
        id: UUID = UUID(),
        setIndex: Int,
        setType: SetType = .normal,
        weightKg: Double = 0,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        rpe: Double? = nil,
        exerciseNotes: String = "",
        supersetId: String? = nil
    ) {
        self.id = id
        self.setIndex = setIndex
        self.setType = setType
        self.weightKg = weightKg
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.rpe = rpe
        self.exerciseNotes = exerciseNotes
        self.supersetId = supersetId
    }

    public var volume: Double { weightKg * Double(reps ?? 0) }
}

// MARK: - Exercise
@Model
public final class Exercise {
    public var id: UUID
    public var name: String
    public var muscleGroup: MuscleGroup
    public var exerciseType: ExerciseType

    @Relationship(inverse: \WorkoutSet.exercise)
    public var sets: [WorkoutSet]

    public init(
        id: UUID = UUID(),
        name: String,
        muscleGroup: MuscleGroup = .other,
        exerciseType: ExerciseType = .weightReps
    ) {
        self.id = id
        self.name = name
        self.muscleGroup = muscleGroup
        self.exerciseType = exerciseType
        self.sets = []
    }
}

// MARK: - UserGoals (salvati su SwiftData, sincronizzati via CloudKit)
@Model
public final class UserGoals {
    public var id: UUID
    public var dailyCalories: Double
    public var dailyProteinG: Double
    public var dailyCarbsG: Double
    public var dailyFatG: Double
    public var dailyFiberG: Double
    public var dailyWaterMl: Double
    public var weeklyWorkouts: Int
    public var dailySteps: Int
    public var dailyActiveCalories: Double

    public init(
        id: UUID = UUID(),
        dailyCalories: Double = 2200,
        dailyProteinG: Double = 160,
        dailyCarbsG: Double = 220,
        dailyFatG: Double = 70,
        dailyFiberG: Double = 30,
        dailyWaterMl: Double = 2500,
        weeklyWorkouts: Int = 4,
        dailySteps: Int = 10000,
        dailyActiveCalories: Double = 600
    ) {
        self.id = id
        self.dailyCalories = dailyCalories
        self.dailyProteinG = dailyProteinG
        self.dailyCarbsG = dailyCarbsG
        self.dailyFatG = dailyFatG
        self.dailyFiberG = dailyFiberG
        self.dailyWaterMl = dailyWaterMl
        self.weeklyWorkouts = weeklyWorkouts
        self.dailySteps = dailySteps
        self.dailyActiveCalories = dailyActiveCalories
    }
}

// MARK: - UserGoals WatchConnectivity helpers

extension UserGoals {
    public var syncPayload: [String: Any] {
        [
            "dailyCalories":       dailyCalories,
            "dailyProteinG":       dailyProteinG,
            "dailyCarbsG":         dailyCarbsG,
            "dailyFatG":           dailyFatG,
            "dailyFiberG":         dailyFiberG,
            "dailyWaterMl":        dailyWaterMl,
            "weeklyWorkouts":      weeklyWorkouts,
            "dailySteps":          dailySteps,
            "dailyActiveCalories": dailyActiveCalories
        ]
    }

    public func applySync(_ payload: [String: Any]) {
        // Read through NSNumber so values survive WatchConnectivity/plist
        // bridging regardless of whether they arrive as Int or Double.
        func double(_ key: String) -> Double? { (payload[key] as? NSNumber)?.doubleValue }
        func int(_ key: String)    -> Int?    { (payload[key] as? NSNumber)?.intValue }

        if let v = double("dailyCalories")       { dailyCalories       = v }
        if let v = double("dailyProteinG")       { dailyProteinG       = v }
        if let v = double("dailyCarbsG")         { dailyCarbsG         = v }
        if let v = double("dailyFatG")           { dailyFatG           = v }
        if let v = double("dailyFiberG")         { dailyFiberG         = v }
        if let v = double("dailyWaterMl")        { dailyWaterMl        = v }
        if let v = int("weeklyWorkouts")         { weeklyWorkouts      = v }
        if let v = int("dailySteps")             { dailySteps          = v }
        if let v = double("dailyActiveCalories") { dailyActiveCalories = v }
    }

    /// Returns the single canonical `UserGoals`, creating one if none exists and
    /// removing any duplicates (CloudKit sync + WatchConnectivity can introduce them).
    /// This guarantees a deterministic record for both scoring and goal display.
    @MainActor
    public static func canonical(in context: ModelContext) -> UserGoals {
        let all = (try? context.fetch(FetchDescriptor<UserGoals>())) ?? []
        guard let survivor = all.first else {
            let fresh = UserGoals()
            context.insert(fresh)
            return fresh
        }
        for duplicate in all.dropFirst() { context.delete(duplicate) }
        return survivor
    }
}

// MARK: - Enums
public enum DataSource: String, Codable {
    case healthKit = "Apple Health"
    case manual = "Manuale"
}

public enum SetType: String, Codable, CaseIterable {
    case normal = "normal"
    case warmup = "warmup"
    case dropSet = "drop_set"
    case failure = "failure"

    public var displayName: String {
        switch self {
        case .normal: return "Normale"
        case .warmup: return "Riscaldamento"
        case .dropSet: return "Drop Set"
        case .failure: return "Al cedimento"
        }
    }
}

public enum ExerciseType: String, Codable, CaseIterable {
    case weightReps = "weight_reps"
    case bodyweightReps = "bodyweight_reps"
    case duration = "duration"
    case distance = "distance"
    case weightDuration = "weight_duration"

    public var displayName: String {
        switch self {
        case .weightReps: return "Peso × Reps"
        case .bodyweightReps: return "Corpo libero × Reps"
        case .duration: return "Durata"
        case .distance: return "Distanza"
        case .weightDuration: return "Peso × Durata"
        }
    }
}

public enum MuscleGroup: String, Codable, CaseIterable, Hashable {
    case chest = "Petto"
    case back = "Schiena"
    case shoulders = "Spalle"
    case biceps = "Bicipiti"
    case triceps = "Tricipiti"
    case forearms = "Avambracci"
    case core = "Core"
    case quads = "Quadricipiti"
    case hamstrings = "Femorali"
    case glutes = "Glutei"
    case calves = "Polpacci"
    case fullBody = "Full Body"
    case cardio = "Cardio"
    case other = "Altro"

    public var icon: String {
        switch self {
        case .chest: return "❤️"
        case .back: return "🏋️"
        case .shoulders: return "🔝"
        case .biceps: return "💪"
        case .triceps: return "💪"
        case .forearms: return "🤜"
        case .core: return "⭕"
        case .quads: return "🦵"
        case .hamstrings: return "🦵"
        case .glutes: return "🍑"
        case .calves: return "🦶"
        case .fullBody: return "🧍"
        case .cardio: return "❤️‍🔥"
        case .other: return "❓"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .chest: return "heart.fill"
        case .back: return "figure.strengthtraining.traditional"
        case .shoulders: return "arrow.up.circle.fill"
        case .biceps, .triceps, .forearms: return "hand.raised.fill"
        case .core: return "circle.fill"
        case .quads, .hamstrings, .glutes, .calves: return "figure.run"
        case .fullBody: return "person.fill"
        case .cardio: return "heart.circle.fill"
        case .other: return "questionmark.circle"
        }
    }
}
