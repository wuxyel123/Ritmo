import SwiftUI
import RitmoCore

struct SleepLogView: View {
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @Environment(\.dismiss) private var dismiss

    var editing: SleepSession? = nil
    var onSaved: (() -> Void)?

    @State private var startTime: Date = {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        c.hour = 23; c.minute = 0
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.date(from: c)!)!
        return yesterday
    }()
    @State private var endTime: Date = {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        c.hour = 7; c.minute = 0
        return Calendar.current.date(from: c)!
    }()
    @State private var quality: SleepQuality = .buono
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saved = false

    private var durationHours: Double {
        max(0, endTime.timeIntervalSince(startTime) / 3600)
    }
    private var isValid: Bool { durationHours > 0 && durationHours <= 24 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Addormentamento", selection: $startTime,
                               displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Sveglia", selection: $endTime,
                               displayedComponents: [.date, .hourAndMinute])
                } header: {
                    Text("Orario")
                } footer: {
                    if durationHours > 0 {
                        Text(String(format: "Durata: %.1f ore", durationHours))
                    } else {
                        Text("L'ora di sveglia deve essere dopo l'addormentamento")
                            .foregroundStyle(.red)
                    }
                }

                Section("Qualità") {
                    ForEach(SleepQuality.allCases, id: \.rawValue) { q in
                        Button {
                            quality = q
                        } label: {
                            HStack {
                                Text("\(q.emoji) \(q.label)")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if quality == q {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(RitmoTheme.accent)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                }

                if let err = errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }

                if saved {
                    Section {
                        Label("Salvato in Apple Salute", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle(editing == nil ? "Registra sonno" : "Modifica sonno")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Salva") { save() }
                            .disabled(!isValid || saved)
                            .fontWeight(.semibold)
                    }
                }
            }
            .onAppear {
                if let s = editing {
                    startTime = s.startTime
                    endTime   = s.endTime
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func save() {
        errorMessage = nil
        isSaving = true
        Task {
            await healthRepo.requestAuthorization()
            do {
                if let s = editing {
                    try await healthRepo.deleteSleepSamples(from: s.startTime, to: s.endTime)
                }
                try await healthRepo.writeSleep(start: startTime, end: endTime, quality: quality)
                saved = true
                isSaving = false
                onSaved?()
                try? await Task.sleep(nanoseconds: 700_000_000)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}
