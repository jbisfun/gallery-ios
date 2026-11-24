import FossifyCommons
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Open camera" (launchCamera()): iOS has no camera intent, so the system camera UI is shown
/// in-app and the capture is saved into the library (and into the current album when there is one).
struct CameraPicker: UIViewControllerRepresentable {
    @Environment(MediaStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let album: String?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let store = parent.store
            let album = parent.album
            Task { @MainActor in
                if let url = info[.mediaURL] as? URL {
                    store.saveNewFile(url, video: true, album: album)
                } else if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.95) {
                    store.saveNewImage(data, album: album)
                }
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
