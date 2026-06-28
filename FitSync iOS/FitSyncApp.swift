import SwiftUI
import SwiftData
import FitSyncCore

// MARK: - iOS App Entry Point
@main
struct FitSyncApp: App {
    @StateObject private var langManager = LanguageManager()
    @StateObject private var healthRepo = HealthKitRepository()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(FitSyncStore.container)
                .id(langManager.viewID)
                .environment(\.locale, langManager.locale)
                .environmentObject(langManager)
                .environmentObject(healthRepo)
                .task { await healthRepo.requestAuthorization() }
        }
    }
}

// MARK: - ContentView
struct ContentView: View {
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(onNavigate: { selectedTab = $0 })
                .tabItem { Label("Oggi", systemImage: "house.fill") }.tag(0)

            WorkoutListView()
                .tabItem { Label("Allenamenti", systemImage: "dumbbell.fill") }.tag(1)

            NutritionView()
                .tabItem { Label("Nutrizione", systemImage: "fork.knife") }.tag(2)

            RecoveryView()
                .tabItem { Label("Recupero", systemImage: "bed.double.fill") }.tag(3)

            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.line.uptrend.xyaxis") }.tag(4)

            SettingsTabView()
                .tabItem { Label("Obiettivi", systemImage: "slider.horizontal.3") }.tag(5)
        }
        .tint(FitSyncTheme.accent)
        .onOpenURL { url in
            switch url.host {
            case "nutrition": selectedTab = 2
            case "recovery": selectedTab = 3
            case "insights": selectedTab = 4
            case "workouts": selectedTab = 1
            default: selectedTab = 0
            }
        }
    }
}

// MARK: - Design System
enum FitSyncTheme {
    // Palette
    static let accent        = Color("AccentColor")
    #if os(iOS)
    static let background    = Color(uiColor: .systemBackground)
    static let cardBG        = Color(uiColor: .secondarySystemBackground)
    static let textPrimary   = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)
    #else
    static let background    = Color(nsColor: .windowBackgroundColor)
    static let cardBG        = Color(nsColor: .controlBackgroundColor)
    static let textPrimary   = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    #endif

    // Colori semantici
    static let calories  = Color.orange
    static let protein   = Color.red
    static let carbs     = Color.yellow
    static let fat       = Color.green
    static let fiber     = Color.mint
    static let water     = Color.blue
    static let sleep     = Color.indigo
    static let workout   = Color.purple
    static let steps     = Color.cyan
    static let positive  = Color.green
    static let warning   = Color.orange
    static let danger    = Color.red

    // Radii
    static let cardRadius: CGFloat = 16
    static let pillRadius: CGFloat = 999

    // Spacing
    static let pagePadding: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let gap: CGFloat = 12
}

// MARK: - Reusable Card Component
struct FitCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(FitSyncTheme.cardPadding)
            .background(FitSyncTheme.cardBG, in: RoundedRectangle(cornerRadius: FitSyncTheme.cardRadius))
            .clipShape(RoundedRectangle(cornerRadius: FitSyncTheme.cardRadius))
    }
}

// MARK: - Section Header
struct SectionHeader: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            Spacer()
            if let action, let onAction {
                Button(action, action: onAction)
                    .font(.subheadline)
                    .foregroundStyle(FitSyncTheme.accent)
            }
        }
    }
}

// MARK: - Progress Bar
struct FitProgressBar: View {
    let value: Double   // 0-1
    let color: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 999)
                    .fill(color.opacity(0.2))
                    .frame(height: height)
                RoundedRectangle(cornerRadius: 999)
                    .fill(value >= 1 ? FitSyncTheme.positive : color)
                    .frame(width: geo.size.width * min(value, 1), height: height)
                    .animation(.spring(response: 0.5), value: value)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Macro Row (usato in Nutrition e Widget)
struct MacroRow: View {
    let emoji: String
    let label: String
    let current: Double
    let goal: Double
    let unit: String
    let color: Color
    var fractionDigits: Int = 0

    var progress: Double { min(current / max(goal, 1), 1.0) }

    private var formattedGoal: String {
        fractionDigits > 0
            ? String(format: "%.\(fractionDigits)f\(unit)", goal)
            : "\(Int(goal))\(unit)"
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(emoji)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(FitSyncTheme.textSecondary)
                Spacer()
                HStack(spacing: 3) {
                    Text(current, format: .number.precision(.fractionLength(fractionDigits)))
                        .fontWeight(.semibold)
                        .foregroundStyle(progress >= 1 ? FitSyncTheme.positive : FitSyncTheme.textPrimary)
                    Text("/ \(formattedGoal)")
                        .font(.subheadline)
                        .foregroundStyle(FitSyncTheme.textSecondary)
                }
            }
            FitProgressBar(value: progress, color: color)
        }
    }
}

