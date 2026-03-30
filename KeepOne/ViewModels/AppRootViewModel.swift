import Foundation
import Photos

@MainActor
final class AppRootViewModel: ObservableObject {
    enum PermissionState: Equatable {
        case unknown
        case denied
        case authorized
        case limited
    }

    @Published private(set) var permissionState: PermissionState = .unknown
    @Published private(set) var isRequestingPermission = false

    private let photoLibraryService: any PhotoLibraryServiceProtocol

    init(photoLibraryService: any PhotoLibraryServiceProtocol) {
        self.photoLibraryService = photoLibraryService
    }

    func refreshAuthorizationStatus() {
        permissionState = Self.map(status: photoLibraryService.authorizationStatus())
    }

    func requestPermission() async {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        let status = await photoLibraryService.requestAuthorization()
        permissionState = Self.map(status: status)
        isRequestingPermission = false
    }

    private static func map(status: PHAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized:
            return .authorized
        case .limited:
            return .limited
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .unknown
        @unknown default:
            return .denied
        }
    }
}
