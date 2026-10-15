import SwiftUI

/// App-wide colour for each headline macro.
extension Nutrient {
    var tint: Color {
        switch self {
        case .calories: return .orange
        case .protein: return .red
        case .carbs: return .blue
        case .fat: return .yellow
        default: return .accentColor
        }
    }
}

/// Circular gauge showing calories eaten versus the daily target.
struct CalorieRing: View {
    var eaten: Double
    var target: Double
    var lineWidth: CGFloat = 14

    private var fraction: Double { target > 0 ? min(eaten / target, 1) : 0 }
    private var remaining: Double { target - eaten }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    remaining < 0 ? Color.red : Nutrient.calories.tint,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: fraction)
            VStack(spacing: 2) {
                Text(Format.kcal(abs(remaining)))
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text(remaining >= 0 ? "remaining" : "over")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("calories.accessibility \(Format.kcal(eaten)) \(Format.kcal(target))"))
    }
}

/// Horizontal progress bar for one macro.
struct MacroBar: View {
    var nutrient: Nutrient
    var eaten: Double
    var target: Double

    private var fraction: Double { target > 0 ? min(eaten / target, 1) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(nutrient.shortName)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(Format.grams(eaten)) / \(Format.grams(target)) g")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(nutrient.tint.opacity(0.2))
                    Capsule()
                        .fill(eaten > target ? Color.red : nutrient.tint)
                        .frame(width: proxy.size.width * fraction)
                        .animation(.easeOut(duration: 0.4), value: fraction)
                }
            }
            .frame(height: 8)
        }
    }
}

/// Row showing a nutrient amount and, when known, progress against the
/// reference daily intake.
struct NutrientProgressRow: View {
    var nutrient: Nutrient
    var amount: Double
    var target: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(nutrient.localizedName)
                Spacer()
                Text(Format.amount(amount, of: nutrient))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if let target, target > 0 {
                    Text(Format.percent(amount / target))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(color(for: amount / target))
                        .frame(width: 44, alignment: .trailing)
                }
            }
            if let target, target > 0 {
                ProgressView(value: min(amount / target, 1))
                    .tint(color(for: amount / target))
            }
        }
    }

    private func color(for fraction: Double) -> Color {
        if nutrient.isLimit {
            return fraction > 1 ? .red : (fraction > 0.8 ? .orange : .green)
        }
        return fraction >= 1 ? .green : (fraction >= 0.5 ? .orange : .secondary)
    }
}

/// Rounded card background used by dashboard sections.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

/// Compact macro summary, e.g. "P 20 · C 35 · F 10".
struct MacroSummaryText: View {
    var nutrients: NutrientProfile

    var body: some View {
        Text(verbatim: "P \(Format.grams(nutrients.protein)) · C \(Format.grams(nutrients.carbs)) · F \(Format.grams(nutrients.fat))")
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}

#if canImport(UIKit)
import UIKit

/// Camera picker bridged from UIKit; the Photos picker covers the library.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif

/// Platform-neutral helpers for turning picked images into JPEG data sized
/// for the API (long edge limited to keep requests small).
enum ImageEncoding {
    static let maxDimension: CGFloat = 1280

    #if canImport(UIKit)
    static func jpegData(from image: UIImage) -> Data? {
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.8)
    }
    #endif
}
