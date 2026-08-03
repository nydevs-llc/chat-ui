import SwiftUI

/// Фото чужой анкеты, процитированное искрой, — в переписке.
///
/// Рисует **само изображение и больше ничего**: ни полоски «переслано от…», ни
/// подписи. Решение владельца вопреки макету — в чат едет сам элемент, а не
/// мета-обвязка вокруг него, а кто автор, и так видно: это переписка с ним.
///
/// Композиция с «подвёрнутым» баблом, статусом и бейджем-искрой общая с
/// карточкой-цитатой (`MessagePublicationQuoteCardView`) — она живёт в
/// `MessageView.publicationQuoteComposition`, здесь только само фото.
///
/// - Important: зеркало `SparkPhotoReplyCardView` из `Foundation/UI` приложения.
///   Форк от него не зависит, числа продублированы вручную — правка идёт в оба
///   репозитория одним заходом, иначе одно и то же фото будет выглядеть по-разному
///   в компоузере и в переписке.
struct MessageProfilePhotoCardView: View {

    let attachment: MessagePublicationAttachment
    /// Сколько места добрать снизу под «подвёрнутый» бабл: он ложится на нижний
    /// край карточки, и без резерва накрыл бы само фото.
    let bottomReserve: CGFloat

    private enum Layout {
        static let width: CGFloat = 244
        static let height: CGFloat = 300
        static let cornerRadius: CGFloat = 20
    }

    var body: some View {
        photo
            .frame(width: Layout.width, height: Layout.height)
            .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .padding(.bottom, bottomReserve)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(attachment.accessibilityTitle)
    }

    @ViewBuilder
    private var photo: some View {
        if let url = attachment.photoURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.black.opacity(0.12)
                }
            }
        } else {
            Color.black.opacity(0.12)
        }
    }
}