// MARK: - Settings Tab — Smart Macro Goals

enum MacroInputMode: String, CaseIterable {
    case perKg  = "g per kg corporeo"
    case total  = "grammi totali"
}

enum AutoMacro: String, CaseIterable {
    case protein = "Proteine"
    case carbs   = "Carboidrati"
    case fat     = "Grassi"
}

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
                            Text("\(lang.flagEmoji) \(lang.displayName)").tag(lang)
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
            .navigationTitle(Text("Obiettivi"))
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
            Text(label).foregroundStyle(color.opacity(0.9))
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

// MARK: - MacroModeSelector

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

// MARK: - AutoMacroSelector

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

// MARK: - View helpers

extension View {
    @ViewBuilder
    func applyIf<M: View>(_ condition: Bool, transform: (Self) -> M) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - Interactive Date Chart (shared across Nutrition + Recovery tabs)

import Charts

struct ChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

enum ChartDisplayType { case bar, line }

struct InteractiveDateChart: View {
    let title: String
    let points: [ChartPoint]
    let goal: Double?
    let color: Color
    let unit: String
    let chartUnit: Calendar.Component
    let chartType: ChartDisplayType
    var yDomain: ClosedRange<Double>? = nil

    @State private var selectedPoint: ChartPoint?
    @State private var isExpanded = false

    var avg: Double {
        let nonZero = points.filter { $0.value > 0 }
        guard !nonZero.isEmpty else { return 0 }
        return nonZero.map(\.value).reduce(0, +) / Double(nonZero.count)
    }

    var body: some View {
        FitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title).font(.subheadline.bold())
                    Spacer()
                    if let sel = selectedPoint {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(String(format: "%.0f \(unit)", sel.value))
                                .font(.subheadline.bold()).foregroundStyle(color)
                            Text(sel.date, format: .dateTime.day().month())
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("Media: \(Int(avg)) \(unit)").font(.caption).foregroundStyle(color)
                            if let g = goal {
                                Text("Obiettivo: \(Int(g)) \(unit)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button { isExpanded = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                chartBody.frame(height: 110).clipped()
            }
        }
        .fullScreenCover(isPresented: $isExpanded) {
            ExpandedChartView(title: title, points: points, goal: goal,
                              color: color, unit: unit, chartUnit: chartUnit, chartType: chartType,
                              yDomain: yDomain)
        }
    }

    private var chartBody: some View {
        Chart {
            ForEach(points) { p in
                if chartType == .bar {
                    BarMark(x: .value("Data", p.date, unit: chartUnit),
                            y: .value(unit, p.value))
                        .foregroundStyle(goal.map { p.value >= $0 } == true ? Color.green : color)
                        .cornerRadius(3)
                } else {
                    LineMark(x: .value("Data", p.date, unit: chartUnit),
                             y: .value(unit, p.value))
                        .foregroundStyle(color).interpolationMethod(.catmullRom)
                    AreaMark(x: .value("Data", p.date, unit: chartUnit),
                             yStart: .value("Base", yDomain?.lowerBound ?? 0),
                             yEnd: .value(unit, p.value))
                        .foregroundStyle(color.opacity(0.12)).interpolationMethod(.catmullRom)
                }
                if let sel = selectedPoint, sel.id == p.id {
                    PointMark(x: .value("Data", p.date, unit: chartUnit),
                              y: .value(unit, p.value))
                        .foregroundStyle(color).symbolSize(60)
                }
            }
            if let g = goal {
                RuleMark(y: .value("Obiettivo", g))
                    .foregroundStyle(color.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
        }
        .applyIf(yDomain != nil) { $0.chartYScale(domain: yDomain!) }
        .chartOverlay { proxy in
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        if let date: Date = proxy.value(atX: val.location.x, as: Date.self) {
                            selectedPoint = points.min {
                                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                            }
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.2)) { selectedPoint = nil }
                    }
                )
        }
    }
}

