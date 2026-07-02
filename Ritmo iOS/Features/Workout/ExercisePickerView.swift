import SwiftUI
import SwiftData
import RitmoCore

// MARK: - ExercisePickerView
// Searchable catalog grouped by muscle group; picking calls back and closes.
// Custom exercises can be added inline and become part of the store.

struct ExercisePickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var showingNewExercise = false

    let onPick: (Exercise) -> Void

    private var filtered: [Exercise] {
        guard !search.isEmpty else { return exercises }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var groups: [(group: MuscleGroup, items: [Exercise])] {
        MuscleGroup.allCases.compactMap { group in
            let items = filtered.filter { $0.muscleGroup == group }
            return items.isEmpty ? nil : (group, items)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.group) { entry in
                    Section {
                        ForEach(entry.items) { exercise in
                            Button {
                                onPick(exercise)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(exercise.name).foregroundStyle(.primary)
                                    Spacer()
                                    if exercise.exerciseType != .weightReps {
                                        Text(LocalizedStringKey(exercise.exerciseType.displayName))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("\(entry.group.icon) ") + Text(LocalizedStringKey(entry.group.rawValue))
                    }
                }
            }
            .searchable(text: $search, prompt: "Cerca esercizio")
            .navigationTitle("Esercizi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNewExercise = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewExercise) {
                NewExerciseSheet { exercise in
                    onPick(exercise)
                    dismiss()
                }
                .presentationDetents([.medium])
            }
            .task { ExerciseCatalog.ensureSeeded(in: modelContext) }
        }
    }
}

// MARK: - NewExerciseSheet

private struct NewExerciseSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var group: MuscleGroup = .chest
    @State private var type: ExerciseType = .weightReps

    let onCreated: (Exercise) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome esercizio", text: $name)
                Picker("Gruppo muscolare", selection: $group) {
                    ForEach(MuscleGroup.allCases, id: \.self) { g in
                        Text(LocalizedStringKey(g.rawValue)).tag(g)
                    }
                }
                Picker("Tipo", selection: $type) {
                    ForEach(ExerciseType.allCases, id: \.self) { t in
                        Text(LocalizedStringKey(t.displayName)).tag(t)
                    }
                }
            }
            .navigationTitle("Nuovo esercizio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crea") {
                        let exercise = Exercise(name: name.trimmingCharacters(in: .whitespaces),
                                                muscleGroup: group, exerciseType: type)
                        modelContext.insert(exercise)
                        try? modelContext.save()
                        onCreated(exercise)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
