import SwiftUI
import SwiftData
import RitmoCore

// MARK: - Exercise UI (library, picker, editor)
//
// Three views sharing one visual language (search bar + muscle-group filter
// chips + badge rows):
// - ExercisePickerView: the same browsing UX in selection mode, used by the
//   editors and the live workout.
// - ExerciseEditorView: create/edit with primary group, MULTIPLE secondary
//   groups (chip multi-select) and the tracking method (weight×reps, reps,
//   duration, distance…).

// MARK: Shared helpers

func muscleColor(_ group: MuscleGroup) -> Color {
    switch group {
    case .chest:                    return .red
    case .back:                     return .blue
    case .shoulders:                return .orange
    case .traps:                    return .indigo
    case .biceps, .triceps, .forearms: return .purple
    case .core:                     return .yellow
    case .lowerBack:                return .brown
    case .quads, .hamstrings, .glutes, .calves,
         .abductors, .adductors:    return .green
    case .fullBody:                 return .pink
    case .cardio:                   return .mint
    case .other:                    return .gray
    }
}

private struct GroupChipsBar: View {
    @Binding var selected: MuscleGroup?
    let available: [MuscleGroup]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: "Tutti", color: RitmoTheme.accent, isOn: selected == nil) {
                    selected = nil
                }
                ForEach(available, id: \.self) { group in
                    chip(label: group.rawValue,
                         color: muscleColor(group),
                         isOn: selected == group) {
                        selected = selected == group ? nil : group
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    private func chip(label: String, color: Color, isOn: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(LocalizedStringKey(label))
                .font(.caption.bold())
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isOn ? color : color.opacity(0.12), in: Capsule())
                .foregroundStyle(isOn ? .white : color)
        }
        .buttonStyle(.plain)
    }
}

private struct ExerciseRowView: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(exercise.name).font(.subheadline.bold())
                Spacer()
                if exercise.exerciseType != .weightReps {
                    Text(LocalizedStringKey(exercise.exerciseType.displayName))
                        .font(.system(size: 9))
                        .foregroundStyle(RitmoTheme.textSecondary)
                }
            }
            HStack(spacing: 5) {
                badge(exercise.muscleGroup, primary: true)
                ForEach(exercise.secondaryMuscleGroups, id: \.self) { group in
                    badge(group, primary: false)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func badge(_ group: MuscleGroup, primary: Bool) -> some View {
        Text(LocalizedStringKey(group.rawValue))
            .font(.system(size: 9, weight: primary ? .bold : .regular))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(muscleColor(group).opacity(primary ? 0.2 : 0.1), in: Capsule())
            .foregroundStyle(muscleColor(group).opacity(primary ? 1 : 0.75))
    }
}

/// Search + chip filtering shared by library and picker.
private func filterExercises(_ all: [Exercise], search: String,
                             group: MuscleGroup?) -> [Exercise] {
    all.filter { exercise in
        if let group,
           exercise.muscleGroup != group,
           !exercise.secondaryMuscleGroups.contains(group) { return false }
        if !search.isEmpty,
           !exercise.name.localizedCaseInsensitiveContains(search) { return false }
        return true
    }
}

// MARK: - ExercisePickerView (selection mode)

struct ExercisePickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var search = ""
    @State private var groupFilter: MuscleGroup?
    @State private var creating = false

    let onPick: (Exercise) -> Void

    private var filtered: [Exercise] {
        filterExercises(exercises, search: search, group: groupFilter)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GroupChipsBar(selected: $groupFilter, available: MuscleGroup.allCases)
                List(filtered) { exercise in
                    Button {
                        onPick(exercise)
                        dismiss()
                    } label: {
                        ExerciseRowView(exercise: exercise)
                            .foregroundStyle(.primary)
                    }
                }
                .listStyle(.plain)
            }
            .searchable(text: $search, prompt: "Cerca esercizio")
            .navigationTitle("Scegli esercizio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $creating) {
                ExerciseEditorView(existing: nil) { created in
                    onPick(created)
                    dismiss()
                }
            }
            .task { ExerciseCatalog.ensureSeeded(in: modelContext) }
        }
    }
}

// MARK: - ExerciseEditorView (create + edit)

struct ExerciseEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let existing: Exercise?
    var onCreated: ((Exercise) -> Void)? = nil

    @State private var name = ""
    @State private var primary: MuscleGroup = .chest
    @State private var secondary: Set<MuscleGroup> = []
    @State private var type: ExerciseType = .weightReps

    private var selectableSecondary: [MuscleGroup] {
        MuscleGroup.allCases.filter { $0 != primary && $0 != .other }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome esercizio", text: $name)
                    Picker("Misurazione", selection: $type) {
                        ForEach(ExerciseType.allCases, id: \.self) { t in
                            Text(LocalizedStringKey(t.displayName)).tag(t)
                        }
                    }
                } header: { Text("Esercizio") }

                Section {
                    Picker("Principale", selection: $primary) {
                        ForEach(MuscleGroup.allCases, id: \.self) { g in
                            Text(LocalizedStringKey(g.rawValue)).tag(g)
                        }
                    }
                    .onChange(of: primary) { _, new in secondary.remove(new) }
                } header: { Text("Gruppo muscolare principale") }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
                              spacing: 8) {
                        ForEach(selectableSecondary, id: \.self) { group in
                            let isOn = secondary.contains(group)
                            Button {
                                if isOn { secondary.remove(group) }
                                else { secondary.insert(group) }
                            } label: {
                                Text(LocalizedStringKey(group.rawValue))
                                    .font(.caption)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(isOn ? muscleColor(group)
                                                     : muscleColor(group).opacity(0.1),
                                                in: Capsule())
                                    .foregroundStyle(isOn ? .white : muscleColor(group))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: { Text("Gruppi secondari") } footer: {
                    Text("I muscoli che l'esercizio coinvolge oltre al principale — anche più di uno.")
                }
            }
            .navigationTitle(existing == nil ? "Nuovo esercizio" : "Modifica esercizio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let existing, name.isEmpty else { return }
        name = existing.name
        primary = existing.muscleGroup
        secondary = Set(existing.secondaryMuscleGroups)
        type = existing.exerciseType
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let orderedSecondary = MuscleGroup.allCases.filter { secondary.contains($0) }
        if let existing {
            existing.name = trimmed
            existing.muscleGroup = primary
            existing.secondaryMuscleGroups = orderedSecondary
            existing.exerciseType = type
            try? modelContext.save()
        } else {
            let exercise = Exercise(name: trimmed, muscleGroup: primary,
                                    exerciseType: type,
                                    secondaryMuscleGroups: orderedSecondary)
            modelContext.insert(exercise)
            try? modelContext.save()
            onCreated?(exercise)
        }
        dismiss()
    }
}
