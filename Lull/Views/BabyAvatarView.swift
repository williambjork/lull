import PhotosUI
import SwiftUI
import UIKit

/// Round baby portrait used on Home and in Settings. Shows the parent's photo
/// when one is saved; otherwise the bundled soft-illustration placeholder.
struct BabyAvatarView: View {
    let image: UIImage?
    var size: CGFloat = 44
    var showsEditBadge: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image("DefaultBabyAvatar")
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )

            if showsEditBadge {
                Image(systemName: "camera.fill")
                    .font(.system(size: max(9, size * 0.18), weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.75))
                    .padding(max(4, size * 0.08))
                    .background(Theme.awakeAccent, in: Circle())
                    .offset(x: 2, y: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(image == nil ? "Default baby illustration" : "Baby photo")
    }
}

/// Tappable avatar that offers library / camera / remove.
struct BabyAvatarButton: View {
    @Environment(AppModel.self) private var model
    var size: CGFloat = 44
    var showsEditBadge: Bool = true

    @State private var showingOptions = false
    @State private var showingLibraryPicker = false
    @State private var showingCamera = false
    @State private var libraryItem: PhotosPickerItem?

    var body: some View {
        Button {
            showingOptions = true
        } label: {
            BabyAvatarView(
                image: model.babyAvatarImage,
                size: size,
                showsEditBadge: showsEditBadge
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Change baby photo")
        .confirmationDialog("Baby photo", isPresented: $showingOptions, titleVisibility: .visible) {
            Button("Choose from Library") { showingLibraryPicker = true }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") { showingCamera = true }
            }
            if model.hasCustomBabyAvatar {
                Button("Remove Photo", role: .destructive) { model.clearBabyAvatar() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shown as a round avatar on the home screen.")
        }
        .photosPicker(
            isPresented: $showingLibraryPicker,
            selection: $libraryItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                await loadLibraryItem(item)
                libraryItem = nil
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in
                if let image {
                    model.setBabyAvatar(image)
                }
            }
            .ignoresSafeArea()
        }
    }

    private func loadLibraryItem(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else { return }
            await MainActor.run { model.setBabyAvatar(image) }
        } catch {
            await MainActor.run { model.errorMessage = error.localizedDescription }
        }
    }
}

/// Thin UIKit camera wrapper — PhotosPicker covers the library; camera still
/// needs UIImagePickerController on device.
struct CameraPicker: UIViewControllerRepresentable {
    var onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
            picker.dismiss(animated: true)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            onFinish(image)
            picker.dismiss(animated: true)
        }
    }
}
