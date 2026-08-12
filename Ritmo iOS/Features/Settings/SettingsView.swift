import SwiftUI
import SwiftData
import AuthenticationServices
import WidgetKit
import RitmoCore

// MARK: - Macro Input Mode

enum MacroInputMode: String, CaseIterable {
    case perKg  = "g per kg corporeo"
    case total  = "grammi totali"
}

enum AutoMacro: String, CaseIterable {
    case protein = "Proteine"
    case carbs   = "Carboidrati"
    case fat     = "Grassi"
}

// MARK: - Settings Tab

struct SettingsTabView: View {
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @EnvironmentObject private var langManager: LanguageManager
    @Environment(\.modelContext) private var modelContext
    @Query private var storedGoals: [UserGoals]

    // --- inputs (two separate sets, one per mode) ---
    @State private var calories: Double = 2200
    // per-kg mode
    @State private var proteinPerKg: Double = 2.0
    @State private var fatPerKg: Double = 0.8
    @State private var carbsPerKg: Double = 3.0
    // total-gram mode
    @State private var proteinTotalG: Double = 160.0
    @State private var fatTotalG: Double = 64.0
    @State private var carbsTotalG: Double = 220.0

    @State private var fiber: Double = 25
    @State private var waterL: Double = 2.5
    @State private var steps: Double = 10000
    @State private var activeKcal: Double = 600

    @State private var inputMode: MacroInputMode = .perKg
    @State private var bodyWeightKg: Double = 80
    @State private var toastMsg: String = ""
    @State private var showToast = false

    @AppStorage("autoMacro") private var autoMacroRaw: String = AutoMacro.carbs.rawValue
    // The per-kg PREFERENCE persists separately from the resulting grams:
    // goals only store grams, and back-deriving g/kg from grams ÷ current
    // weight made the g/kg drift whenever the weight changed, instead of the
    // grams following the weight (the whole point of per-kg mode).
    @AppStorage("macroInputModeStored") private var storedInputModeRaw = ""
    @AppStorage("macroProteinPerKg") private var storedProteinPerKg = 0.0
    @AppStorage("macroFatPerKg") private var storedFatPerKg = 0.0
    @AppStorage("macroCarbsPerKg") private var storedCarbsPerKg = 0.0
    // Lives in the App Group: the repository reads it when writing awake
    // samples and when scoring continuity for manually logged nights.
    @AppStorage("sleepAvgAwakeMinutes",
                store: UserDefaults(suiteName: "group.alessandrodiscalzi.com.ritmo"))
    private var avgAwakeMinutes = HealthKitRepository.defaultAwakeMinutesPerWake
    @AppStorage("weeklyRecapNotification") private var weeklyRecapNotification = false
    @AppStorage("hevyConnected") private var hevyConnected = false
    @AppStorage("oplUsername") private var oplUsername = ""
    @AppStorage("stravaRefreshToken") private var stravaRefreshToken = ""
    @State private var shareFile: ShareFile?
    @EnvironmentObject private var pro: ProStore
    @State private var paywallFor: ProFeature?

    // --- derived ---
    var autoMacro: AutoMacro { AutoMacro(rawValue: autoMacroRaw) ?? .carbs }

    var proteinRawG: Double { inputMode == .perKg ? proteinPerKg * bodyWeightKg : proteinTotalG }
    var fatRawG:     Double { inputMode == .perKg ? fatPerKg * bodyWeightKg : fatTotalG }
    var carbsRawG:   Double { inputMode == .perKg ? carbsPerKg * bodyWeightKg : carbsTotalG }

    var proteinG: Double {
        guard autoMacro == .protein else { return proteinRawG }
        return max(0, (calories - carbsRawG * 4 - fatRawG * 9) / 4)
    }
    var fatG: Double {
        guard autoMacro == .fat else { return fatRawG }
        return max(0, (calories - proteinRawG * 4 - carbsRawG * 4) / 9)
    }
    var carbsG: Double {
        guard autoMacro == .carbs else { return carbsRawG }
        return max(0, (calories - proteinRawG * 4 - fatRawG * 9) / 4)
    }
    var macrosOk: Bool { proteinG >= 0 && carbsG >= 0 && fatG >= 0 }
    var totalMacroKcal: Double { proteinG * 4 + carbsG * 4 + fatG * 9 }

