import SwiftUI
import PhotosUI

struct ContentView: View {
  @State private var selectedItem: PhotosPickerItem?
  @State private var selectedImageData: Data?

  var body: some View {
    VStack {
      PhotosPicker("Select a photo", selection: $selectedItem, matching: .images)
        .onChange(of: selectedItem) { _, newItem in
          Task {
            selectedImageData = try? await newItem?.loadTransferable(type: Data.self)
          }
        }
      if let selectedImageData, let uiImage = UIImage(data: selectedImageData) {
        Image(uiImage: uiImage).resizable().scaledToFit()
      }
    }
  }
}
