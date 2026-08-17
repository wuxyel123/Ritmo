import SwiftUI
import RitmoCore

struct SleepLogView: View {
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @Environment(\.dismiss) private var dismiss

    var editing: SleepSession? = nil
    var onSaved: (() -> Void)?

    // A night is entered as the morning you woke up plus two clock times.
    // Asking for a full date on both ends made the commonest case — to bed
    // yesterday, up today — a manual two-date exercise, and let you save a
    // "night" that ran backwards. Here the calendar day is derived: bedtime
    // later on the clock than wake time simply means the night before.
    @State private var wakeDay: Date = Calendar.current.startOfDay(for: .now)
    @State private var bedClock: Date = Self.clock(hour: 23)
    @State private var wakeClock: Date = Self.clock(hour: 7)

    private static func clock(hour: Int, minute: Int = 0) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c) ?? .now
    }

    /// Wake instant: the chosen day at the chosen wake time.
    private var endTime: Date {
        Self.combine(day: wakeDay, clock: wakeClock)
    }

    /// Bedtime on the same day, rolled back one day when that would land at or
    /// after waking — 23:00 → 07:00 is the night before, 01:00 → 07:00 is not.
    private var startTime: Date {
        let sameDay = Self.combine(day: wakeDay, clock: bedClock)
        guard sameDay < endTime else {
            return Calendar.current.date(byAdding: .day, value: -1, to: sameDay) ?? sameDay
        }
        return sameDay
    }

    private static func combine(day: Date, clock: Date) -> Date {
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: clock)
        return cal.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: day) ?? day
    }
    @State private var quality: SleepQuality = .buono
    @State private var wakeCount = 0
    @AppStorage("sleepAvgAwakeMinutes",
                store: UserDefaults(suiteName: "group.alessandrodiscalzi.com.ritmo"))
    private var avgAwakeMinutes = HealthKitRepository.defaultAwakeMinutesPerWake
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saved = false

    private var durationHours: Double {
        max(0, endTime.timeIntervalSince(startTime) / 3600)
    }
    private var isValid: Bool { durationHours > 0 && durationHours < 24 }

    /// Spelled out so the derived day is never a surprise.
    private var spanDescription: String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
        return String(format: AppLocalization.string("Da %@ a %@"),
                      f.string(from: startTime), f.string(from: endTime))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Mattina del risveglio", selection: $wakeDay,
                               displayedComponents: [.date])
                    DatePicker("Addormentamento", selection: $bedClock,
                               displayedComponents: [.hourAndMinute])
                    DatePicker("Sveglia", selection: $wakeClock,
                               displayedComponents: [.hourAndMinute])
                } header: {
                    Text("Orario")
                } footer: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(spanDescription)
                        if isValid {
                            Text(String(format: AppLocalization.string("Durata: %@ ore"),
                                        String(format: "%.1f", durationHours)))
                        } else {
                            Text("Imposta orari diversi per addormentamento e sveglia.")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    Stepper(value: $wakeCount, in: 0...10) {
                        HStack {
                            Text("Risvegli notturni")
                            Spacer()
                            Text("\(wakeCount)")
                                .font(.headline)
                                .foregroundStyle(wakeCount <= 1 ? .green
                                                 : wakeCount <= 3 ? .orange : .red)
                                .padding(.trailing, 8)
                        }
                    }
                } footer: {
                    Text(String(format: AppLocalization.string("Quante volte ti sei svegliato durante la notte: rende più preciso il punteggio di continuità. Ogni risveglio conta %@ min (modificabile in Impostazioni)."), "\(Int(avgAwakeMinutes))"))
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
                    wakeDay   = Calendar.current.startOfDay(for: s.endTime)
                    bedClock  = s.startTime
                    wakeClock = s.endTime
                    // Wakes are real awake stages now; older logs fall back
                    // to the stored count.
                    let stageWakes = s.stages.filter { $0.type == .awake }.count
                    wakeCount = stageWakes > 0 ? stageWakes
                        : (s.manualWakeCount ?? healthRepo.loadWakeCount(for: s.endTime) ?? 0)
                    if let q = healthRepo.loadSleepQuality(for: s.endTime) {
                        quality = q
                    }
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
                try await healthRepo.writeSleep(start: startTime, end: endTime,
                                                quality: quality, wakeCount: wakeCount)
                healthRepo.saveWakeCount(wakeCount, for: endTime)
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
