import SwiftUI

struct WaterLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onLog: (Double) -> Void

    private let presets: [(String, Double)] = [
        ("☕ 150ml", 150), ("🥛 200ml", 200), ("🫙 330ml", 330),
        ("🍶 500ml", 500), ("🧴 750ml", 750)
    ]

    @State private var customAmount: String = ""
    @FocusState private var customFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Preset grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                    GridItem(.flexible())], spacing: 12) {
                    ForEach(presets, id: \.0) { label, ml in
                        Button {
                            onLog(ml)
                            dismiss()
                        } label: {
                            VStack(spacing: 4) {
                                Text(label).font(.subheadline.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RitmoTheme.water.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(RitmoTheme.water.opacity(0.3), lineWidth: 1))
                            .foregroundStyle(RitmoTheme.water)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                Divider()

                // Custom amount
                VStack(spacing: 12) {
                    HStack {
                        TextField("Quantità (ml)", text: $customAmount)
                            .keyboardType(.numberPad)
                            .focused($customFocused)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(RitmoTheme.cardBG, in: RoundedRectangle(cornerRadius: 12))

                        Button {
                            if let ml = Double(customAmount), ml > 0 {
                                onLog(ml)
                                dismiss()
                            }
                        } label: {
                            Text("Aggiungi")
                                .font(.headline.bold())
                                .foregroundStyle(.white)
                                .padding()
                                .background(RitmoTheme.water, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(Double(customAmount) == nil || (Double(customAmount) ?? 0) <= 0)
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Aggiungi acqua")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
