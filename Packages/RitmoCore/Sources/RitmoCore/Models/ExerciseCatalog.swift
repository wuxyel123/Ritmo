import Foundation
import SwiftData

// MARK: - ExerciseCatalog
//
// Seed list of common gym exercises (Italian names, consistent with the rest
// of the app's base language) so the exercise picker isn't empty on first use.
// Each entry carries the PRIMARY muscle group plus the SECONDARY groups the
// movement also loads. Seeding is idempotent by name: user-created exercises
// and renames survive; seed-named exercises missing their secondary groups
// get them backfilled (covers stores created before secondaries existed).

public enum ExerciseCatalog {

    public struct SeedExercise {
        public let name: String
        public let group: MuscleGroup
        public let type: ExerciseType
        public let secondary: [MuscleGroup]

        init(_ name: String, _ group: MuscleGroup, _ type: ExerciseType = .weightReps,
             _ secondary: [MuscleGroup] = []) {
            self.name = name
            self.group = group
            self.type = type
            self.secondary = secondary
        }
    }

    public static let seed: [SeedExercise] = [
        // ── Dallo storico Hevy dell'utente (2026-07-03) ──────────
        SeedExercise("Crunch", .core, .bodyweightReps),
        SeedExercise("Plank", .core, .duration, [.shoulders]),
        SeedExercise("Calf Raise Seduto", .calves),
        SeedExercise("Rematore Manubrio", .back, .weightReps, [.biceps]),
        SeedExercise("Croci ai Cavi", .chest, .weightReps, [.shoulders]),
        SeedExercise("Face Pull", .shoulders, .weightReps, [.traps, .back]),
        SeedExercise("Panca Piana (Bilanciere)", .chest, .weightReps, [.triceps, .shoulders]),
        SeedExercise("Panca Piana (Manubrio)", .chest, .weightReps, [.triceps, .shoulders]),
        SeedExercise("Panca Piana (Multipower)", .chest, .weightReps, [.triceps, .shoulders]),
        SeedExercise("Panca Piana - Presa Stretta (Bilanciere)", .triceps, .weightReps, [.chest, .shoulders]),
        SeedExercise("Panca Inclinata (Bilanciere)", .chest, .weightReps, [.shoulders, .triceps]),
        SeedExercise("Panca Inclinata (Manubrio)", .chest, .weightReps, [.shoulders, .triceps]),
        SeedExercise("Panca Inclinata (Multipower)", .chest, .weightReps, [.shoulders, .triceps]),
        SeedExercise("Panca Paralimpica", .chest, .weightReps, [.triceps]),
        SeedExercise("Panca Discesa Lenta", .chest, .weightReps, [.triceps, .shoulders]),
        SeedExercise("Bench 3 Fermi In Discesa", .chest, .weightReps, [.triceps, .shoulders]),
        SeedExercise("Panca Board Presa Stretta", .triceps, .weightReps, [.chest]),
        SeedExercise("Panca Board Stretta Elastico Medio", .triceps, .weightReps, [.chest]),
        SeedExercise("Floor Press (Bilanciere)", .chest, .weightReps, [.triceps]),
        SeedExercise("Chest Press (Macchina)", .chest, .weightReps, [.triceps, .shoulders]),
        SeedExercise("Croci (Macchina)", .chest, .weightReps, [.shoulders]),
        SeedExercise("Croci (Manubrio)", .chest, .weightReps, [.shoulders]),
        SeedExercise("Farfalla (Pec Deck)", .chest, .weightReps, [.shoulders]),
        SeedExercise("Piegamento (Con Peso Aggiunto)", .chest, .weightReps, [.triceps, .shoulders, .core]),
        SeedExercise("Trazione", .back, .bodyweightReps, [.biceps, .forearms]),
        SeedExercise("Trazione (Con Peso Aggiunto)", .back, .weightReps, [.biceps, .forearms]),
        SeedExercise("Trazione Fasce", .back, .bodyweightReps, [.biceps]),
        SeedExercise("Trazione Presa Supina", .back, .bodyweightReps, [.biceps, .forearms]),
        SeedExercise("Trazione Supina (Con Peso Aggiunto)", .back, .weightReps, [.biceps, .forearms]),
        SeedExercise("Lat Pulldown (Cavo)", .back, .weightReps, [.biceps]),
        SeedExercise("Lat Pulldown Braccia Dritte (Cavo)", .back, .weightReps, [.triceps]),
        SeedExercise("Lat Pulldown Braccio Singolo", .back, .weightReps, [.biceps]),
        SeedExercise("Lat Pulldown Presa Inversa (Cavo)", .back, .weightReps, [.biceps]),
        SeedExercise("Lat pulldown - Presa Stretta (Cavo)", .back, .weightReps, [.biceps]),
        SeedExercise("Pulldown Corda a Braccia Dritte", .back, .weightReps, [.triceps]),
        SeedExercise("Rematore Inclinato (Bilanciere)", .back, .weightReps, [.biceps, .lowerBack]),
        SeedExercise("Rematore Inclinato con Petto Appoggiato (Manubrio)", .back, .weightReps, [.biceps]),
        SeedExercise("Rematore Pendlay (Bilanciere)", .back, .weightReps, [.biceps, .lowerBack]),
        SeedExercise("Rematore Seduto (Macchina)", .back, .weightReps, [.biceps]),
        SeedExercise("Rematore T Bar", .back, .weightReps, [.biceps, .lowerBack]),
        SeedExercise("Rematore al Cavo Singolo", .back, .weightReps, [.biceps]),
        SeedExercise("Rematore al Cavo da Seduto", .back, .weightReps, [.biceps]),
        SeedExercise("Rematore Convergente (Macchina)", .back, .weightReps, [.biceps]),
        SeedExercise("Low Row", .back, .weightReps, [.biceps]),
        SeedExercise("Pulley al Cavo Tra le Gambe", .back, .weightReps, [.biceps]),
        SeedExercise("Tirate al Petto (Cavo)", .shoulders, .weightReps, [.traps]),
        SeedExercise("Dead Hang", .forearms, .duration, [.back]),
        SeedExercise("Stacco da Terra (Bilanciere)", .back, .weightReps, [.hamstrings, .glutes, .lowerBack, .traps, .forearms]),
        SeedExercise("Stacco da Terra (Trap Bar)", .back, .weightReps, [.quads, .glutes, .hamstrings, .traps]),
        SeedExercise("Stacco Dai Blocchi", .back, .weightReps, [.hamstrings, .glutes, .lowerBack, .traps]),
        SeedExercise("Stacco Complex", .back, .weightReps, [.hamstrings, .glutes, .lowerBack]),
        SeedExercise("Stacco Salita 6”", .back, .weightReps, [.hamstrings, .glutes, .lowerBack]),
        SeedExercise("Deadlift fermo ginocchio", .back, .weightReps, [.hamstrings, .glutes, .lowerBack]),
        SeedExercise("Stacco da Terra Gambe Dritte", .hamstrings, .weightReps, [.glutes, .lowerBack]),
        SeedExercise("Stacco da Terra Rumena (Bilanciere)", .hamstrings, .weightReps, [.glutes, .lowerBack]),
        SeedExercise("Stacco da Terra Rumena (Manubrio)", .hamstrings, .weightReps, [.glutes, .lowerBack]),
        SeedExercise("Stacco da Terra Rumeno (Bilanciere)", .hamstrings, .weightReps, [.glutes, .lowerBack]),
        SeedExercise("Lento in Avanti (Bilanciere)", .shoulders, .weightReps, [.triceps, .traps, .core]),
        SeedExercise("Lento in Avanti (Manubrio)", .shoulders, .weightReps, [.triceps]),
        SeedExercise("Lento in Avanti (Smith Machine)", .shoulders, .weightReps, [.triceps]),
        SeedExercise("Lento in Avanti Seduto (Macchina)", .shoulders, .weightReps, [.triceps]),
        SeedExercise("Shoulder Press (Machine Plates)", .shoulders, .weightReps, [.triceps]),
        SeedExercise("Arnold Press (Manubrio)", .shoulders, .weightReps, [.triceps]),
        SeedExercise("Alzate Laterali (Cavo)", .shoulders, .weightReps, [.traps]),
        SeedExercise("Aperture Laterali (Manubrio)", .shoulders, .weightReps, [.traps]),
        SeedExercise("Alzata Frontale (Bilanciere)", .shoulders),
        SeedExercise("Lu Shoulders", .shoulders, .weightReps, [.traps]),
        SeedExercise("Croci Inverse Appoggiato (Manubrio)", .shoulders, .weightReps, [.back, .traps]),
        SeedExercise("Scrollata di Spalle (Bilanciere)", .traps, .weightReps, [.forearms]),
        SeedExercise("Curl Bicipiti (Cavo)", .biceps, .weightReps, [.forearms]),
        SeedExercise("Curl Bicipiti (Manubrio)", .biceps, .weightReps, [.forearms]),
        SeedExercise("Curl Bicipiti Inclinato da Seduto (Manubrio)", .biceps),
        SeedExercise("Curl Bicipiti con Corda", .biceps, .weightReps, [.forearms]),
        SeedExercise("Curl Bicipiti con EZ Bar", .biceps, .weightReps, [.forearms]),
        SeedExercise("Bicipiti Cavo Doppio", .biceps),
        SeedExercise("Bicipiti Martello (Cavo)", .biceps, .weightReps, [.forearms]),
        SeedExercise("Bicipiti Martello (Manubrio)", .biceps, .weightReps, [.forearms]),
        SeedExercise("Bicipiti Martello Incrociato", .biceps, .weightReps, [.forearms]),
        SeedExercise("Curl Martello Cintura", .biceps, .weightReps, [.forearms]),
        SeedExercise("Concentration Curl", .biceps),
        SeedExercise("Preacher Curl (Bilanciere)", .biceps, .weightReps, [.forearms]),
        SeedExercise("Preacher Curl (Manubrio)", .biceps, .weightReps, [.forearms]),
        SeedExercise("Zottman Curl (Manubrio)", .biceps, .weightReps, [.forearms]),
        SeedExercise("Curl Invertito (Manubrio)", .forearms, .weightReps, [.biceps]),
        SeedExercise("Pronated Curl", .forearms, .weightReps, [.biceps]),
        SeedExercise("Curl dal Ginocchio", .biceps),
        SeedExercise("Dip Tricipiti", .triceps, .bodyweightReps, [.chest, .shoulders]),
        SeedExercise("Dip Tricipiti (Con Peso Aggiunto)", .triceps, .weightReps, [.chest, .shoulders]),
        SeedExercise("Dip su Panca", .triceps, .bodyweightReps, [.chest, .shoulders]),
        SeedExercise("Skullcrusher (Bilanciere)", .triceps),
        SeedExercise("Skullcrusher (Manubrio)", .triceps),
        SeedExercise("JM Press (Barbell)", .triceps, .weightReps, [.chest, .shoulders]),
        SeedExercise("Estensione Tricipiti (Cavo)", .triceps),
        SeedExercise("Estensione Tricipiti (Macchina)", .triceps),
        SeedExercise("Estensione Tricipiti (Manubrio)", .triceps),
        SeedExercise("Estensione dei tricipiti con cavo a braccio singolo", .triceps),
        SeedExercise("Estensione dei tricipiti sopra la testa (cavo)", .triceps),
        SeedExercise("Overhead Triceps Extension (Cable)", .triceps),
        SeedExercise("Single Arm Triceps Pushdown (Cable)", .triceps),
        SeedExercise("Pushdown Tricipiti", .triceps),
        SeedExercise("Pushdown Tricipiti con Corda", .triceps),
        SeedExercise("Pushdown Tricipiti Panca Inclinata", .triceps),
        SeedExercise("Distensioni Tricipiti", .triceps),
        SeedExercise("Squat (Bilanciere)", .quads, .weightReps, [.glutes, .hamstrings, .lowerBack, .core]),
        SeedExercise("Squat (Multipower)", .quads, .weightReps, [.glutes, .hamstrings]),
        SeedExercise("Box Squat (Bilanciere)", .quads, .weightReps, [.glutes, .hamstrings]),
        SeedExercise("Pause Squat (Barbell)", .quads, .weightReps, [.glutes, .hamstrings, .core]),
        SeedExercise("SQUAT 3 fermi in discesa", .quads, .weightReps, [.glutes, .hamstrings, .core]),
        SeedExercise("Squat Discesa Lenta", .quads, .weightReps, [.glutes, .hamstrings]),
        SeedExercise("Sumo Squat (Bilanciere)", .quads, .weightReps, [.glutes, .adductors]),
        SeedExercise("Hack Squat (Macchina)", .quads, .weightReps, [.glutes]),
        SeedExercise("Pendulum Squat (Machine)", .quads, .weightReps, [.glutes]),
        SeedExercise("Belt squat", .quads, .weightReps, [.glutes]),
        SeedExercise("Leg Press (Macchina)", .quads, .weightReps, [.glutes, .hamstrings]),
        SeedExercise("Leg Press Orizzontale (Macchina)", .quads, .weightReps, [.glutes, .hamstrings]),
        SeedExercise("Leg Press Gamba Singola (Macchina)", .quads, .weightReps, [.glutes]),
        SeedExercise("Leg Extension (Macchina)", .quads),
        SeedExercise("Leg Extensions Gamba Singola", .quads),
        SeedExercise("Affondi (Manubrio)", .quads, .weightReps, [.glutes, .hamstrings]),
        SeedExercise("Affondo Bulgaro", .quads, .weightReps, [.glutes, .hamstrings]),
        SeedExercise("Hatfield Split Squat", .quads, .weightReps, [.glutes]),
        SeedExercise("Step Up Manubrio", .quads, .weightReps, [.glutes]),
        SeedExercise("Leg Curl Sdraiato (Macchina)", .hamstrings),
        SeedExercise("Leg Curl Seduto (Macchina)", .hamstrings),
        SeedExercise("Nordic Curls Femorali", .hamstrings, .bodyweightReps, [.glutes]),
        SeedExercise("Good Morning (Bilanciere)", .hamstrings, .weightReps, [.lowerBack, .glutes]),
        SeedExercise("Hip Thrust (Bilanciere)", .glutes, .weightReps, [.hamstrings]),
        SeedExercise("Ipertensione Inversa", .glutes, .bodyweightReps, [.lowerBack, .hamstrings]),
        SeedExercise("Estensione Dorso (Ipertensione con Peso)", .lowerBack, .weightReps, [.glutes, .hamstrings]),
        SeedExercise("Hyper Hold", .lowerBack, .duration, [.glutes]),
        SeedExercise("Abduzione Anche (Macchina)", .abductors, .weightReps, [.glutes]),
        SeedExercise("Adduzione Anche (Macchina)", .adductors),
        SeedExercise("Calf Press (Macchina)", .calves),
        SeedExercise("Cable Crunch", .core),
        SeedExercise("Cable Twist (da Sotto a Sopra)", .core),
        SeedExercise("Crunch (Con Peso Aggiunto)", .core),
        SeedExercise("Crunch Declinato", .core, .bodyweightReps),
        SeedExercise("Crunch Declinato (Con Peso Aggiunto)", .core),
        SeedExercise("Crunch Inverso", .core, .bodyweightReps),
        SeedExercise("Curl Up", .core, .bodyweightReps),
        SeedExercise("Dead Bug", .core, .bodyweightReps),
        SeedExercise("Bird Dog", .core, .bodyweightReps, [.lowerBack]),
        SeedExercise("Sit Up", .core, .bodyweightReps),
        SeedExercise("Sit Up (Con Peso Aggiunto)", .core),
        SeedExercise("Sit Up Zavorrato", .core),
        SeedExercise("Leg Raise Appeso", .core, .bodyweightReps, [.forearms]),
        SeedExercise("Addominali Bicicletta", .core, .bodyweightReps),
        SeedExercise("Tocco Talloni", .core, .bodyweightReps),
        SeedExercise("Roll Back Obliques", .core, .bodyweightReps),
        SeedExercise("Hollow Rotazione Gambe", .core, .bodyweightReps),
        SeedExercise("Ruota Addominali", .core, .bodyweightReps, [.shoulders, .lowerBack]),
        SeedExercise("Pallof Press", .core),
        SeedExercise("Pallof Press Iso", .core, .duration),
        SeedExercise("Plank Inverso", .core, .duration, [.glutes]),
        SeedExercise("Plank Laterale", .core, .duration),
        SeedExercise("Plank Zavorrato", .core, .weightDuration, [.shoulders]),
        SeedExercise("Russian Twist (Con Peso Aggiunto)", .core),
        SeedExercise("Spiderman", .core, .bodyweightReps, [.shoulders]),
        SeedExercise("Farmers Walk", .fullBody, .distance, [.forearms, .traps, .core]),
        SeedExercise("Pinch Plate Hold", .forearms, .duration, [.traps])
    ]

