//
//  MediaPickerFallback.swift
//  ExyteChat
//
//  Stub types replacing ExyteMediaPicker while the dependency is disabled.
//  When re-enabling ExyteMediaPicker:
//    1. Uncomment the dependency in Package.swift
//    2. Restore `import ExyteMediaPicker` in files that need it
//    3. Delete this entire MediaPickerFallback folder
//

import SwiftUI
import UIKit

// MARK: - MediaType

public enum MediaType {
    case image
    case video
}

// MARK: - Media

public struct Media: Identifiable, Equatable {
    public let id = UUID()
    public let type: MediaType

    public init(type: MediaType = .image) {
        self.type = type
    }

    public func getThumbnailURL() async -> URL? { nil }
    public func getThumbnailData() async -> Data? { nil }
    public func getURL() async -> URL? { nil }
}

// MARK: - MediaPickerMode

public enum MediaPickerMode {
    case photos
    case albums
    case camera
    case cameraSelection
}

// MARK: - MediaPickerOrientationHandler

public typealias MediaPickerOrientationHandler = (UIDeviceOrientation) -> Void

// MARK: - SelectionParamsHolder (aliased as MediaPickerParameters)

public class SelectionParamsHolder {
    public var selectionLimit: Int = 1
    public var showFullscreenPreview: Bool = true

    public init() {}
}

// MARK: - MediaPickerTheme (Environment)

public struct MediaPickerTheme {
    public struct Main {
        public var pickerBackground: Color = Color(UIColor.systemBackground)
    }
    public var main = Main()
}

private struct MediaPickerThemeKey: EnvironmentKey {
    static let defaultValue = MediaPickerTheme()
}

public extension EnvironmentValues {
    var mediaPickerTheme: MediaPickerTheme {
        get { self[MediaPickerThemeKey.self] }
        set { self[MediaPickerThemeKey.self] = newValue }
    }
}

// MARK: - MediaPicker (stub view)

/// Stub replacement for ExyteMediaPicker.MediaPicker.
/// Renders nothing — the real picker will be restored when the dependency is re-enabled.
public struct MediaPicker<AlbumSelection: View, CameraSelection: View, CameraView: View>: View {

    @Binding var isPresented: Bool

    public init(
        isPresented: Binding<Bool>,
        didClose: (([Media]) -> Void)? = nil,
        @ViewBuilder albumSelectionBuilder: @escaping (Binding<[Media]>, AnyView, Binding<Media?>) -> AlbumSelection = { _, _, _ in AnyView(EmptyView()) as! AlbumSelection },
        @ViewBuilder cameraSelectionBuilder: @escaping (Binding<[Media]>, @escaping () -> Void, AnyView) -> CameraSelection = { _, _, _ in AnyView(EmptyView()) as! CameraSelection },
        @ViewBuilder cameraViewBuilder: @escaping (AnyView, @escaping () -> Void, @escaping () -> Void, @escaping () -> Void, @escaping () -> Void, @escaping () -> Void, @escaping () -> Void, @escaping () -> Void) -> CameraView = { _, _, _, _, _, _, _, _ in AnyView(EmptyView()) as! CameraView }
    ) {
        self._isPresented = isPresented
    }

    public var body: some View {
        EmptyView()
    }

    // MARK: - Modifier stubs

    public func didPressCancelCamera(_ action: @escaping () -> Void) -> Self { self }
    public func currentFullscreenMedia(_ binding: Binding<Media?>) -> Self { self }
    public func showLiveCameraCell() -> Self { self }
    public func setSelectionParameters(_ params: SelectionParamsHolder?) -> Self { self }
    public func pickerMode(_ binding: Binding<MediaPickerMode>) -> Self { self }
    public func orientationHandler(_ handler: @escaping MediaPickerOrientationHandler) -> Self { self }
}