    // No NavigationStack of its own: pushed inside the Altro tab's stack.
    var body: some View {
        Group {
            Form {
                // MARK: Language
                Section {
                    Picker(selection: Binding(
                        get: { langManager.language },
                        set: { langManager.set($0) }
                    )) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text("\(lang.flagEmoji) \(Text(LocalizedStringKey(lang.displayName)))").tag(lang)
                        }
                    } label: {
                        Label("Lingua", systemImage: "globe")
                    }
                }

                // MARK: Body weight info
                Section {
                    HStack {
                        Label("Peso corporeo (da Apple Salute)", systemImage: "scalemass.fill")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.2f kg", bodyWeightKg))
                            .font(.subheadline.bold()).foregroundStyle(RitmoTheme.accent)
                    }
                } header: { Text("Corpo") } footer: {
                    Text("Media degli ultimi 7 giorni da Apple Salute — usata per i macro in modalità 'g per kg corporeo'.")
                }

                // MARK: Calories
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        SmartStepper(label: "Calorie totali", value: $calories, step: 50,
                                     format: "%.0f kcal", onChange: recalc)
                        HStack(spacing: 4) {
                            Text("Macro attivi:").font(.caption2).foregroundStyle(.secondary)
                            Text(String(format: "%.0f kcal", totalMacroKcal))
                                .font(.caption2.bold()).foregroundStyle(macrosOk ? .green : .red)
                        }
                    }
                } header: { Text("Calorie giornaliere") }

                // MARK: Macro mode + auto selection
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Modalità inserimento", systemImage: "slider.horizontal.3")
                                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            MacroModeSelector(selection: $inputMode, onChange: recalc)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Macro calcolato automaticamente", systemImage: "function")
                                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            AutoMacroSelector(selection: $autoMacroRaw, onChange: recalc)
                        }
                    }
                    .padding(.vertical, 4)
                } header: { Text("Macro") } footer: {
                    Text("Il macro automatico viene calcolato dalle calorie e dagli altri due.")
                }

                // MARK: Proteine
                Section {
                    if autoMacro == .protein {
                        autoMacroDisplay(value: proteinG, color: RitmoTheme.protein)
                    } else if inputMode == .perKg {
                        SmartStepper(label: "Proteine", value: $proteinPerKg, step: 0.1,
                                     format: "%.1f g/kg  (→ %.0f g)",
                                     formatArgs: [proteinPerKg, proteinRawG],
                                     color: RitmoTheme.protein, onChange: recalc)
                    } else {
                        SmartStepper(label: "Proteine", value: $proteinTotalG, step: 1,
                                     format: "%.0f g", color: RitmoTheme.protein,
                                     onChange: recalc, allowsDirectInput: true)
                    }
                } header: { Text("Proteine") }

                // MARK: Carboidrati
                Section {
                    if autoMacro == .carbs {
                        autoMacroDisplay(value: carbsG, color: RitmoTheme.carbs)
                    } else if inputMode == .perKg {
                        SmartStepper(label: "Carboidrati", value: $carbsPerKg, step: 0.5,
                                     format: "%.1f g/kg  (→ %.0f g)",
                                     formatArgs: [carbsPerKg, carbsRawG],
                                     color: RitmoTheme.carbs, onChange: recalc)
                    } else {
                        SmartStepper(label: "Carboidrati", value: $carbsTotalG, step: 5,
                                     format: "%.0f g", color: RitmoTheme.carbs,
                                     onChange: recalc, allowsDirectInput: true)
                    }
                } header: { Text("Carboidrati") }

                // MARK: Grassi
                Section {
                    if autoMacro == .fat {
                        autoMacroDisplay(value: fatG, color: RitmoTheme.fat)
                    } else if inputMode == .perKg {
                        SmartStepper(label: "Grassi", value: $fatPerKg, step: 0.05,
                                     format: "%.2f g/kg  (→ %.0f g)",
                                     formatArgs: [fatPerKg, fatRawG],
                                     color: RitmoTheme.fat, onChange: recalc)
                    } else {
                        SmartStepper(label: "Grassi", value: $fatTotalG, step: 1,
                                     format: "%.0f g", color: RitmoTheme.fat,
                                     onChange: recalc, allowsDirectInput: true)
                    }
                } header: { Text("Grassi") }

                // MARK: Fiber & Water
                Section {
                    SmartStepper(label: "Fibre", value: $fiber, step: 2, format: "%.0f g",
                                 color: RitmoTheme.fiber, onChange: saveGoals)
                    SmartStepper(label: "Acqua", value: $waterL, step: 0.25, format: "%.2f L",
                                 color: RitmoTheme.water, onChange: saveGoals)
                } header: { Text("Fibre & Acqua") }

                // MARK: Movement
                Section {
                    SmartStepper(label: "Passi", value: $steps, step: 500, format: "%.0f",
                                 color: RitmoTheme.steps, onChange: saveGoals)
                    SmartStepper(label: "Calorie attive", value: $activeKcal, step: 50,
                                 format: "%.0f kcal", color: .red, onChange: saveGoals)
                } header: { Text("Movimento") }

                // MARK: Sleep
                Section {
                    Stepper(value: $avgAwakeMinutes, in: 1...60, step: 1) {
                        HStack {
                            Text("Tempo sveglio per risveglio")
                            Spacer()
                            Text(String(format: AppLocalization.string("%@ min"),
                                        "\(Int(avgAwakeMinutes))"))
                                .font(.headline)
                                .foregroundStyle(RitmoTheme.sleep)
                        }
                    }
                } header: { Text("Sonno") } footer: {
                    Text("Quanto resti sveglio in media a ogni risveglio notturno. Usato per i risvegli che registri a mano: definisce il tempo da vigile scritto in Apple Salute e quanto pesa la continuità nel punteggio del sonno.")
                }

                // MARK: Health permissions
                Section {
                    Button {
                        // No API reveals a DENIED read permission — HealthKit
                        // just returns zero — so all we can do is send the user
                        // to the one place where it can be turned back on.
                        if let url = URL(string: "x-apple-health://") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Permessi Apple Salute", systemImage: "heart.text.square")
                    }
                } header: { Text("Apple Salute") } footer: {
                    Text("Se una metrica resta a zero mentre le altre si aggiornano (per esempio la distanza con i passi già contati), il permesso di lettura di quella categoria è disattivato: Ritmo riceve zero senza poter distinguere il rifiuto. Attivalo in Salute › profilo › App e servizi › Ritmo.")
                }

                // MARK: Integrations
                Section {
                    NavigationLink {
                        // Locked rows never navigate; see the
                        // .disabled below and the tap handler.
                        HevySettingsView()
                    } label: {
                        HStack {
                            Label("Hevy", systemImage: "link")
                            Spacer()
                            if hevyConnected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Collegato").font(.caption)
                                    .foregroundStyle(RitmoTheme.textSecondary)
                            } else {
                                Text("Non collegato").font(.caption)
                                    .foregroundStyle(RitmoTheme.textSecondary)
                            }
                        }
                    }
                    NavigationLink {
                        // Locked rows never navigate; see the
                        // .disabled below and the tap handler.
                        PowerliftingSettingsView()
                    } label: {
                        HStack {
                            Label("Powerlifting", systemImage: "figure.strengthtraining.traditional")
                            Spacer()
                            if !oplUsername.isEmpty {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Collegato").font(.caption)
                                    .foregroundStyle(RitmoTheme.textSecondary)
                            }
                        }
                    }
                    NavigationLink {
                        // Locked rows never navigate; see the
                        // .disabled below and the tap handler.
                        StravaSettingsView()
                    } label: {
                        HStack {
                            Label("Strava", systemImage: "figure.run.circle")
                            Spacer()
                            if !stravaRefreshToken.isEmpty {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Collegato").font(.caption)
                                    .foregroundStyle(RitmoTheme.textSecondary)
                            } else {
                                // "Avanzato" rather than "Non collegato": the
                                // setup is a detour through Strava's site, and
                                // the row is the last place to say so before
                                // someone commits to it.
                                Text("Avanzato").font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text("Integrazioni")
                        if !pro.isPro { ProBadge() }
                    }
                } footer: {
                    if !pro.isPro {
                        Text("Hevy, Strava e OpenPowerlifting fanno parte di Ritmo Pro.")
                    }
                }
                .disabled(!pro.isPro)
                .overlay {
                    if !pro.isPro {
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { paywallFor = .integrations }
                    }
                }

                // MARK: Export
                Section {
                    Button {
                        shareFile = exportCSV(name: "ritmo-allenamenti.csv", content: workoutsCSV())
                    } label: {
                        Label("Esporta allenamenti (CSV)", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        shareFile = exportCSV(name: "ritmo-gare.csv", content: racesCSV())
                    } label: {
                        Label("Esporta gare (CSV)", systemImage: "square.and.arrow.up")
                    }
                } header: { Text("Esporta dati") } footer: {
                    Text("File CSV apribili con Numbers o Excel — una riga per serie (allenamenti) e per gara.")
                }

                // MARK: Notifications
                Section {
                    Toggle(isOn: $weeklyRecapNotification) {
                        Label("Riepilogo settimanale", systemImage: "calendar.badge.clock")
                    }
                    .onChange(of: weeklyRecapNotification) { _, enabled in
                        if enabled {
                            Task {
                                if await WeeklyRecapNotifier.schedule() {
                                    flash("Notifica del lunedì attivata")
                                } else {
                                    weeklyRecapNotification = false
                                    flash("Permesso notifiche negato: attivalo dalle Impostazioni di iOS")
                                }
                            }
                        } else {
                            WeeklyRecapNotifier.cancel()
                        }
                    }
                } header: { Text("Notifiche") } footer: {
                    Text("Ogni lunedì alle 9:00 un promemoria con il riepilogo della settimana appena conclusa.")
                }

                // MARK: Default reset
                Section {
                    Button("Ripristina default per il tuo peso") {
                        applyDefaults()
                    }
                    .foregroundStyle(RitmoTheme.accent)
                } footer: {
                    Text("Default: carboidrati automatici · 2g proteine/kg · 0.8g grassi/kg.")
                }
            }
            .sheet(item: $paywallFor) { feature in PaywallView(requested: feature) }
            .navigationTitle(Text("Impostazioni"))
            .overlay(alignment: .bottom) {
                if showToast {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(toastMsg).font(.subheadline)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 4)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3), value: showToast)
        }
        .sheet(item: $shareFile) { file in
            ShareSheet(url: file.url)
        }
        .task {
            // Daily weigh-ins fluctuate: use the 7-day average, falling back
            // to the latest sample when there's no recent history. Averaged
            // per DAY first, so weighing three times one morning doesn't make
            // that day count triple.
            let history = await healthRepo.fetchBodyWeightHistoryPoints(days: 7)
            if !history.isEmpty {
                let calendar = Calendar.current
                let byDay = Dictionary(grouping: history) { calendar.startOfDay(for: $0.date) }
                let dayAverages = byDay.values.map { $0.map(\.value).reduce(0, +) / Double($0.count) }
                bodyWeightKg = dayAverages.reduce(0, +) / Double(dayAverages.count)
            } else if let metric = await healthRepo.fetchLatestBodyMetric(),
                      let w = metric.weightKg {
                bodyWeightKg = w
            }
            loadGoals()
        }
    }

    @ViewBuilder
    private func autoMacroDisplay(value: Double, color: Color) -> some View {
        HStack {
            Label("calcolato automaticamente", systemImage: "function")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            if value >= 0 {
                Text(String(format: "%.0f g", value))
                    .font(.subheadline.bold()).foregroundStyle(color)
            } else {
                Text("Calorie insufficienti").font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func recalc() {
        saveGoals()
    }

    private func applyDefaults() {
        inputMode    = .perKg
        autoMacroRaw = AutoMacro.carbs.rawValue
        proteinPerKg = 2.0
        fatPerKg     = 0.8
        carbsPerKg   = 3.0
        recalc()
        flash("Default applicati per \(String(format: "%.0f", bodyWeightKg))kg")
    }

    private func loadGoals() {
        let g = storedGoals.first ?? UserGoals()
        calories   = g.dailyCalories
        fiber      = g.dailyFiberG
        waterL     = g.dailyWaterMl / 1000
        steps      = Double(g.dailySteps)
        activeKcal = g.dailyActiveCalories

        proteinTotalG = g.dailyProteinG
        fatTotalG     = g.dailyFatG
        carbsTotalG   = g.dailyCarbsG

        // Preferred path: the user's stored per-kg settings are the source of
        // truth, and the gram goals are recomputed from them at the CURRENT
        // body weight (which was fetched right before this call).
        if let storedMode = MacroInputMode(rawValue: storedInputModeRaw) {
            inputMode = storedMode
            if storedMode == .perKg, storedProteinPerKg > 0, storedFatPerKg > 0, storedCarbsPerKg > 0 {
                proteinPerKg = storedProteinPerKg
                fatPerKg     = storedFatPerKg
                carbsPerKg   = storedCarbsPerKg
                saveGoals()   // grams follow the weight, not the other way round
            }
            return
        }

        // Legacy fallback (installs from before the per-kg preference was
        // persisted): guess the mode by back-deriving g/kg from the grams.
        let pw = bodyWeightKg > 0 ? bodyWeightKg : 80
        let ppkg = g.dailyProteinG / pw
        let fpkg = g.dailyFatG / pw
        let cpkg = g.dailyCarbsG / pw
        if ppkg >= 1.0 && ppkg <= 4.0 && fpkg >= 0.3 && fpkg <= 3.0 {
            inputMode    = .perKg
            proteinPerKg = ppkg
            fatPerKg     = fpkg
            carbsPerKg   = max(1.0, cpkg)
        } else {
            inputMode = .total
        }
    }

    private func saveGoals() {
        let g = UserGoals.canonical(in: modelContext)
        g.dailyCalories       = calories
        g.dailyProteinG       = proteinG
        g.dailyCarbsG         = carbsG
        g.dailyFatG           = fatG
        g.dailyFiberG         = fiber
        g.dailyWaterMl        = waterL * 1000
        g.dailySteps          = Int(steps)
        g.dailyActiveCalories = activeKcal
        try? modelContext.save()
        GoalsSyncService.shared.send(g)

        // Persist the per-kg preference itself — see loadGoals.
        storedInputModeRaw = inputMode.rawValue
        if inputMode == .perKg {
            storedProteinPerKg = proteinPerKg
            storedFatPerKg     = fatPerKg
            storedCarbsPerKg   = carbsPerKg
        }
    }

    private func flash(_ msg: String) {
        toastMsg = msg
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showToast = false }
        }
    }

    // MARK: - CSV export

    private func exportCSV(name: String, content: String) -> ShareFile? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard (try? content.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        return ShareFile(url: url)
    }

    private func csvField(_ value: String) -> String {
        value.contains(",") || value.contains("\"") || value.contains("\n")
            ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            : value
    }

    /// One row per set; sessions without sets still get one row with the
    /// session columns filled and the set columns empty.
    private func workoutsCSV() -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["date,title,source,duration_min,rpe,calories,distance_m,exercise,set_index,set_type,weight_kg,reps"]
        let sessions = (try? modelContext.fetch(
            FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startTime, order: .reverse)])
        )) ?? []
        for session in sessions {
            let base = [formatter.string(from: session.startTime),
                        csvField(session.title),
                        session.source.rawValue,
                        "\(session.durationMinutes)",
                        "\(session.effortScore)",
                        String(format: "%.0f", session.activeCalories),
                        String(format: "%.0f", session.distanceMeters)]
            let sets = session.sets.sorted { $0.setIndex < $1.setIndex }
            if sets.isEmpty {
                lines.append((base + ["", "", "", "", ""]).joined(separator: ","))
            } else {
                for set in sets {
                    lines.append((base + [csvField(set.exercise?.name ?? ""),
                                          "\(set.setIndex)",
                                          set.setType.rawValue,
                                          String(format: "%.2f", set.weightKg),
                                          set.reps.map { "\($0)" } ?? ""]).joined(separator: ","))
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private func racesCSV() -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["date,name,sport,distance_m,duration_s,source"]
        let races = (try? modelContext.fetch(
            FetchDescriptor<RaceResult>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        )) ?? []
        for race in races {
            lines.append([formatter.string(from: race.date),
                          csvField(race.name),
                          race.sportRaw,
                          String(format: "%.0f", race.distanceMeters),
                          "\(race.durationSeconds)",
                          race.sourceRaw].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Share sheet plumbing

struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Smart Stepper

private struct SmartStepper: View {
    let label: String
    @Binding var value: Double
    let step: Double
    let format: String
    var formatArgs: [Double]? = nil
    var color: Color = .primary
    var onChange: (() -> Void)? = nil
    var allowsDirectInput: Bool = false

    @State private var textInput: String = ""
    @FocusState private var isFocused: Bool

    private var displayText: String {
        if let args = formatArgs, !args.isEmpty {
            switch args.count {
            case 2: return String(format: format, args[0], args[1])
            default: return String(format: format, args[0])
            }
        }
        return String(format: format, value)
    }

    var body: some View {
        HStack {
            Text(LocalizedStringKey(label)).foregroundStyle(color.opacity(0.9))
            Spacer()
            if allowsDirectInput {
                HStack(spacing: 10) {
                    Button { value = max(0, value - step); onChange?() } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    TextField("", text: $textInput)
                        .keyboardType(.decimalPad)
                        .focused($isFocused)
                        .multilineTextAlignment(.center)
                        .monospacedDigit()
                        .font(.subheadline.bold())
                        .foregroundStyle(color)
                        .frame(width: 70)
                        .onAppear { textInput = String(format: "%.0f", value) }
                        .onChange(of: value) { _, v in
                            if !isFocused { textInput = String(format: "%.0f", v) }
                        }
                        .onSubmit {
                            if let v = Double(textInput) { value = max(0, v); onChange?() }
                            else { textInput = String(format: "%.0f", value) }
                        }
                        .onChange(of: isFocused) { _, focused in
                            if !focused {
                                if let v = Double(textInput) { value = max(0, v); onChange?() }
                                else { textInput = String(format: "%.0f", value) }
                            }
                        }
                    Button { value += step; onChange?() } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(color)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 14) {
                    Button { value = max(0, value - step); onChange?() } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    Text(displayText).monospacedDigit().font(.subheadline.bold())
                        .frame(minWidth: 90, alignment: .center)
                    Button { value += step; onChange?() } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(color)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Macro Mode Selector

private struct MacroModeSelector: View {
    @Binding var selection: MacroInputMode
    var onChange: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(MacroInputMode.allCases, id: \.self) { mode in
                let selected = selection == mode
                Button { selection = mode; onChange() } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode == .perKg ? "scalemass.fill" : "textformat.123")
                            .font(.headline)
                        Text(LocalizedStringKey(mode == .perKg ? "g / kg" : "Grammi totali"))
                            .font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selected ? RitmoTheme.accent.opacity(0.12) : Color(.systemGray6),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(selected ? RitmoTheme.accent : .clear, lineWidth: 1.5)
                    )
                    .foregroundStyle(selected ? RitmoTheme.accent : RitmoTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.2), value: selected)
            }
        }
    }
}

// MARK: - Auto Macro Selector

private struct AutoMacroSelector: View {
    @Binding var selection: String
    var onChange: () -> Void

    private func color(for macro: AutoMacro) -> Color {
        switch macro {
        case .protein: return RitmoTheme.protein
        case .carbs:   return RitmoTheme.carbs
        case .fat:     return RitmoTheme.fat
        }
    }
    private func emoji(for macro: AutoMacro) -> String {
        switch macro {
        case .protein: return "🥩"
        case .carbs:   return "🍞"
        case .fat:     return "🥑"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AutoMacro.allCases, id: \.rawValue) { macro in
                let selected = selection == macro.rawValue
                let color = color(for: macro)
                Button { selection = macro.rawValue; onChange() } label: {
                    VStack(spacing: 4) {
                        Text(emoji(for: macro)).font(.title3)
                        Text(LocalizedStringKey(macro.rawValue)).font(.caption.bold())
                        Text("automatico")
                            .font(.caption2)
                            .foregroundStyle(selected ? color.opacity(0.85) : .clear)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selected ? color.opacity(0.12) : Color(.systemGray6),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(selected ? color : .clear, lineWidth: 1.5)
                    )
                    .foregroundStyle(selected ? color : RitmoTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.2), value: selected)
            }
        }
    }
}

// MARK: - Hevy settings (submenu)

struct HevySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hevyApiKey") private var hevyApiKey = ""
    @AppStorage("hevyConnected") private var hevyConnected = false
    @AppStorage("hevyLastSync") private var hevyLastSyncTimestamp: Double = 0
    @State private var hevyImporting = false
    @State private var hevyProgress = ""
    @State private var hevyResult: String?

    var body: some View {
        Form {
            Section {
                if hevyConnected {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Hevy collegato").font(.subheadline.bold())
                        Spacer()
                        if hevyLastSyncTimestamp > 0 {
                            Text(Date(timeIntervalSince1970: hevyLastSyncTimestamp),
                                 format: .relative(presentation: .named))
                                .font(.caption2).foregroundStyle(RitmoTheme.textSecondary)
                        }
                    }
                    if hevyImporting {
                        HStack {
                            ProgressView().padding(.trailing, 6)
                            Text(hevyProgress.isEmpty ? "Importazione…" : hevyProgress)
                        }
                    } else {
                        Button {
                            importFromHevy(fullHistory: false)
                        } label: {
                            Label("Sincronizza ora (nuovi allenamenti)", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button {
                            importFromHevy(fullHistory: true)
                        } label: {
                            Label("Importa storico completo", systemImage: "clock.arrow.circlepath")
                        }
                    }
                    if let hevyResult {
                        Text(hevyResult).font(.caption).foregroundStyle(RitmoTheme.textSecondary)
                    }
                    Button(role: .destructive) {
                        hevyApiKey = ""
                        hevyConnected = false
                        hevyLastSyncTimestamp = 0
                        hevyResult = nil
                    } label: {
                        Label("Rimuovi collegamento", systemImage: "xmark.circle")
                    }
                    .disabled(hevyImporting)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Come collegare Hevy", systemImage: "info.circle")
                            .font(.caption.bold()).foregroundStyle(RitmoTheme.accent)
                        Text("La chiave si crea SOLO dalla versione web: vai su hevy.com dal browser, accedi, apri Impostazioni → Developer (serve Hevy Pro) e genera la API key. Incollala qui sotto: il collegamento resta attivo finché non lo rimuovi.")
                            .font(.caption2).foregroundStyle(RitmoTheme.textSecondary)
                        Text("E il webhook che vedi su quella pagina? Manda una notifica a un server quando salvi un allenamento — ma Ritmo non ha server, e per leggere i dati servirebbe comunque la chiave. Qui la chiave fa entrambe le cose: importa lo storico e completa i nuovi allenamenti appena compaiono.")
                            .font(.caption2).foregroundStyle(RitmoTheme.textSecondary)
                    }
                    .padding(.vertical, 2)
                    SecureField("Chiave API Hevy", text: $hevyApiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        connectHevy()
                    } label: {
                        HStack {
                            if hevyImporting {
                                ProgressView().padding(.trailing, 6)
                                Text(hevyProgress.isEmpty ? "Importazione…" : hevyProgress)
                            } else {
                                Label("Collega Hevy", systemImage: "link")
                            }
                        }
                    }
                    .disabled(hevyApiKey.trimmingCharacters(in: .whitespaces).isEmpty || hevyImporting)
                    if let hevyResult {
                        Text(hevyResult).font(.caption).foregroundStyle(RitmoTheme.textSecondary)
                    }
                }
            } footer: {
                if hevyConnected {
                    Text("Ritmo completa da solo i nuovi allenamenti: quando ne compare uno da Apple Salute, scarica da Hevy serie, pesi e titolo sulla stessa voce — mai un doppione. «Sincronizza ora» forza subito quel controllo; «Importa storico completo» ripassa tutta la cronologia per recuperare quelli vecchi.")
                } else {
                    Text("Una volta collegato, quando un nuovo allenamento compare da Apple Salute Ritmo lo completa da solo con i dati Hevy — serie, pesi e ripetizioni. L'allenamento resta uno solo: la voce di Apple Salute viene arricchita, non duplicata.")
                }
            }
        }
        .navigationTitle("Hevy")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// First-time connection: validates the key, marks the integration as
    /// connected (persists until removed), then runs the full first import.
    private func connectHevy() {
        hevyImporting = true
        hevyResult = nil
        let service = HevyService(apiKey: hevyApiKey.trimmingCharacters(in: .whitespaces))
        Task { @MainActor in
            do {
                try await service.validate()
                hevyConnected = true
                hevyImporting = false
                importFromHevy(fullHistory: true)
            } catch {
                hevyResult = error.localizedDescription
                hevyImporting = false
            }
        }
    }

    /// fullHistory walks every page (old workouts); otherwise it's the fast
    /// incremental check that stops at the first fully-known page.
    private func importFromHevy(fullHistory: Bool) {
        hevyImporting = true
        hevyResult = nil
        let service = HevyService(apiKey: hevyApiKey.trimmingCharacters(in: .whitespaces))
        Task { @MainActor in
            do {
                let result = try await service.importAll(into: modelContext,
                                                         stopWhenAllKnown: !fullHistory) { done, total in
                    hevyProgress = String(format: AppLocalization.string("Importazione… %@ di ~%@"),
                                          "\(done)", "\(total)")
                }
                hevyResult = String(format: AppLocalization.string("Importati %@ allenamenti, %@ arricchiti, %@ corretti, %@ già presenti."),
                                    "\(result.imported)", "\(result.mergedIntoExisting)",
                                    "\(result.updated)", "\(result.skipped)")
                hevyLastSyncTimestamp = Date.now.timeIntervalSince1970
                // The imported history changes the load baseline everywhere.
                GoalsSyncService.shared.sendTrainingLoad(recomputingFrom: modelContext)
            } catch {
                hevyResult = error.localizedDescription
            }
            hevyImporting = false
            hevyProgress = ""
        }
    }
}

// MARK: - Powerlifting settings (comp 1RMs + OpenPowerlifting)

struct PowerliftingSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("oplUsername") private var oplUsername = ""
    @AppStorage("meetDateEpoch") private var meetDateEpoch = 0.0

    @State private var squatText = ""
    @State private var benchText = ""
    @State private var deadliftText = ""
    @State private var usernameField = ""
    @State private var checking = false
    @State private var checkResult: String?
    @State private var loaded = false

    var body: some View {
        Form {
            // MARK: Competition 1RMs
            Section {
                maxRow("Squat", text: $squatText)
                maxRow("Panca Piana", text: $benchText)
                maxRow("Stacco da Terra", text: $deadliftText)
            } header: { Text("Massimali gara (kg)") } footer: {
                Text("I tuoi 1RM veri da gara: compaiono in Statistiche accanto alle stime e come riferimento nei grafici di progressione.")
            }

            // MARK: Next meet
            Section {
                Toggle("Gara programmata", isOn: Binding(
                    get: { meetDateEpoch > 0 },
                    set: { on in
                        meetDateEpoch = on
                            ? (Calendar.current.date(byAdding: .weekOfYear, value: 8, to: .now)?
                                .timeIntervalSince1970 ?? 0)
                            : 0
                    }))
                if meetDateEpoch > 0 {
                    DatePicker("Data della gara",
                               selection: Binding(
                                   get: { Date(timeIntervalSince1970: meetDateEpoch) },
                                   set: { meetDateEpoch = $0.timeIntervalSince1970 }),
                               displayedComponents: .date)
                }
            } header: { Text("Prossima gara") } footer: {
                Text("Il conto alla rovescia compare in Allenamenti → Statistiche.")
            }

            // MARK: OpenPowerlifting
            Section {
                if oplUsername.isEmpty {
                    TextField("username", text: $usernameField)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        connect()
                    } label: {
                        HStack {
                            if checking {
                                ProgressView().padding(.trailing, 6)
                                Text("Verifica…")
                            } else {
                                Label("Collega OpenPowerlifting", systemImage: "link")
                            }
                        }
                    }
                    .disabled(usernameField.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(oplUsername).font(.subheadline.bold())
                    }
                    Button(role: .destructive) {
                        oplUsername = ""
                        usernameField = ""
                        checkResult = nil
                    } label: {
                        Label("Rimuovi collegamento", systemImage: "xmark.circle")
                    }
                }
                if let checkResult {
                    Text(checkResult).font(.caption).foregroundStyle(RitmoTheme.textSecondary)
                }
            } header: { Text("OpenPowerlifting") } footer: {
                Text("Profilo pubblico su openpowerlifting.org: lo username è l'ultima parte dell'URL della tua pagina atleta (openpowerlifting.org/u/tuonome). Le tue gare compaiono in Allenamenti → Statistiche.")
            }
        }
        .navigationTitle("Powerlifting")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: meetDateEpoch) { _, epoch in
            // Widgets read the app group; the watch complication gets a push.
            HealthKitRepository.cacheMeetDate(epoch)
            GoalsSyncService.shared.sendMeetDate(epoch)
            WidgetCenter.shared.reloadTimelines(ofKind: "RitmoMeetCountdown")
        }
        .onAppear(perform: loadMaxes)
        .onChange(of: squatText) { _, _ in saveMaxes() }
        .onChange(of: benchText) { _, _ in saveMaxes() }
        .onChange(of: deadliftText) { _, _ in saveMaxes() }
    }

    private func maxRow(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(LocalizedStringKey(label))
            Spacer()
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text("kg").foregroundStyle(RitmoTheme.textSecondary).font(.caption)
        }
    }

    private func loadMaxes() {
        guard !loaded else { return }
        loaded = true
        let goals = UserGoals.canonical(in: modelContext)
        squatText = goals.compSquatKg > 0 ? fmt(goals.compSquatKg) : ""
        benchText = goals.compBenchKg > 0 ? fmt(goals.compBenchKg) : ""
        deadliftText = goals.compDeadliftKg > 0 ? fmt(goals.compDeadliftKg) : ""
        usernameField = oplUsername
    }

    private func saveMaxes() {
        guard loaded else { return }
        let goals = UserGoals.canonical(in: modelContext)
        goals.compSquatKg = parse(squatText)
        goals.compBenchKg = parse(benchText)
        goals.compDeadliftKg = parse(deadliftText)
        try? modelContext.save()
    }

    /// Accepts the Italian decimal comma as well as the dot.
    private func parse(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func fmt(_ kg: Double) -> String {
        kg.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(kg))" : String(format: "%.1f", kg)
    }

    /// Validates the username against the live endpoint before storing it.
    private func connect() {
        checking = true
        checkResult = nil
        let candidate = usernameField.trimmingCharacters(in: .whitespaces).lowercased()
        Task { @MainActor in
            do {
                let meets = try await OpenPowerliftingService.fetchMeets(username: candidate)
                oplUsername = candidate
                checkResult = String(format: AppLocalization.string("Trovate %@ gare."), "\(meets.count)")
            } catch {
                checkResult = error.localizedDescription
            }
            checking = false
        }
    }
}