    /// Old generic seeds (pre-Hevy vocabulary, retired 2026-07-03): removed
    /// from stores when unused. Exercises with recorded sets are kept — they
    /// carry history. Case-insensitive.
    static let retiredNames: Set<String> = [
        "panca piana", "panca inclinata", "panca declinata", "panca con manubri",
        "croci con manubri", "chest press", "pullover", "piegamenti", "trazioni",
        "lat machine", "rematore bilanciere", "t-bar row", "pulley basso",
        "stacco da terra", "scrollate", "iperestensioni", "military press",
        "arnold press", "lento con manubri", "alzate laterali", "alzate frontali",
        "alzate posteriori", "curl bilanciere", "curl manubri", "curl a martello",
        "curl concentrato", "panca scott", "french press", "pushdown ai cavi",
        "dip", "estensioni sopra la testa", "squat", "front squat", "leg press",
        "leg extension", "affondi", "squat bulgaro", "pistol squat", "leg curl",
        "stacco rumeno", "good morning", "nordic curl", "hip thrust",
        "ponte glutei", "abductor machine", "adductor machine",
        "calf raise in piedi", "side plank", "russian twist", "leg raise",
        "mountain climber", "clean & press", "kettlebell swing", "farmer's walk",
        "burpees", "thruster",
        // typo'd originals, replaced by corrected seeds
        "hatsfield split squat", "curl dal ginocchio"
    ]

