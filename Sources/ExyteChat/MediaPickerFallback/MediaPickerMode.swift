import Foundation

public enum MediaPickerMode: Equatable {

    case photos
    case albums
    case album(Album)
    case camera
    case cameraSelection

    public static func == (lhs: MediaPickerMode, rhs: MediaPickerMode) -> Bool {
        switch (lhs, rhs) {
        case (.photos, .photos):
            return true
        case (.albums, .albums):
            return true
        case (.album(let a1), .album(let a2)):
            return a1.id == a2.id
        case (.camera, .camera):
            return true
        case (.cameraSelection, .cameraSelection):
            return true
        default:
            return false
        }
    }
}

import Foundation
import Photos

public struct Album: Identifiable {
    public let id: String
    public let title: String?
    public let preview: PHAsset?
}

struct AlbumModel {
    let preview: AssetMediaModel?
    let source: PHAssetCollection
}

extension AlbumModel: Identifiable {
    public var id: String {
        source.localIdentifier
    }

    public var title: String? {
        source.localizedTitle
    }
}

extension AlbumModel: Equatable {}

extension AlbumModel {
    func toAlbum() -> Album {
        Album(id: id, title: title, preview: preview?.asset)
    }
}

struct AssetMediaModel {
    let asset: PHAsset
}

extension AssetMediaModel: MediaModelProtocol {

    var mediaType: MediaType? {
        switch asset.mediaType {
        case .image:
            return .image
        case .video:
            return .video
        default:
            return nil
        }
    }

    var duration: CGFloat? {
        CGFloat(asset.duration)
    }

    func getURL() async -> URL? {
        await asset.getURL()
    }

    func getThumbnailURL() async -> URL? {
        await asset.getThumbnailURL()
    }

    func getData() async throws -> Data? {
        try await asset.getData()
    }

    func getThumbnailData() async -> Data? {
        await asset.getThumbnailData()
    }
}

extension AssetMediaModel: Identifiable {
    var id: String {
        asset.localIdentifier
    }
}

extension AssetMediaModel: Equatable {
    static func ==(lhs: AssetMediaModel, rhs: AssetMediaModel) -> Bool {
        lhs.id == rhs.id
    }
}
