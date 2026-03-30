import SwiftUI

@main
struct KeepOneApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView(photoLibraryService: container.photoLibraryService)
                .environmentObject(container)
        }
    }
}
