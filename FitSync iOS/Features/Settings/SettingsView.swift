import SwiftUI
import SwiftData
import FitSyncCore

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
                        Text(String(format: "%.1f kg", bodyWeightKg))
                            .font(.subheadline.bold()).foregroundStyle(FitSyncTheme.accent)
                    }
                } header: { Text("Corpo") } footer: {
                    Text("Usato per calcolare i macro in modalità 'g per kg corporeo'.")
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
                        autoMacroDisplay(value: proteinG, color: FitSyncTheme.protein)
                    } else if inputMode == .perKg {
                        SmartStepper(label: "Proteine", value: $proteinPerKg, step: 0.1,
                                     format: "%.1f g/kg  (→ %.0f g)",
                                     formatArgs: [proteinPerKg, proteinRawG],
                                     color: FitSyncTheme.protein, onChange: recalc)
                    } else {
                        SmartStepper(label: "Proteine", value: $proteinTotalG, step: 1,
                                     format: "%.0f g", color: FitSyncTheme.protein,
                                     onChange: recalc, allowsDirectInput: true)
                    }
                } header: { Text("Proteine") }

                // MARK: Carboidrati
                Section {
                    if autoMacro == .carbs {
                        autoMacroDisplay(value: carbsG, color: FitSyncTheme.carbs)
                    } else if inputMode == .perKg {
                        SmartStepper(label: "Carboidrati", value: $carbsPerKg, step: 0.5,
                                     format: "%.1f g/kg  (→ %.0f g)",
                                     formatArgs: [carbsPerKg, carbsRawG],
                                     color: FitSyncTheme.carbs, onChange: recalc)
                    } else {
                        SmartStepper(label: "Carboidrati", value: $carbsTotalG, step: 5,
                                     format: "%.0f g", color: FitSyncTheme.carbs,
                                     onChange: recalc, allowsDirectInput: true)
                    }
                } header: { Text("Carboidrati") }

                // MARK: Grassi
                Section {
                    if autoMacro == .fat {
                        autoMacroDisplay(value: fatG, color: FitSyncTheme.fat)
                    } else if inputMode == .perKg {
                        SmartStepper(label: "Grassi", value: $fatPerKg, step: 0.05,
                                     format: "%.2f g/kg  (→ %.0f g)",
                                     formatArgs: [fatPerKg, fatRawG],
                                     color: FitSyncTheme.fat, onChange: recalc)
                    } else {
                        SmartStepper(label: "Grassi", value: $fatTotalG, step: 1,
                                     format: "%.0f g", color: FitSyncTheme.fat,
                                     onChange: recalc, allowsDirectInput: true)
                    }
                } header: { Text("Grassi") }

                // MARK: Fiber & Water
                Section {
                    SmartStepper(label: "Fibre", value: $fiber, step: 2, format: "%.0f g",
                                 color: FitSyncTheme.fiber, onChange: saveGoals)
                    SmartStepper(label: "Acqua", value: $waterL, step: 0.25, format: "%.2f L",
                                 color: FitSyncTheme.water, onChange: saveGoals)
                } header: { Text("Fibre & Acqua") }

                // MARK: Movement
                Section {
                    SmartStepper(label: "Passi", value: $steps, step: 500, format: "%.0f",
                                 color: FitSyncTheme.steps, onChange: saveGoals)
                    SmartStepper(label: "Calorie attive", value: $activeKcal, step: 50,
                                 format: "%.0f kcal", color: .red, onChange: saveGoals)
                } header: { Text("Movimento") }

                // MARK: Default reset
                Section {
                    Button("Ripristina default per il tuo peso") {
                        applyDefaults()
                    }
                    .foregroundStyle(FitSyncTheme.accent)
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
            if let metric = await healthRepo.fetchLatestBodyMetric(),
               let w = metric.weightKg { bodyWeightKg = w }
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
        let g = storedGoals.first ?? UserGoals()
        if storedGoals.isEmpty { modelContext.insert(g) }
        g.dailyCalories       = calories
        g.dailyProteinG       = proteinG
        g.dailyCarbsG         = carbsG
        g.dailyFatG           = fatG
        g.dailyFiberG         = fiber
        g.dailyWaterMl        = waterL * 1000
        g.dailySteps          = Int(steps)
        g.dailyActiveCalories = activeKcal
        try? modelContext.save()
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
                        selected ? FitSyncTheme.accent.opacity(0.12) : Color(.systemGray6),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(selected ? FitSyncTheme.accent : .clear, lineWidth: 1.5)
                    )
                    .foregroundStyle(selected ? FitSyncTheme.accent : FitSyncTheme.textSecondary)
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
        case .protein: return FitSyncTheme.protein
        case .carbs:   return FitSyncTheme.carbs
        case .fat:     return FitSyncTheme.fat
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
                    .foregroundStyle(selected ? color : FitSyncTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.2), value: selected)
            }
        }
    }
}
