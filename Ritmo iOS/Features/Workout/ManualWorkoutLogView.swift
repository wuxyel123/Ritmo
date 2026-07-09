import SwiftUI
import SwiftData
import RitmoCore

// MARK: - ManualWorkoutLogView
//
// Editor for manually-logged strength workouts (source .manual, activity type
// traditionalStrengthTraining so the session counts as .strength for training
// load). Edits happen on local value types; SwiftData is only touched on save,
// so cancelling never leaves half-written sets behind.
//
// On save the workout is ALSO written to Apple Health (Ritmo owns the record
// and stores its UUID on the session, so the importer never duplicates it) —
// that's what makes it count for the day score, the rings, and the watch.
// Sets/reps stay in the app's own store; HealthKit has no concept of them.

struct ManualWorkoutLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var healthRepo: HealthKitRepository

    var existing: WorkoutSession? = nil
    var onSaved: (() -> Void)? = nil

    @State private var title = "Allenamento pesi"
    @State private var start = Date.now.addingTimeInterval(-3600)
    @State private var end = Date.now
    @State private var rpe = 7
    @State private var entries: [ExerciseEntry] = []
    @State private var showingPicker = false

    struct ExerciseEntry: Identifiable {
        let id = UUID()
        var exercise: Exercise
        var sets: [SetEntry]
        var notes: String = ""
    }

    struct SetEntry: Identifiable {
        let id = UUID()
        var weightKg: Double = 0
        var reps: Int = 8
        var seconds: Int = 30
        var type: SetType = .normal
    }

    private var durationMinutes: Int { max(Int(end.timeIntervalSince(start) / 60), 0) }
    private var totalVolume: Double {
        entries.reduce(0.0) { total, entry in
            total + entry.sets.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Info
                Section {
                    TextField("Titolo", text: $title)
                    DatePicker("Inizio", selection: $start)
                    DatePicker("Fine", selection: $end, in: start...)
                    HStack {
                        Text("Durata")
                        Spacer()
                        Text("\(durationMinutes) min")
                            .foregroundStyle(RitmoTheme.textSecondary)
                    }
                } header: { Text("Allenamento") }

                // MARK: RPE
                Section {
                    Picker(selection: $rpe) {
                        ForEach(1...10, id: \.self) { v in
                            Text("\(v)").tag(v)
                        }
                    } label: {
                        Label("RPE (sforzo percepito)", systemImage: "gauge.with.needle")
                    }
                } footer: {
                    Text("1 = leggerissimo · 10 = massimale. Determina il carico di allenamento.")
                }

                // MARK: Exercises
                ForEach($entries) { $entry in
                    Section {
                        ForEach($entry.sets) { $set in
                            setRow(for: $set, type: entry.exercise.exerciseType)
                        }
                        .onDelete { offsets in
                            entry.sets.remove(atOffsets: offsets)
                        }
                        Button {
                            entry.sets.append(entry.sets.last ?? SetEntry())
                        } label: {
                            Label("Aggiungi serie", systemImage: "plus.circle")
                                .font(.subheadline)
                        }
                        TextField("Note esercizio", text: $entry.notes, axis: .vertical)
                            .font(.caption)
                            .lineLimit(1...3)
                    } header: {
                        HStack {
                            Text(entry.exercise.name)
                            Spacer()
                            Button {
                                entries.removeAll { $0.id == entry.id }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                        }
                    }
                }

                Section {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Aggiungi esercizio", systemImage: "plus")
                    }
                    if totalVolume > 0 {
                        HStack {
                            Text("Volume totale")
                            Spacer()
                            Text(String(format: "%.0f kg", totalVolume))
                                .foregroundStyle(RitmoTheme.textSecondary)
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Nuovo allenamento" : "Modifica allenamento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }
                        .disabled(end <= start)
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView { exercise in
                    entries.append(ExerciseEntry(exercise: exercise, sets: [SetEntry()]))
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    // MARK: Set row

    @ViewBuilder
    private func setRow(for set: Binding<SetEntry>, type: ExerciseType) -> some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(SetType.allCases, id: \.self) { t in
                    Button(t.displayName) { set.wrappedValue.type = t }
                }
            } label: {
                Text(setTypeShort(set.wrappedValue.type))
                    .font(.caption.bold())
                    .frame(width: 26, height: 26)
                    .background(setTypeColor(set.wrappedValue.type).opacity(0.15), in: Circle())
                    .foregroundStyle(setTypeColor(set.wrappedValue.type))
            }

            switch type {
            case .duration:
                TextField("sec", value: set.seconds, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                Text("sec").foregroundStyle(RitmoTheme.textSecondary).font(.caption)
            case .bodyweightReps:
                TextField("reps", value: set.reps, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                Text("reps").foregroundStyle(RitmoTheme.textSecondary).font(.caption)
            default:
                TextField("kg", value: set.weightKg, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text("kg ×").foregroundStyle(RitmoTheme.textSecondary).font(.caption)
                TextField("reps", value: set.reps, format: .number)
                    .keyboardType(.numberPad)
                    .frame(width: 44)
                Text("reps").foregroundStyle(RitmoTheme.textSecondary).font(.caption)
            }
        }
    }

    private func setTypeShort(_ t: SetType) -> String {
        switch t {
        case .normal:  return "N"
        case .warmup:  return "R"
        case .dropSet: return "D"
        case .failure: return "C"
        }
    }

    private func setTypeColor(_ t: SetType) -> Color {
        switch t {
        case .normal:  return RitmoTheme.accent
        case .warmup:  return .orange
        case .dropSet: return .purple
        case .failure: return .red
        }
    }

    // MARK: Load / save

    private func loadExisting() {
        guard let existing, entries.isEmpty else { return }
        title = existing.title
        start = existing.startTime
        end = existing.endTime
        rpe = existing.userRPE ?? existing.autoEffort

        // Rebuild entries grouped by exercise, preserving first-seen order.
        var ordered: [ExerciseEntry] = []
        for set in existing.sets.sorted(by: { $0.setIndex < $1.setIndex }) {
            guard let exercise = set.exercise else { continue }
            let entry = SetEntry(weightKg: set.weightKg,
                                 reps: set.reps ?? 0,
                                 seconds: set.durationSeconds ?? 0,
                                 type: set.setType)
            if let i = ordered.firstIndex(where: { $0.exercise.id == exercise.id }) {
                ordered[i].sets.append(entry)
                if ordered[i].notes.isEmpty { ordered[i].notes = set.exerciseNotes }
            } else {
                ordered.append(ExerciseEntry(exercise: exercise, sets: [entry],
                                             notes: set.exerciseNotes))
            }
        }
        entries = ordered
    }

    private func save() {
        let session: WorkoutSession
        if let existing {
            session = existing
            session.title = title
            session.startTime = start
            session.endTime = end
            session.userRPE = rpe
            for old in existing.sets { modelContext.delete(old) }
            session.sets = []
        } else {
            session = WorkoutSession(title: title,
                                     startTime: start,
                                     endTime: end,
                                     source: .manual,
                                     hkActivityType: 50, // traditionalStrengthTraining → .strength
                                     userRPE: rpe)
            modelContext.insert(session)
        }

        var index = 0
        for entry in entries {
            for s in entry.sets {
                let isDuration = entry.exercise.exerciseType == .duration
                let workoutSet = WorkoutSet(setIndex: index,
                                            setType: s.type,
                                            weightKg: isDuration ? 0 : s.weightKg,
                                            reps: isDuration ? nil : (s.reps > 0 ? s.reps : nil),
                                            durationSeconds: isDuration ? s.seconds : nil,
                                            exerciseNotes: entry.notes.trimmingCharacters(in: .whitespaces))
                modelContext.insert(workoutSet)
                workoutSet.exercise = entry.exercise
                workoutSet.session = session
                index += 1
            }
        }

        try? modelContext.save()

        // Mirror to Apple Health: replace the previous record on edit (times
        // may have changed), then attach the RPE as a workout effort score.
        let rpeValue = rpe
        Task { @MainActor in
            if let oldUUID = session.hkWorkoutUUID {
                _ = await healthRepo.deleteHealthKitWorkout(uuid: oldUUID)
                session.hkWorkoutUUID = nil
            }
            if let uuid = await healthRepo.saveManualWorkout(start: session.startTime,
                                                             end: session.endTime) {
                session.hkWorkoutUUID = uuid
                await healthRepo.saveWorkoutEffort(rpe: rpeValue, forWorkoutUUID: uuid)
            }
            try? modelContext.save()
            onSaved?()
        }
        dismiss()
    }
}
