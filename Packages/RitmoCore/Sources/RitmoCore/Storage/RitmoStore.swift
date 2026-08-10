import Foundation
import SwiftData

// MARK: - RitmoStore
/// Configurazione SwiftData, solo locale.
///
/// Niente CloudKit — deliberatamente. Quasi tutto ciò che sta in questo store
/// deriva da Apple Salute (le sessioni importate portano `hkWorkoutUUID`), e le
/// regole di App Review vietano di conservare dati sanitari su iCloud. I dati
/// che contano seguono comunque l'utente: gli allenamenti perché è Apple Salute
/// stessa a sincronizzarli tra i dispositivi, e Hevy perché si reimporta.
public enum RitmoStore {

    private static let schema = Schema([
        WorkoutSession.self,
        WorkoutSet.self,
        Exercise.self,
        UserGoals.self,
        RaceResult.self
    ])

    /// Container principale — su disco, nessuna sincronizzazione.
    public static var container: ModelContainer = {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    /// Container in-memory per Preview e test
    @MainActor
    public static var previewContainer: ModelContainer = {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        SampleData.populate(container: container)
        return container
    }()
}

// MARK: - SampleData
/// Dati di esempio per Preview Xcode
public enum SampleData {
    @MainActor
    public static func populate(container: ModelContainer) {
        let ctx = container.mainContext

        // Obiettivi utente
        let goals = UserGoals(
            dailyCalories: 2200,
            dailyProteinG: 160,
            dailyCarbsG: 220,
            dailyFatG: 70,
            dailyFiberG: 30,
            dailyWaterMl: 2500,
            weeklyWorkouts: 4,
            dailySteps: 10000
        )
        ctx.insert(goals)

        // Esercizi campione
        let benchPress = Exercise(name: "Panca Piana", muscleGroup: .chest, exerciseType: .weightReps)
        let squat = Exercise(name: "Squat", muscleGroup: .quads, exerciseType: .weightReps)
        let deadlift = Exercise(name: "Stacco", muscleGroup: .back, exerciseType: .weightReps)
        let pullUp = Exercise(name: "Trazioni", muscleGroup: .back, exerciseType: .bodyweightReps)
        ctx.insert(benchPress)
        ctx.insert(squat)
        ctx.insert(deadlift)
        ctx.insert(pullUp)

        // Sessione allenamento campione
        let session = WorkoutSession(
            title: "Push Day",
            startTime: Calendar.current.date(byAdding: .hour, value: -2, to: .now)!,
            endTime: Date.now,
            source: .manual
        )
        ctx.insert(session)

        let set1 = WorkoutSet(setIndex: 0, setType: .normal, weightKg: 80, reps: 8)
        let set2 = WorkoutSet(setIndex: 1, setType: .normal, weightKg: 85, reps: 6)
        let set3 = WorkoutSet(setIndex: 2, setType: .failure, weightKg: 90, reps: 5, rpe: 9.5)
        set1.exercise = benchPress
        set2.exercise = benchPress
        set3.exercise = benchPress
        set1.session = session
        set2.session = session
        set3.session = session
        ctx.insert(set1)
        ctx.insert(set2)
        ctx.insert(set3)

        try? ctx.save()
    }
}
