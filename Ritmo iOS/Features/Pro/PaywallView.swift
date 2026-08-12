import SwiftUI
import StoreKit
import RitmoCore

// MARK: - PaywallView
//
// Only ever reached by tapping a Pro feature. The free tier has no paywall in
// front of it, and founding users never see this at all.

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var pro: ProStore

    /// The feature the user was reaching for — shown first, so the screen
    /// answers "why am I seeing this?" before it asks for anything.
    var requested: ProFeature?

    private var priceLine: String? {
        guard let product = pro.product else { return nil }
        return String(format: AppLocalization.string("%@ all'anno"), product.displayPrice)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RitmoTheme.gap) {

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ritmo Pro").font(.largeTitle.bold())
                        Text("Il punteggio del giorno, gli allenamenti, il sonno e il recupero restano gratuiti per sempre. Pro aggiunge l'analisi.")
                            .font(.subheadline)
                            .foregroundStyle(RitmoTheme.textSecondary)
                    }
                    .padding(.top, 8)

                    FitCard {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(ProFeature.allCases, id: \.rawValue) { feature in
                                featureRow(feature, highlighted: feature == requested)
                            }
                        }
                    }

                    if let priceLine {
                        Text(priceLine).font(.headline)
                        Text("Rinnovo automatico annuale. Puoi disdire quando vuoi dalle impostazioni dell'App Store; l'abbonamento resta attivo fino alla fine del periodo pagato.")
                            .font(.caption2).foregroundStyle(RitmoTheme.textSecondary)
                    } else {
                        Text("Prezzo non disponibile al momento.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await pro.purchase(); if pro.isPro { dismiss() } }
                    } label: {
                        HStack {
                            Spacer()
                            if pro.isWorking { ProgressView().tint(.white) }
                            else { Text("Attiva Pro").font(.headline) }
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(RitmoTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(pro.isWorking || pro.product == nil)

                    Button {
                        Task { await pro.restore(); if pro.isPro { dismiss() } }
                    } label: {
                        Text("Ripristina acquisti").font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(pro.isWorking)

                    if let error = pro.lastError {
                        Text(error).font(.caption2).foregroundStyle(.red)
                    }

                    // App Review requires both of these reachable from the
                    // purchase screen.
                    HStack(spacing: 16) {
                        Link("Privacy", destination: URL(string: "https://wuxyel123.github.io/Ritmo/privacy.html")!)
                        Link("Termini d'uso", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        Spacer()
                    }
                    .font(.caption2)
                    .padding(.top, 4)
                }
                .padding(RitmoTheme.pagePadding)
            }
            .navigationTitle("Ritmo Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .task { await pro.refresh() }
        }
    }

    private func featureRow(_ feature: ProFeature, highlighted: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feature.icon)
                .font(.title3)
                .foregroundStyle(highlighted ? RitmoTheme.accent : .secondary)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(feature.title))
                    .font(.subheadline.bold())
                    .foregroundStyle(highlighted ? RitmoTheme.accent : .primary)
                Text(LocalizedStringKey(feature.detail))
                    .font(.caption2).foregroundStyle(RitmoTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Pro gating

extension View {
    /// Runs `action` when the user is entitled, otherwise presents the paywall.
    /// Used by the entry cards so a locked feature still looks like a feature.
    func proGated(_ feature: ProFeature, isPro: Bool,
                  showPaywall: Binding<ProFeature?>,
                  action: @escaping () -> Void) -> some View {
        Button {
            if isPro { action() } else { showPaywall.wrappedValue = feature }
        } label: { self }
        .buttonStyle(.plain)
    }
}

/// Small lock chip for entry cards the user hasn't unlocked yet.
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 9, weight: .heavy))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RitmoTheme.accent.opacity(0.15), in: Capsule())
            .foregroundStyle(RitmoTheme.accent)
    }
}
