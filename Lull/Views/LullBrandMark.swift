import SwiftUI

/// Product mark from William's grandmother-and-baby artwork.
///
/// - `badge` keeps the black rounded-square presentation (matches the home-screen icon).
/// - `glyph` is white line art on a transparent background for dark inline surfaces
///   where a solid black chip would look heavy.
enum LullBrandMarkStyle {
    case badge
    case glyph
}

struct LullBrandMark: View {
    var style: LullBrandMarkStyle = .badge
    var size: CGFloat = 72

    var body: some View {
        Image(style == .badge ? "LullLogo" : "LullLogoGlyph")
            .resizable()
            .renderingMode(.original)
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Onboarding / settings brand lockup: mark + wordmark.
struct LullBrandHeader: View {
    var markSize: CGFloat = 88
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 16) {
            LullBrandMark(style: .badge, size: markSize)
            Text("Nana")
                .font(.largeTitle.bold())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Nana")
    }
}
