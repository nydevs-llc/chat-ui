//
//  Created by Alex.M on 16.06.2022.
//

import ExyteMediaPicker
import UIKit

public enum AttachmentType: String, Codable {
    case image
    case video

    public var title: String {
        switch self {
        case .image:
            return "Image"
        default:
            return "Video"
        }
    }

    public init(mediaType: MediaType) {
        switch mediaType {
        case .image:
            self = .image
        default:
            self = .video
        }
    }
}

public struct Attachment: Codable, Identifiable, Hashable {
    public let id: String
    public let thumbnail: URL?
    public let thumbnailData: Data?
    public let full: URL
    public let type: AttachmentType
    public let aspectRatio: CGFloat?
    public let mimeType: String?
    public let key: Data?
    public let iv: Data?

    public init(
        id: String,
        thumbnail: URL?,
        thumbnailData: Data?,
        full: URL,
        type: AttachmentType,
        aspectRatio: CGFloat? = nil,
        mimeType: String? = nil,
        key: Data? = nil,
        iv: Data? = nil
    ) {
        self.id = id
        self.thumbnail = thumbnail
        self.thumbnailData = thumbnailData
        self.full = full
        self.type = type
        self.aspectRatio = aspectRatio
        self.mimeType = mimeType
        self.key = key
        self.iv = iv
    }

    public init(id: String, url: URL, type: AttachmentType) {
        self.init(id: id, thumbnail: url, thumbnailData: nil, full: url, type: type)
    }
}
