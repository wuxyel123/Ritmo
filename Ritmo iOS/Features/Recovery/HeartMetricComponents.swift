import SwiftUI
import RitmoCore

struct MetricInfo {
    let title: String
    let whatItIs: LocalizedStringKey
    let goodValues: [(range: String, label: LocalizedStringKey, color: Color)]
    let tip: LocalizedStringKey
}

struct HeartMetric: View {
    let value: String; let label: LocalizedStringKey; let unit: LocalizedStringKey
    let color: Color; let icon: String
    var info: MetricInfo? = nil

    @State private var showingInfo = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon).foregroundStyle(color).font(.caption)
                    .frame(maxWidth: .infinity)
                if info != nil {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
            }
            Text(value).font(.title3.bold())
            Text(unit).font(.system(size: 9)).foregroundStyle(RitmoTheme.textSecondary)
            Text(label).font(.system(size: 9)).foregroundStyle(RitmoTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { if info != nil { showingInfo = true } }
        .sheet(isPresented: $showingInfo) {
            if let info { MetricInfoSheet(info: info) }
        }
    }
}

struct MetricInfoSheet: View {
    let info: MetricInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // What it is
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Cos'è", systemImage: "questionmark.circle")
                            .font(.subheadline.bold()).foregroundStyle(RitmoTheme.accent)
                        Text(info.whatItIs)
                            .font(.body).foregroundStyle(.primary)
                    }
                    .padding()
                    .background(RitmoTheme.cardBG, in: RoundedRectangle(cornerRadius: RitmoTheme.cardRadius))

                    // Good values
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Valori di riferimento", systemImage: "chart.bar")
                            .font(.subheadline.bold()).foregroundStyle(RitmoTheme.accent)
                        ForEach(info.goodValues, id: \.range) { entry in
                            HStack(spacing: 12) {
                                Circle().fill(entry.color).frame(width: 10, height: 10)
                                Text(entry.range).font(.subheadline.bold()).frame(width: 90, alignment: .leading)
                                Text(entry.label).font(.subheadline).foregroundStyle(RitmoTheme.textSecondary)
                            }
                        }
                    }
                    .padding()
                    .background(RitmoTheme.cardBG, in: RoundedRectangle(cornerRadius: RitmoTheme.cardRadius))

                    // Tip
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Consiglio", systemImage: "lightbulb")
                            .font(.subheadline.bold()).foregroundStyle(.yellow)
                        Text(info.tip)
                            .font(.body).foregroundStyle(.primary)
                    }
                    .padding()
                    .background(RitmoTheme.cardBG, in: RoundedRectangle(cornerRadius: RitmoTheme.cardRadius))
                }
                .padding(RitmoTheme.pagePadding)
            }
            .navigationTitle(Text(LocalizedStringKey(info.title)))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