    /// Historic-title aliases (lowercased) → canonical seed name, so imports
    /// still carrying the old spelling attach to the corrected exercise.
    public static let nameAliases: [String: String] = [
        "hatsfield split squat": "Hatfield Split Squat",
        "curl dal ginocchio": "Curl dal Ginocchio"
    ]

    public static func canonicalName(_ name: String) -> String {
        nameAliases[name.lowercased()] ?? name
    }

    /// Inserts any seed exercise not already present (matched by name, so user
    /// edits/additions are never duplicated or overwritten), backfills
    /// secondary groups on seed-named exercises that predate them, and retires
    /// unused pre-Hevy seeds. Safe to call on every picker appearance.
    @MainActor
    public static func ensureSeeded(in context: ModelContext) {
        var existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []

        var changed = false
        for e in existing where retiredNames.contains(e.name.lowercased()) && e.sets.isEmpty {
            context.delete(e)
            changed = true
        }
        existing.removeAll { retiredNames.contains($0.name.lowercased()) && $0.sets.isEmpty }

        var byName: [String: Exercise] = [:]
        for e in existing { byName[e.name.lowercased()] = e }
        for item in seed {
            if let already = byName[item.name.lowercased()] {
                if already.secondaryMuscleGroups.isEmpty && !item.secondary.isEmpty {
                    already.secondaryMuscleGroups = item.secondary
                    changed = true
                }
            } else {
                context.insert(Exercise(name: item.name, muscleGroup: item.group,
                                        exerciseType: item.type,
                                        secondaryMuscleGroups: item.secondary))
                changed = true
            }
        }
        if changed { try? context.save() }
    }
}