// MARK: - Strava session (tokens + import, shared with the stats screen)

enum StravaSession {
    static var isConnected: Bool {
        !(UserDefaults.standard.string(forKey: "stravaRefreshToken") ?? "").isEmpty
    }

    static func store(_ tokens: StravaTokens) {
        let defaults = UserDefaults.standard
        defaults.set(tokens.accessToken, forKey: "stravaAccessToken")
        defaults.set(tokens.refreshToken, forKey: "stravaRefreshToken")
        defaults.set(tokens.expiresAt, forKey: "stravaExpiresAt")
    }

    static func disconnect() {
        let defaults = UserDefaults.standard
        for key in ["stravaAccessToken", "stravaRefreshToken", "stravaExpiresAt", "stravaLastImport"] {
            defaults.removeObject(forKey: key)
        }
    }

    /// Current access token, refreshed through the stored refresh token when
    /// expired — Strava access tokens only live six hours.
    @MainActor
    static func validAccessToken() async throws -> String {
        let defaults = UserDefaults.standard
        guard let refresh = defaults.string(forKey: "stravaRefreshToken"), !refresh.isEmpty,
              let clientID = defaults.string(forKey: "stravaClientID"), !clientID.isEmpty,
              let clientSecret = defaults.string(forKey: "stravaClientSecret"), !clientSecret.isEmpty
        else { throw StravaError.notConnected }

        let tokens = StravaTokens(accessToken: defaults.string(forKey: "stravaAccessToken") ?? "",
                                  refreshToken: refresh,
                                  expiresAt: defaults.double(forKey: "stravaExpiresAt"))
        if !tokens.isExpired, !tokens.accessToken.isEmpty { return tokens.accessToken }
        let fresh = try await StravaService.refresh(tokens, clientID: clientID, clientSecret: clientSecret)
        store(fresh)
        return fresh.accessToken
    }

