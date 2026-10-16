//
//  MessageVideoNote.swift
//  Chat
//
//  Видеосообщение-кружок (по мотивам Telegram): рисуется БЕЗ пузыря, кругом
//  212 pt (240 на планшете), по тапу со звуком увеличивается до
//  min(404, ширина − 20). Время со статусом — в капсуле сбоку внизу.
//
//  Форк не знает ни про AVPlayer, ни про кеш файлов: содержимое круга рисует
//  приложение (`ChatVideoNoteRendering.content`). Без конфигурации форк рисует
//  нейтральный круг с длительностью.
//

import Foundation
import CoreGraphics

public struct MessageVideoNote: Codable, Hashable, Sendable {

    /// Идентификатор файла на бэкенде (у черновика — `draft-<guid>`).
    public let fileId: String
    public let durationMs: Int
    /// Входящий и ещё не просмотрен со звуком — точка «не просмотрено».
    public var isUnseen: Bool
    /// Модерация отклонила (`moderation: rejected`). У получателя — заглушка,
    /// у отправителя — своё видео под блюром с красной подписью.
    public var isRemoved: Bool
    /// Играет со звуком и увеличен (смена размера ячейки идёт через `==`).
    public var isEnlarged: Bool

    public init(
        fileId: String,
        durationMs: Int,
        isUnseen: Bool = false,
        isRemoved: Bool = false,
        isEnlarged: Bool = false
    ) {
        self.fileId = fileId
        self.durationMs = durationMs
        self.isUnseen = isUnseen
        self.isRemoved = isRemoved
        self.isEnlarged = isEnlarged
    }

    /// Диаметр в ленте (контракт: 212 на телефоне, 240 на планшете).
    public static func baseDiameter(isRegularWidth: Bool) -> CGFloat {
        isRegularWidth ? 240 : 212
    }

    /// Диаметр увеличенного кружка: min(404, ширина ленты − 20).
    public static func enlargedDiameter(listWidth: CGFloat) -> CGFloat {
        max(0, min(404, listWidth - 20))
    }

    /// `m:ss` (`h:mm:ss` дольше часа).
    public static func formatDuration(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
