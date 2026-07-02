import Foundation
import SwiftData

// MARK: - ExerciseCatalog
//
// Seed list of common gym exercises (Italian names, consistent with the rest
// of the app's base language) so the exercise picker isn't empty on first use.
// Seeding is idempotent by name: user-created exercises and renames survive.

public enum ExerciseCatalog {

    public static let seed: [(name: String, group: MuscleGroup, type: ExerciseType)] = [
        // Petto
        ("Panca piana",            .chest, .weightReps),
        ("Panca inclinata",        .chest, .weightReps),
        ("Panca con manubri",      .chest, .weightReps),
        ("Croci ai cavi",          .chest, .weightReps),
        ("Chest press",            .chest, .weightReps),
        ("Piegamenti",             .chest, .bodyweightReps),
        // Schiena
        ("Trazioni",               .back, .bodyweightReps),
        ("Lat machine",            .back, .weightReps),
        ("Rematore bilanciere",    .back, .weightReps),
        ("Rematore manubrio",      .back, .weightReps),
        ("Pulley basso",           .back, .weightReps),
        ("Stacco da terra",        .back, .weightReps),
        // Spalle
        ("Military press",         .shoulders, .weightReps),
        ("Lento con manubri",      .shoulders, .weightReps),
        ("Alzate laterali",        .shoulders, .weightReps),
        ("Alzate frontali",        .shoulders, .weightReps),
        ("Face pull",              .shoulders, .weightReps),
        // Bicipiti
        ("Curl bilanciere",        .biceps, .weightReps),
        ("Curl manubri",           .biceps, .weightReps),
        ("Curl a martello",        .biceps, .weightReps),
        ("Panca Scott",            .biceps, .weightReps),
        // Tricipiti
        ("French press",           .triceps, .weightReps),
        ("Pushdown ai cavi",       .triceps, .weightReps),
        ("Dip",                    .triceps, .bodyweightReps),
        ("Estensioni sopra la testa", .triceps, .weightReps),
        // Gambe
        ("Squat",                  .quads, .weightReps),
        ("Leg press",              .quads, .weightReps),
        ("Leg extension",          .quads, .weightReps),
        ("Affondi",                .quads, .weightReps),
        ("Squat bulgaro",          .quads, .weightReps),
        ("Leg curl",               .hamstrings, .weightReps),
        ("Stacco rumeno",          .hamstrings, .weightReps),
        ("Good morning",           .hamstrings, .weightReps),
        ("Hip thrust",             .glutes, .weightReps),
        ("Ponte glutei",           .glutes, .weightReps),
        ("Calf raise in piedi",    .calves, .weightReps),
        ("Calf raise seduto",      .calves, .weightReps),
        // Core
        ("Crunch",                 .core, .bodyweightReps),
        ("Plank",                  .core, .duration),
        ("Russian twist",          .core, .weightReps),
        ("Leg raise",              .core, .bodyweightReps),
        // Full body
        ("Clean & press",          .fullBody, .weightReps),
        ("Kettlebell swing",       .fullBody, .weightReps),
        ("Burpees",                .fullBody, .bodyweightReps)
    ]

    /// Inserts any seed exercise not already present (matched by name, so user
    /// edits/additions are never duplicated or overwritten). Safe to call on
    /// every picker appearance.
    @MainActor
    public static func ensureSeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let existingNames = Set(existing.map { $0.name.lowercased() })
        var inserted = false
        for item in seed where !existingNames.contains(item.name.lowercased()) {
            context.insert(Exercise(name: item.name, muscleGroup: item.group, exerciseType: item.type))
            inserted = true
        }
        if inserted { try? context.save() }
    }
}
