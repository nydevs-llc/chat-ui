//
//  MessageSticker.swift
//  Chat
//
//  Стикер в сообщении: рисуется БЕЗ пузыря, не больше 160×160 pt с сохранением
//  пропорций, время и статус — в маленькой капсуле в правом нижнем углу.
//
//  Форк не знает ни про Lottie, ни про кеш файлов: содержимое стикера рисует
//  приложение через `ChatStickerRendering.stickerContent`. Без конфигурации форк
//  показывает статичную превьюшку (`thumbnailURL`).
//

import Foundation
import CoreGraphics

public struct MessageSticker: Codable, Hashable, Sendable {
    public let id: String
    public let packId: String
    /// Основной эмодзи стикера — подпись для VoiceOver и превью ответа.
    public let emoji: String
    public let fileURL: URL
    public let thumbnailURL: URL?
    public let isAnimated: Bool
    /// Канва в пикселях; только для пропорций.
    public let pixelSize: CGSize

    public init(
        id: String,
        packId: String,
        emoji: String,
        fileURL: URL,
        thumbnailURL: URL?,
        isAnimated: Bool,
        pixelSize: CGSize
    ) {
        self.id = id
        self.packId = packId
        self.emoji = emoji
        self.fileURL = fileURL
        self.thumbnailURL = thumbnailURL
        self.isAnimated = isAnimated
        self.pixelSize = pixelSize
    }

    /// Потолок стороны стикера в ленте (контракт: 160×160 pt).
    public static let maxSide: CGFloat = 160

    /// Размер в ленте: вписываем канву в квадрат `maxSide`, сохраняя пропорции.
    public static func displaySize(for pixelSize: CGSize, maxSide: CGFloat = maxSide) -> CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0 else {
            return CGSize(width: maxSide, height: maxSide)
        }
        let scale = min(maxSide / pixelSize.width, maxSide / pixelSize.height)
        return CGSize(width: (pixelSize.width * scale).rounded(), height: (pixelSize.height * scale).rounded())
    }

    public var displaySize: CGSize { Self.displaySize(for: pixelSize) }
}
