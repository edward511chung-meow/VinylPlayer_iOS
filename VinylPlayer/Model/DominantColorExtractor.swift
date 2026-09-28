import UIKit
import CoreImage
import SwiftUI

/// Extracts the dominant (average) color from a UIImage using Core Image.
enum DominantColorExtractor {

    /// Extract the dominant color from a UIImage.
    /// Uses CIAreaAverage for a fast GPU-accelerated average.
    static func dominantColor(from uiImage: UIImage) -> Color? {
        guard let ciImage = CIImage(image: uiImage) else { return nil }

        let extent = ciImage.extent
        guard let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: ciImage,
                                                 kCIInputExtentKey: CIVector(cgRect: extent)]) else {
            return nil
        }
        guard let outputImage = filter.outputImage else { return nil }

        // Read the single-pixel result
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        let r = Double(bitmap[0]) / 255.0
        let g = Double(bitmap[1]) / 255.0
        let b = Double(bitmap[2]) / 255.0

        return Color(red: r, green: g, blue: b)
    }

    /// Extract dominant color from raw image data (e.g. album.customCoverImageData).
    static func dominantColor(from data: Data) -> Color? {
        guard let uiImage = UIImage(data: data) else { return nil }
        return dominantColor(from: uiImage)
    }

    /// Async extraction from a remote URL. Downloads, extracts, returns on main.
    static func dominantColor(from url: URL) async -> Color? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let uiImage = UIImage(data: data) else { return nil }
            return dominantColor(from: uiImage)
        } catch {
            return nil
        }
    }

    // MARK: - Color Adaptation Helpers

    /// Darken a color for dark-mode backgrounds.
    /// `amount` 0…1, where 1 = fully black.
    static func darkened(_ color: Color, by amount: Double = 0.7) -> Color {
        let uiColor = UIColor(color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let newBrightness = b * (1.0 - amount)
        let newSaturation = min(1.0, s * 1.2) // boost saturation slightly
        return Color(hue: Double(h), saturation: Double(newSaturation), brightness: Double(newBrightness))
    }

    /// Lighten & desaturate a color for light-mode backgrounds.
    /// Produces a soft pastel tint.
    static func lightened(_ color: Color, by amount: Double = 0.7) -> Color {
        let uiColor = UIColor(color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let newBrightness = b + (1.0 - b) * amount
        let newSaturation = s * (1.0 - amount * 0.5) // desaturate for softness
        return Color(hue: Double(h), saturation: Double(newSaturation), brightness: Double(newBrightness))
    }
}
