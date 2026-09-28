import SwiftUI
import PhotosUI

struct ShareCustomizationSheet: View {
    @ObservedObject var customization: ShareCustomization
    let hasLyrics: Bool
    @EnvironmentObject var styleManager: StyleManager
    @Environment(\.dismiss) private var dismiss

    // PhotosPicker
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showResetConfirm: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    vinylSection
                    backgroundSection
                    coverSection
                    textSection
                    if hasLyrics {
                        lyricsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .navigationTitle(L("share.customize_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showResetConfirm = true
                    } label: {
                        Text(L("share.reset"))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!customization.hasChanges)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(styleManager.theme.accentColor)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .alert(L("share.reset_title"), isPresented: $showResetConfirm) {
            Button(L("share.reset"), role: .destructive) {
                customization.reset()
            }
            Button(L("share.resave_cancel"), role: .cancel) {}
        } message: {
            Text(L("share.reset_message"))
        }
    }

    // MARK: - Vinyl Section

    private var vinylSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L("share.section_vinyl"), icon: "record.circle")

            // Color presets
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ShareCustomization.presetVinylColors, id: \.hex) { preset in
                        Button {
                            customization.vinylColorHex = preset.hex
                        } label: {
                            Circle()
                                .fill(Color(hex: preset.hex) ?? .gray)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: customization.vinylColorHex == preset.hex ? 2.5 : 0)
                                        .padding(-3)
                                )
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }

            // Translucent toggle
            Toggle(L("share.translucent"), isOn: $customization.isTranslucent)
                .font(.subheadline)
        }
        .padding(16)
        .background(sectionBackground)
    }

    // MARK: - Background Section

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L("share.section_background"), icon: "paintpalette")

            // Style picker
            HStack(spacing: 0) {
                ForEach(ShareBackgroundStyle.allCases) { style in
                    Button {
                        customization.backgroundStyle = style
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: style.iconName)
                                .font(.system(size: 16))
                            Text(style.displayName)
                                .font(.system(size: 10))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(customization.backgroundStyle == style
                                    ? Color.primary.opacity(0.12)
                                    : Color.clear)
                        )
                        .foregroundColor(customization.backgroundStyle == style ? .primary : .secondary)
                    }
                }
            }

            // Conditional color pickers
            switch customization.backgroundStyle {
            case .solidColor:
                ColorPicker(L("share.bg_color"), selection: Binding(
                    get: { customization.backgroundColor },
                    set: { customization.backgroundColorHex = $0.hexString }
                ))
                .font(.subheadline)
            case .gradient:
                ColorPicker(L("share.gradient_start"), selection: Binding(
                    get: { customization.gradientStart },
                    set: { customization.gradientStartHex = $0.hexString }
                ))
                .font(.subheadline)
                ColorPicker(L("share.gradient_end"), selection: Binding(
                    get: { customization.gradientEnd },
                    set: { customization.gradientEndHex = $0.hexString }
                ))
                .font(.subheadline)
            case .blurredCover:
                EmptyView()
            }
        }
        .padding(16)
        .background(sectionBackground)
    }

    // MARK: - Cover Section

    private var coverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L("share.section_cover"), icon: "photo")

            HStack(spacing: 12) {
                // Current cover preview
                if let img = customization.customCoverImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Text(L("share.choose_cover"))
                            .font(.subheadline.weight(.medium))
                    }

                    if customization.customCoverImage != nil {
                        Button(role: .destructive) {
                            customization.customCoverImage = nil
                        } label: {
                            Text(L("share.remove_cover"))
                                .font(.caption)
                        }
                    }
                }

                Spacer()
            }
        }
        .padding(16)
        .background(sectionBackground)
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    customization.customCoverImage = img
                }
            }
        }
    }

    // MARK: - Text Section

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L("share.section_text"), icon: "textformat")

            // Text color
            ColorPicker(L("share.text_color"), selection: Binding(
                get: { customization.textColor },
                set: { customization.textColorHex = $0.hexString }
            ))
            .font(.subheadline)

            // Font size slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("share.font_size"))
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(customization.titleFontSize))pt")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Slider(value: $customization.titleFontSize, in: 12...28, step: 1)
            }

            // Font design
            VStack(alignment: .leading, spacing: 6) {
                Text(L("share.font_style"))
                    .font(.subheadline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ShareFontDesign.allCases) { design in
                            Button {
                                customization.fontDesign = design
                            } label: {
                                Text(design.displayName)
                                    .font(design.font(size: 13, weight: .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule()
                                            .fill(customization.fontDesign == design
                                                ? Color.primary.opacity(0.12)
                                                : Color.primary.opacity(0.04))
                                    )
                                    .foregroundColor(customization.fontDesign == design ? .primary : .secondary)
                            }
                        }
                    }
                }
            }

            // Font weight
            VStack(alignment: .leading, spacing: 6) {
                Text(L("share.font_weight"))
                    .font(.subheadline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ShareFontWeight.allCases) { weight in
                            Button {
                                customization.fontWeight = weight
                            } label: {
                                Text(weight.displayName)
                                    .font(.system(size: 13, weight: weight.weight))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule()
                                            .fill(customization.fontWeight == weight
                                                ? Color.primary.opacity(0.12)
                                                : Color.primary.opacity(0.04))
                                    )
                                    .foregroundColor(customization.fontWeight == weight ? .primary : .secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(sectionBackground)
    }

    // MARK: - Lyrics Section

    private var lyricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L("share.section_lyrics"), icon: "text.quote")

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("share.lyrics_lines"))
                        .font(.subheadline)
                    Spacer()
                    Text("\(customization.lyricsLineCount)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(customization.lyricsLineCount) },
                        set: { customization.lyricsLineCount = Int($0) }
                    ),
                    in: 1...13,
                    step: 1
                )
            }
        }
        .padding(16)
        .background(sectionBackground)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.primary)
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.04))
    }
}
