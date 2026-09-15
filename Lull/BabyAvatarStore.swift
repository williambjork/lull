import Foundation
import UIKit

/// Persists the parent's chosen baby photo next to the sleep dataset in
/// Application Support/Lull/. Absence of the file means the bundled default
/// illustration should be shown.
enum BabyAvatarStore {
    static let fileName = "baby-avatar.jpg"

    static func directoryURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Lull", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func fileURL() throws -> URL {
        try directoryURL().appendingPathComponent(fileName)
    }

    static var hasCustomAvatar: Bool {
        (try? fileURL().path).map { FileManager.default.fileExists(atPath: $0) } ?? false
    }

    static func load() -> UIImage? {
        guard let url = try? fileURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return UIImage(data: data)
    }

    static func save(_ image: UIImage) throws {
        let prepared = squareCropped(image)
        guard let data = prepared.jpegData(compressionQuality: 0.9) else {
            throw BabyAvatarStoreError.encodingFailed
        }
        let url = try fileURL()
        try data.write(to: url, options: .atomic)
    }

    static func delete() throws {
        let url = try fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Center-crop to a square so circular avatars stay well-framed.
    private static func squareCropped(_ image: UIImage) -> UIImage {
        let size = image.size
        let side = min(size.width, size.height)
        guard side > 0 else { return image }
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        let crop = CGRect(origin: origin, size: CGSize(width: side, height: side))
        guard let cgImage = image.cgImage?.cropping(to: crop.integralScaled(by: image.scale)) else {
            return image
        }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}

enum BabyAvatarStoreError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed: "Couldn't save that photo."
        }
    }
}

private extension CGRect {
    func integralScaled(by scale: CGFloat) -> CGRect {
        CGRect(
            x: origin.x * scale,
            y: origin.y * scale,
            width: size.width * scale,
            height: size.height * scale
        ).integral
    }
}