struct ExpandedChartView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let points: [ChartPoint]
    let goal: Double?
    let color: Color
    let unit: String
    let chartUnit: Calendar.Component
    let chartType: ChartDisplayType
    var yDomain: ClosedRange<Double>? = nil

    @State private var selectedPoint: ChartPoint?

    var avg: Double {
        let nonZero = points.filter { $0.value > 0 }
        guard !nonZero.isEmpty else { return 0 }
        return nonZero.map(\.value).reduce(0, +) / Double(nonZero.count)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Selected info banner
                if let sel = selectedPoint {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(sel.date, format: .dateTime.weekday(.wide).day().month())
                                .font(.subheadline.bold())
                            Text(String(format: "%.0f %@", sel.value, unit))
                                .font(.title2.bold()).foregroundStyle(color)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            if let g = goal {
                                let pct = sel.value / g * 100
                                Text(String(format: "%.0f%% obiettivo", pct))
                                    .font(.caption).foregroundStyle(pct >= 100 ? .green : .secondary)
                            }
                        }
                    }
                    .padding()
                    .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                } else {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Media").font(.caption).foregroundStyle(.secondary)
                            Text("\(Int(avg)) \(unit)").font(.title2.bold()).foregroundStyle(color)
                        }
                        Spacer()
                        if let g = goal {
                            VStack(alignment: .trailing) {
                                Text("Obiettivo").font(.caption).foregroundStyle(.secondary)
                                Text("\(Int(g)) \(unit)").font(.headline)
                            }
                        }
                    }
                    .padding()
                    .background(FitSyncTheme.cardBG, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                // Big interactive chart
                Chart(points) { p in
                    if chartType == .bar {
                        BarMark(x: .value("Data", p.date, unit: chartUnit),
                                y: .value(unit, p.value))
                            .foregroundStyle(goal.map { p.value >= $0 } == true ? Color.green : color)
                            .cornerRadius(4)
                    } else {
                        LineMark(x: .value("Data", p.date, unit: chartUnit),
                                 y: .value(unit, p.value))
                            .foregroundStyle(color).interpolationMethod(.catmullRom)
                        AreaMark(x: .value("Data", p.date, unit: chartUnit),
                                 yStart: .value("Base", yDomain?.lowerBound ?? 0),
                                 yEnd: .value(unit, p.value))
                            .foregroundStyle(color.opacity(0.12)).interpolationMethod(.catmullRom)
                    }
                    if let sel = selectedPoint, sel.id == p.id {
                        PointMark(x: .value("Data", p.date, unit: chartUnit),
                                  y: .value(unit, p.value))
                            .foregroundStyle(color).symbolSize(80)
                        RuleMark(x: .value("Data", p.date, unit: chartUnit))
                            .foregroundStyle(color.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    }
                    if let g = goal {
                        RuleMark(y: .value("Obiettivo", g))
                            .foregroundStyle(color.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6]))
                    }
                }
                .applyIf(yDomain != nil) { $0.chartYScale(domain: yDomain!) }
                .chartOverlay { proxy in
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                if let date: Date = proxy.value(atX: val.location.x, as: Date.self) {
                                    selectedPoint = points.min {
                                        abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                    }
                                }
                            }
                            .onEnded { _ in
                                withAnimation(.easeOut(duration: 0.25)) { selectedPoint = nil }
                            }
                        )
                }
                .frame(maxHeight: .infinity)
                .padding()
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Fit Calendar View (shared — shows dots on days with data)

struct FitCalendarView: View {
    @Binding var selectedDate: Date
    let daysWithData: Set<String>
    let onSelect: () -> Void

    @State private var displayedMonth = Date.now
    private let calendar = Calendar.current
    private let fmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; return f
    }()

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))!
    }
    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: displayedMonth)!.count
    }
    private var weekdayOfFirst: Int {
        (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
    }
    private let dayNames = ["Lu", "Ma", "Me", "Gi", "Ve", "Sa", "Do"]

    var body: some View {
        VStack(spacing: 16) {
            // Month header
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(displayedMonth, format: .dateTime.month(.wide).year())
                    .font(.headline.bold())
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(calendar.isDate(displayedMonth, equalTo: .now, toGranularity: .month))
            }

            // Day-of-week header
            HStack {
                ForEach(dayNames, id: \.self) { d in
                    Text(d).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }

            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(0..<weekdayOfFirst, id: \.self) { _ in Color.clear }
                ForEach(1...daysInMonth, id: \.self) { day in
                    let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart)!
                    let isFuture = date > .now
                    let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                    let hasData = daysWithData.contains(fmt.string(from: date))

                    Button {
                        if !isFuture { selectedDate = date; onSelect() }
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(day)")
                                .font(.subheadline.bold())
                                .frame(width: 36, height: 36)
                                .background(isSelected ? FitSyncTheme.accent : Color.clear,
                                            in: Circle())
                                .foregroundStyle(isSelected ? .white : isFuture ? Color.secondary : Color.primary)
                            Circle().fill(hasData ? FitSyncTheme.accent : Color.clear)
                                .frame(width: 4, height: 4)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isFuture)
                }
            }

            Divider()

            // "Oggi" shortcut
            Button("Vai a oggi") {
                selectedDate = .now
                displayedMonth = .now
                onSelect()
            }
            .font(.subheadline).foregroundStyle(FitSyncTheme.accent)
            .padding(.bottom, 4)
        }
        .padding()
        .onAppear { displayedMonth = selectedDate }
    }

    private func shiftMonth(_ delta: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) ?? displayedMonth
    }
}
