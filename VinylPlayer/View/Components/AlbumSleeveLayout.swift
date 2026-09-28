import SwiftUI

/// A square sleeve with a nearly equal-sized record pulled halfway out.
/// Artwork proportions scale with the grid cell rather than clipping the record.
struct AlbumSleeveLayout<Cover: View>: View {
    let vinylColors: [Color]
    let vinylOpacity: Double
    let labelColor: Color
    var adaptsDefaultVinyl = false
    @Environment(\.colorScheme) private var colorScheme

    private var usesPearlVinyl: Bool { adaptsDefaultVinyl && colorScheme == .dark }
    private var discColors: [Color] {
        usesPearlVinyl
            ? [Color(white: 0.70), Color(white: 0.86), Color(white: 0.76)]
            : vinylColors
    }
    @ViewBuilder var cover: (CGFloat) -> Cover

    var body: some View {
        GeometryReader { geometry in
            let sleeve = geometry.size.width / 1.56
            let disc = sleeve * 0.98
            ZStack(alignment: .leading) {
                Circle()
                    .fill(RadialGradient(colors: discColors, center: .center,
                                         startRadius: 0, endRadius: disc / 2))
                    .opacity(vinylOpacity)
                    .overlay {
                        // Static grooves and broad reflections keep small cards inexpensive.
                        ZStack {
                            ForEach(0..<16, id: \.self) { index in
                                Circle().stroke(
                                    usesPearlVinyl
                                        ? Color.black.opacity(index.isMultiple(of: 3) ? 0.09 : 0.035)
                                        : Color.white.opacity(index.isMultiple(of: 3) ? 0.16 : 0.07),
                                    lineWidth: 0.5)
                                    .padding(disc * (0.04 + CGFloat(index) * 0.018))
                            }
                            Circle().fill(AngularGradient(colors: [.clear, .white.opacity(0.24), .clear,
                                                                   .white.opacity(0.12), .clear], center: .center))
                            Circle().fill(labelColor.gradient)
                                .frame(width: disc * 0.34, height: disc * 0.34)
                                .overlay(Circle().stroke(.black.opacity(0.2), lineWidth: 0.5))
                            Circle().fill(Color(white: 0.2))
                                .frame(width: disc * 0.025, height: disc * 0.025)
                        }
                    }
                    .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 0.5))
                    .frame(width: disc, height: disc)
                    .offset(x: sleeve * 0.58)
                cover(sleeve)
                    .frame(width: sleeve, height: sleeve)
                    .shadow(color: .black.opacity(0.24), radius: 2, x: 2, y: 0)
            }
            .frame(width: geometry.size.width, height: sleeve, alignment: .leading)
        }
        .aspectRatio(1.56, contentMode: .fit)
    }
}

#Preview("Sleeve proportions") {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
        ForEach(0..<4) { index in
            AlbumSleeveLayout(vinylColors: index == 0 ? [.white, .gray] : [.gray, .black],
                              vinylOpacity: 1, labelColor: .pink) { side in
                ZStack {
                    LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text("ENCORE").font(.system(size: side * 0.12, weight: .semibold, design: .serif)).foregroundStyle(.white)
                }.frame(width: side, height: side)
            }
        }
    }.padding(16)
}