    /// Pulls race-tagged activities (incremental unless `full`) into the race
    /// log. Returns how many were added.
    @MainActor
    static func importNewRaces(into context: ModelContext, full: Bool = false) async throws -> Int {
        let token = try await validAccessToken()
        let defaults = UserDefaults.standard
        let lastImport = defaults.double(forKey: "stravaLastImport")
        let after: Date? = (full || lastImport <= 0) ? nil : Date(timeIntervalSince1970: lastImport)
        let activities = try await StravaService.fetchRaceActivities(accessToken: token, after: after)
        let added = StravaService.importRaces(activities, into: context)
        defaults.set(Date.now.timeIntervalSince1970, forKey: "stravaLastImport")
        return added
    }
}

// MARK: - Strava settings (user's own API app + OAuth)

private final class WebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Every ASPresentationAnchor initialiser except init(windowScene:) is
        // deprecated on iOS 26, so a scene is required — and the user reached
        // this from a visible settings screen, so one necessarily exists.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let anchor = scenes.compactMap(\.keyWindow).first
                ?? scenes.flatMap(\.windows).first
                ?? scenes.first.map(ASPresentationAnchor.init(windowScene:))
        else {
            preconditionFailure("Strava sign-in presented with no window scene")
        }
        return anchor
    }
}

