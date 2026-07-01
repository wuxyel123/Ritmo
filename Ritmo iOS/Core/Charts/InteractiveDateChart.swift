import SwiftUI
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
                    Text(LocalizedStringKey(title)).font(.subheadline.bold())
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
                            (Text("Media") + Text(": \(Int(avg)) \(unit)")).font(.caption).foregroundStyle(color)
                            if let g = goal {
                                (Text("Obiettivo") + Text(": \(Int(g)) \(unit)")).font(.caption2).foregroundStyle(.secondary)
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
                                (Text(String(format: "%.0f%%", pct)) + Text(" ") + Text("obiettivo"))
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
                    .background(RitmoTheme.cardBG, in: RoundedRectangle(cornerRadius: 12))
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
            .navigationTitle(Text(LocalizedStringKey(title)))
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
