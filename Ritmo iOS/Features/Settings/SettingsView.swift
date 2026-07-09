import SwiftUI
import SwiftData
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
    @AppStorage("weeklyRecapNotification") private var weeklyRecapNotification = false
    @AppStorage("hevyConnected") private var hevyConnected = false

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

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Language
                Section {
                    Picker(selection: Binding(
                        get: { langManager.language },
                        set: { langManager.set($0) }
                    )) {
                        ForEach(AppLanguage.allCases) { lang in
                            (Text(lang.flagEmoji + " ") + Text(LocalizedStringKey(lang.displayName))).tag(lang)
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

                // MARK: Integrations
                Section {
                    NavigationLink {
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
                } header: { Text("Integrazioni") }

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
        .task {
            // Daily weigh-ins fluctuate: use the 7-day average, falling back
            // to the latest sample when there's no recent history.
            let history = await healthRepo.fetchBodyWeightHistoryPoints(days: 7)
            if !history.isEmpty {
                bodyWeightKg = history.map(\.value).reduce(0, +) / Double(history.count)
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

        let pw = bodyWeightKg > 0 ? bodyWeightKg : 80
        proteinTotalG = g.dailyProteinG
        fatTotalG     = g.dailyFatG
        carbsTotalG   = g.dailyCarbsG
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
    }

    private func flash(_ msg: String) {
        toastMsg = msg
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showToast = false }
        }
    }
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
                    hevyProgress = String(format: NSLocalizedString("Importazione… %@ di ~%@", comment: ""),
                                          "\(done)", "\(total)")
                }
                hevyResult = String(format: NSLocalizedString("Importati %@ allenamenti, %@ arricchiti, %@ corretti, %@ già presenti.", comment: ""),
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