struct StravaSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("stravaClientID") private var clientID = ""
    @AppStorage("stravaClientSecret") private var clientSecret = ""
    @AppStorage("stravaRefreshToken") private var refreshToken = ""

    @State private var working = false
    @State private var result: String?
    @State private var authSession: ASWebAuthenticationSession?
    private let presentationContext = WebAuthPresentationContext()

    private var connected: Bool { !refreshToken.isEmpty }

    var body: some View {
        Form {
            Section {
                if connected {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Strava collegato").font(.subheadline.bold())
                    }
                    Button {
                        importRaces()
                    } label: {
                        HStack {
                            if working {
                                ProgressView().padding(.trailing, 6)
                                Text("Importazione…")
                            } else {
                                Label("Importa gare ora", systemImage: "flag.checkered")
                            }
                        }
                    }
                    .disabled(working)
                    Button(role: .destructive) {
                        StravaSession.disconnect()
                        refreshToken = ""
                        result = nil
                    } label: {
                        Label("Rimuovi collegamento", systemImage: "xmark.circle")
                    }
                    .disabled(working)
                } else {
                    // Say the quiet part first. Connecting Strava means
                    // registering an API application on their site and copying
                    // a client secret — developer work. Strava requires that
                    // secret for the token exchange and Ritmo has no server to
                    // keep it on, so there is no one-tap version to offer.
                    // Better to name the cost up front than let someone
                    // discover it three steps in and assume the app is broken.
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Integrazione avanzata", systemImage: "wrench.and.screwdriver")
                            .font(.caption.bold()).foregroundStyle(.orange)
                        Text("Richiede qualche minuto sul sito di Strava: serve creare una tua app API personale e copiare due codici. Le gare puoi comunque aggiungerle a mano in qualsiasi momento.")
                            .font(.caption2).foregroundStyle(RitmoTheme.textSecondary)
                    }
                    .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Come collegare Strava", systemImage: "info.circle")
                            .font(.caption.bold()).foregroundStyle(RitmoTheme.accent)
                        Text(String(format: AppLocalization.string("1. Apri strava.com/settings/api e crea la TUA app API (è gratis).\n2. In «Authorization Callback Domain» scrivi %@.\n3. Copia qui sotto Client ID e Client Secret."), StravaService.callbackHost))
                            .font(.caption2).foregroundStyle(RitmoTheme.textSecondary)
                    }
                    .padding(.vertical, 2)
                    TextField("Client ID", text: $clientID)
                        .keyboardType(.numberPad)
                    SecureField("Client Secret", text: $clientSecret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        connect()
                    } label: {
                        HStack {
                            if working {
                                ProgressView().padding(.trailing, 6)
                                Text("Verifica…")
                            } else {
                                Label("Collega Strava", systemImage: "link")
                            }
                        }
                    }
                    .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty
                              || clientSecret.trimmingCharacters(in: .whitespaces).isEmpty
                              || working)
                }
                if let result {
                    Text(result).font(.caption).foregroundStyle(RitmoTheme.textSecondary)
                }
            } footer: {
                Text("Vengono importate SOLO le attività segnate come gara su Strava (corsa e bici): gli allenamenti arrivano già da Apple Salute, importarli due volte creerebbe duplicati. Le gare compaiono in Allenamenti → Statistiche → Cardio.")
            }
        }
        .navigationTitle("Strava")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// OAuth in a system web session; the callback carries the one-time code
    /// exchanged (with the user's own client secret) for the token pair.
    private func connect() {
        guard let url = StravaService.authorizationURL(clientID: clientID.trimmingCharacters(in: .whitespaces)) else { return }
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: StravaService.urlScheme) { callbackURL, error in
            guard error == nil,
                  let callbackURL,
                  let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                      .queryItems?.first(where: { $0.name == "code" })?.value
            else {
                Task { @MainActor in result = AppLocalization.string("Accesso annullato.") }
                return
            }
            Task { @MainActor in
                working = true
                do {
                    let tokens = try await StravaService.exchangeCode(
                        code,
                        clientID: clientID.trimmingCharacters(in: .whitespaces),
                        clientSecret: clientSecret.trimmingCharacters(in: .whitespaces))
                    StravaSession.store(tokens)
                    refreshToken = tokens.refreshToken
                    result = nil
                    importRaces(full: true)
                } catch {
                    result = error.localizedDescription
                    working = false
                }
            }
        }
        session.presentationContextProvider = presentationContext
        authSession = session
        session.start()
    }

    private func importRaces(full: Bool = true) {
        working = true
        result = nil
        Task { @MainActor in
            do {
                let added = try await StravaSession.importNewRaces(into: modelContext, full: full)
                result = String(format: AppLocalization.string("Importate %@ gare."), "\(added)")
            } catch {
                result = error.localizedDescription
            }
            working = false
        }
    }
}
