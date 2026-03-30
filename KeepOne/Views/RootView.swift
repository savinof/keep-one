import SwiftUI
import UIKit

struct RootView: View {
    @StateObject private var viewModel: AppRootViewModel
    @EnvironmentObject private var container: AppContainer

    init(photoLibraryService: any PhotoLibraryServiceProtocol) {
        _viewModel = StateObject(
            wrappedValue: AppRootViewModel(photoLibraryService: photoLibraryService)
        )
    }

    var body: some View {
        NavigationStack {
            switch viewModel.permissionState {
            case .unknown:
                PermissionView(
                    title: "Allow Photo Access",
                    message: "KeepOne only analyzes a month when you ask. It never auto-deletes photos.",
                    buttonTitle: "Grant Access",
                    isLoading: viewModel.isRequestingPermission,
                    action: {
                        Task { await viewModel.requestPermission() }
                    }
                )

            case .denied:
                PermissionView(
                    title: "Photo Access Needed",
                    message: "Enable Photos access in Settings to review similar photo groups safely.",
                    buttonTitle: "Open Settings",
                    isLoading: false,
                    action: {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                )

            case .authorized, .limited:
                YearListView(
                    viewModel: YearListViewModel(photoLibraryService: container.photoLibraryService)
                )
            }
        }
        .task {
            viewModel.refreshAuthorizationStatus()
        }
    }
}
