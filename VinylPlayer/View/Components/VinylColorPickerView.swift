import SwiftUI

/// Reusable vinyl color picker — shows preset VinylColor options + a custom ColorPicker.
struct VinylColorPickerView: View {
    @Binding var customHex: String?
    @Binding var vinylOpacity: Double?
    let currentEditionColor: VinylColor?
    @EnvironmentObject var styleManager: StyleManager

    @State private var pickerColor: Color = .red
    @State private var showCustomPicker = false

    private var opacityValue: Double {
        get { vinylOpacity ?? 1.0 }
    }

    /// Whether a preset is currently active (no custom override).
    private var activePreset: VinylColor? {
        guard customHex == nil || customHex?.isEmpty == true else { return nil }
        return currentEditionColor ?? .black
    }

    private let presets = VinylColor.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("vinyl_color.title"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(styleManager.theme.textPrimary)

            // Preset color grid + custom
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                ForEach(presets, id: \.self) { preset in
                    presetCircle(preset)
                }

                // Custom color button
                customCircle
            }

            // Opacity slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("vinyl_color.opacity"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(styleManager.theme.textSecondary)
                    Spacer()
                    Text("\(Int(opacityValue * 100))%")
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundColor(styleManager.theme.textSecondary)
                }

                Slider(value: Binding(
                    get: { opacityValue },
                    set: { vinylOpacity = $0 >= 0.99 ? nil : $0 }
                ), in: 0.4...1.0, step: 0.05)
                .tint(styleManager.theme.accentColor)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(styleManager.theme.surfaceColor)
        )
        .sheet(isPresented: $showCustomPicker) {
            customPickerSheet
        }
    }

    // MARK: - Preset Circle

    private func presetCircle(_ preset: VinylColor) -> some View {
        let editionColor = currentEditionColor ?? .black
        let isSelected: Bool = {
            if let hex = customHex, !hex.isEmpty {
                return hex == preset.colorHex
            }
            return preset == editionColor
        }()

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if preset == editionColor {
                    customHex = nil // Revert to edition default
                } else {
                    customHex = preset.colorHex
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(vinylFillColor(for: preset))
                    .frame(width: 36, height: 36)

                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                    .frame(width: 36, height: 36)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.displayName)
    }

    private func vinylFillColor(for preset: VinylColor) -> Color {
        let base = Color(hex: preset.colorHex) ?? Color(white: 0.1)
        if preset == .clear {
            return base.opacity(0.4)
        }
        return base
    }

    // MARK: - Custom Circle

    private var customCircle: some View {
        let isCustomActive = customHex != nil && !customHex!.isEmpty &&
            !presets.contains(where: { $0.colorHex == customHex })

        return Button {
            if let hex = customHex, !hex.isEmpty {
                pickerColor = Color(hex: hex) ?? .red
            }
            showCustomPicker = true
        } label: {
            ZStack {
                // Rainbow gradient to indicate "custom"
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red],
                            center: .center
                        )
                    )
                    .frame(width: 36, height: 36)

                if isCustomActive {
                    // Show the actual custom color in center
                    Circle()
                        .fill(Color(hex: customHex!) ?? .red)
                        .frame(width: 24, height: 24)

                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                } else {
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 24, height: 24)

                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("vinyl_color.custom"))
    }

    // MARK: - Custom Picker Sheet

    private var customPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Preview disc
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [pickerColor, pickerColor.opacity(0.7), .black],
                                center: .center,
                                startRadius: 10,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)

                    // Groove rings
                    ForEach(0..<6, id: \.self) { i in
                        Circle()
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                            .frame(width: CGFloat(40 + i * 20), height: CGFloat(40 + i * 20))
                    }

                    // Center hole
                    Circle()
                        .fill(Color.black)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                }
                .padding(.top, 20)

                ColorPicker(L("vinyl_color.pick"), selection: $pickerColor, supportsOpacity: false)
                    .font(.system(size: 16, weight: .medium))
                    .padding(.horizontal, 24)

                Spacer()
            }
            .navigationTitle(L("vinyl_color.custom_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("album.cancel")) {
                        showCustomPicker = false
                    }
                    .foregroundColor(styleManager.theme.accentColor)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("vinyl_color.apply")) {
                        customHex = pickerColor.toHex()
                        showCustomPicker = false
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(styleManager.theme.accentColor)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Color → Hex

extension Color {
    func toHex() -> String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
