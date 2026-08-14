//
//  VoicePlayerEnvironment.swift
//
//  Общий плеер голосовых, живущий НАД ячейкой списка.
//

import SwiftUI

/// Общий плеер переписки. `nil` — общего нет, строка играет сама.
///
/// Ключ намеренно НЕОБЯЗАТЕЛЬНЫЙ, и это не осторожность, а требование:
///
/// 1. Содержимое `UIHostingConfiguration` — новый корень SwiftUI-дерева, он не
///    наследует окружение от `ChatView`. `@EnvironmentObject` без явной
///    инжекции внутри замыкания ячейки уронил бы приложение в рантайме.
/// 2. Форк рисует волну не только в ленте переписки: карточка-цитата
///    публикации, бар ввода, превью. Там общего плеера нет и не нужно —
///    строка обязана продолжать работать по-старому.
private struct SharedVoicePlayerKey: EnvironmentKey {
    static var defaultValue: RecordingPlayer? { nil }
}

extension EnvironmentValues {
    var sharedVoicePlayer: RecordingPlayer? {
        get { self[SharedVoicePlayerKey.self] }
        set { self[SharedVoicePlayerKey.self] = newValue }
    }
}

extension View {
    /// Отдаёт поддереву общий плеер голосовых.
    ///
    /// Вызывается ВНУТРИ замыкания `UIHostingConfiguration` (см. `SonataUIList`),
    /// потому что ячейка не наследует окружение списка.
    func sharedVoicePlayer(_ player: RecordingPlayer?) -> some View {
        environment(\.sharedVoicePlayer, player)
    }
}
