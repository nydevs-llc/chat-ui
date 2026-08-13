//
//  MessageView.swift
//  Chat
//
//  Created by Alex.M on 23.05.2022.
//

import SwiftUI
import MapKit

struct MessageView: View {

    @Environment(\.chatTheme) private var theme

    @ObservedObject var viewModel: ChatViewModel

    let message: Message
    let positionInUserGroup: PositionInUserGroup
    let positionInMessagesSection: PositionInMessagesSection
    let chatType: ChatType
    let avatarSize: CGFloat
    let tapAvatarClosure: ChatView.TapAvatarClosure?
    let messageUseMarkdown: Bool
    let isDisplayingMessageMenu: Bool
    let showMessageTimeView: Bool
    let isGroup: Bool
    let tapDocumentClosure: ChatView.TapDocumentClosure?
    let groupUsers: [User]
    
    @State var avatarViewSize: CGSize = .zero
    @State var statusSize: CGSize = .zero
    @State var timeSize: CGSize = .zero
    @State var bubbleSize: CGSize = .zero
    /// Измеренный размер подвёрнутого пузыря ответа на публикацию-цитату.
    /// Нужен ровно для одного — посчитать, на сколько нарастить карточку, чтобы
    /// пузырь лёг на её пустоту, а не на текст ответа (`quoteCardBottomReserve`).
    @State private var quoteReplyBubbleSize: CGSize = .zero
    static let widthWithMedia: CGFloat = 204
    static let horizontalNoAvatarPadding: CGFloat = 16 //or 8
    static let horizontalAvatarPadding: CGFloat = 8
    static let horizontalTextPadding: CGFloat = 12
    static let horizontalAttachmentPadding: CGFloat = 1 // for multiple attachments
    static let statusViewSize: CGFloat = 14
    static let horizontalStatusPadding: CGFloat = 8
    static let horizontalBubblePadding: CGFloat = 70

    // Композиция «ответ на публикацию-цитату» (макет)
    //
    // ⚠️ Значения — зеркало компоузера приложения (`SparkSecretReplyCardView`:
    // `bubbleOverhang = 18`, `.offset(y: 14)`). Один и тот же секрет обязан
    // выглядеть одинаково на экране отправки и в переписке, поэтому правка
    // подворота обязана идти в оба места одним заходом.
    static let quoteCardWidth: CGFloat = 236
    /// На сколько пузырь ответа НАЕЗЖАЕТ на карточку снизу.
    ///
    /// Фиксируется именно перекрытие, а не «сколько висит ниже»: по макету
    /// пузырь лежит на самом краю карточки и уходит вниз всей остальной высотой,
    /// поэтому от числа строк в реплике должен меняться свес, а не наезд.
    /// Константный свес (как было) на однострочной реплике загонял пузырь
    /// внутрь карточки, на двухстрочной — наоборот, отрывал.
    static let quoteReplyOverlap: CGFloat = 20
    /// На сколько пузырь ответа выходит за ЛЕВУЮ границу карточки.
    ///
    /// Влево в обе стороны переписки, а не зеркально по автору: пузырь висит на
    /// карточке-цитате, а у карточки закрывающая кавычка нарисована в правом
    /// нижнем углу — подворот справа накрывал бы именно её. Так же и в макете
    /// («Ответ на секрет», `left: -6`), и в компоузере.
    ///
    /// Значение из макета (`left: -6`), а НЕ компоузерные 18: 18 уводили бы
    /// композицию за край экрана тем сильнее, чем шире свес.
    ///
    /// ⚠️ Прежняя редакция этого комментария обосновывала выбор так: «у входящего
    /// карточка стоит в 30pt от края экрана, и 6 + 8 = 14 держат бейдж на виду».
    /// Обе посылки неверны. Отступ строки от края в диалоге 1-на-1 —
    /// `horizontalTextPadding` (12pt, `avatarView` подставляет Spacer вместо
    /// аватара), а не 30. И бейдж вынесен не на 8, а на `SparkReplyBadge.overhang`
    /// (14) ОТ ПУЗЫРЯ, который сам уже сдвинут на эти 6: суммарно 20 от карточки.
    /// Итог 12 − 6 − 14 = −8pt — кружок реально срезало левым краем экрана.
    /// Лечится не сдвигом бейджа (он привязан к левому краю текста реплики), а
    /// резервом у самой композиции — см. `quoteReplyLeftBleed`.
    static let quoteReplyOverhang: CGFloat = 6
    /// Запас слева под то, что композиция «кровит» за свой левый край.
    ///
    /// Ни свес пузыря (`offset`), ни бейдж (`overlay`) в раскладке места не
    /// занимают, поэтому строка сообщения о них не знает и прижимает карточку к
    /// штатному отступу — кружок уходит за экран. Резерв возвращает ровно
    /// недостающее: свес плюс вынос бейджа минус отступ, который у строки уже есть.
    ///
    /// Выражен через `SparkReplyBadge.overhang`, а не числом: вынос бейджа и этот
    /// резерв обязаны меняться вместе, иначе кружок снова уедет за край.
    static let quoteReplyLeftBleed: CGFloat = max(
        0,
        quoteReplyOverhang + SparkReplyBadge.overhang - horizontalTextPadding
    )
    /// Просвет между последней строкой ответа и верхом пузыря: без него резерв
    /// подводит текст ВПЛОТНУЮ к пузырю — формально не накрыт, читается слипшимся.
    static let quoteReplyClearance: CGFloat = 10
    /// Колонка справа, которую пузырь не занимает, — там живёт закрывающая
    /// кавычка карточки (глиф ~37pt + 10pt отступа от края).
    ///
    /// Без ограничения пузырь на длинной реплике дотягивался до правого края и
    /// закрывал кавычку целиком: она ниже его верхней границы, потому что
    /// карточка обнимает контент, а на макете кавычка в 150px торчит над
    /// пузырём сама.
    static let quoteGlyphColumn: CGFloat = 46
    /// Ширина, по которой переносится текст пузыря ответа НА ЦИТАТУ (секрет,
    /// вопрос дня, публикация) — у такой карточки справа висит кавычка.
    static let quoteReplyBubbleMaxWidth: CGFloat = quoteCardWidth - quoteGlyphColumn
    /// То же для ответа на ФОТО АНКЕТЫ.
    ///
    /// У фото-карточки декоративной кавычки нет вовсе, а сама она шире (244 против
    /// 236), поэтому вычитать `quoteGlyphColumn` здесь не из чего: 46pt
    /// резервировались впустую. Реплика «Привет, как дела?» из-за этого не влезала
    /// в строку, промахиваясь на доли пункта (134.4pt текста при 134.0pt доступных),
    /// и ломалась на две строки при явно свободном месте справа.
    static let photoReplyBubbleMaxWidth: CGFloat = MessageProfilePhotoCardView.cardWidth
    /// Всё, что в голосовом пузыре занимает ширину помимо самой волны:
    /// кнопка play (40) + зазор `HStack` (12) + горизонтальные паддинги
    /// `recordingView` (12 × 2). Считается по фактическим значениям, а не на глаз.
    static let voiceBubbleChrome: CGFloat = 40 + 12 + horizontalTextPadding * 2
    /// Пол ширины ВОЛНЫ — чтобы запись в секунду не схлопывалась в огрызок
    /// вокруг кнопки: под волной ещё стоит таймер, ему нужна строка.
    static let voiceWaveformMinWidth: CGFloat = 80
    /// Колонка справа внутри пузыря под галочки статуса: 14pt глифа + просвет.
    ///
    /// Просвет щедрый намеренно: галочки стоят на одной строке с текстом у
    /// короткой реплики, и на 8pt они читались как «приклеенные» к последнему
    /// слову — почти как часть слова.
    static let quoteReplyStatusColumn: CGFloat = 28
    /// #FFCB52
    static let quoteReplyOutgoingTop = Color(red: 255 / 255, green: 203 / 255, blue: 82 / 255)
    /// #F0982B
    static let quoteReplyOutgoingBottom = Color(red: 240 / 255, green: 152 / 255, blue: 43 / 255)
    /// #3A2606
    static let quoteReplyOutgoingText = Color(red: 58 / 255, green: 38 / 255, blue: 6 / 255)

    var font: UIFont

    enum DateArrangement {
        case hstack, vstack, overlay
    }

    var additionalMediaInset: CGFloat {
        message.attachments.count > 1 ? MessageView.horizontalAttachmentPadding * 2 : 0
    }

    var dateArrangement: DateArrangement {
        let timeWidth = timeSize.width + 10
        let textPaddings = MessageView.horizontalTextPadding * 2
        let widthWithoutMedia = UIScreen.main.bounds.width
        - (message.user.isCurrentUser ? MessageView.horizontalNoAvatarPadding : avatarViewSize.width)
        - statusSize.width
        - MessageView.horizontalBubblePadding
        - textPaddings

        let maxWidth = message.attachments.isEmpty ? widthWithoutMedia : MessageView.widthWithMedia - textPaddings
        let finalWidth = message.text.width(withConstrainedWidth: maxWidth, font: font, messageUseMarkdown: messageUseMarkdown)
        let lastLineWidth = message.text.lastLineWidth(labelWidth: maxWidth, font: font, messageUseMarkdown: messageUseMarkdown)
        let numberOfLines = message.text.numberOfLines(labelWidth: maxWidth, font: font, messageUseMarkdown: messageUseMarkdown)

        if numberOfLines == 1, finalWidth + CGFloat(timeWidth) < maxWidth {
            return .hstack
        }
        if lastLineWidth + CGFloat(timeWidth) < finalWidth {
            return .overlay
        }
        return .vstack
    }

    var showAvatar: Bool {
        positionInUserGroup == .single
        || (chatType == .conversation && positionInUserGroup == .last)
        || (chatType == .comments && positionInUserGroup == .first)
    }

    var topPadding: CGFloat {
        if chatType == .comments { return 0 }
        return positionInUserGroup.isTop && !positionInMessagesSection.isTop ? 8 : 4
    }

    var bottomPadding: CGFloat {
        if chatType == .conversation { return 0 }
        return positionInUserGroup.isTop ? 8 : 4
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if !message.user.isCurrentUser {
                avatarView
            }

            VStack(alignment: message.user.isCurrentUser ? .trailing : .leading, spacing: 2) {
                if !isDisplayingMessageMenu, let reply = message.replyMessage?.toMessage() {
                    replyBubbleView(reply)
                        .opacity(0.5)
                        .padding(message.user.isCurrentUser ? .trailing : .leading, 10)
                        .overlay(alignment: message.user.isCurrentUser ? .trailing : .leading) {
                            Capsule()
                                .foregroundColor(theme.colors.buttonBackground)
                                .frame(width: 2)
                        }
                }
                
                if !message.user.isCurrentUser && (positionInUserGroup == .single || (chatType == .conversation && positionInUserGroup == .first)) && isGroup {
                    Text(message.user.name)
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .label.withAlphaComponent(0.7)))
                        .offset(x: 8.0)
                }
                
                bubbleView(message)
            }
        }
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .padding(.trailing, message.user.isCurrentUser ? MessageView.horizontalNoAvatarPadding : 0)
        .padding(message.user.isCurrentUser ? .leading : .trailing, MessageView.horizontalBubblePadding)
        .frame(maxWidth: UIScreen.main.bounds.width, alignment: message.user.isCurrentUser ? .trailing : .leading)
    }

    /// Единственная развилка: публикация-цитата (у неё есть вопрос или голос)
    /// рисуется собственной композицией — карточка сама себе фон + пузырь ответа
    /// ПОВЕРХ неё с выходом за границу, — потому что штатный `bubbleView`
    /// складывает содержимое вертикально ВНУТРИ подложки пузыря.
    ///
    /// Публикация без вопроса и голоса (свободный пост) сюда НЕ попадает и идёт
    /// прежним путём, компактной полоской внутри обычного пузыря: развилка стоит
    /// на `showsQuoteCard`, а не на самом факте вложения. Все остальные типы
    /// сообщений тоже идут прежним путём — тело `standardBubbleView` перенесено
    /// без единого изменения.
    @ViewBuilder
    func bubbleView(_ message: Message) -> some View {
        if let publication = message.publicationAttachment, publication.showsQuoteCard {
            publicationQuoteComposition(message, publication)
        } else {
            standardBubbleView(message)
        }
    }

    @ViewBuilder
    private func standardBubbleView(_ message: Message) -> some View {
        VStack(
            alignment: message.user.isCurrentUser ? .leading : .trailing,
            spacing: -bubbleSize.height / 3
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if !message.attachments.isEmpty {
                    attachmentsView(message)
                }

                if let pubAttachment = message.publicationAttachment {
                    MessagePublicationCardView(
                        attachment: pubAttachment,
                        isOutgoing: message.user.isCurrentUser
                    )
                    .padding(.horizontal, 6)
                    .padding(.top, 6)
                }

                if message.type == .geo {
                    VStack(alignment: .trailing, spacing: 8) {
                        locationView(message)
                    }
                }
                
                if !message.text.isEmpty && message.type != .document && message.type != .geo {
                    textWithTimeView(message)
                        .font(Font(font))
                }
                
                if let recording = message.recording {
                    // Статус НАКЛАДЫВАЕТСЯ на блок записи, а не идёт следующей
                    // строкой стека. Длительность внутри `recordingView` стоит
                    // внизу СЛЕВА, справа от неё пусто — туда и садится галочка,
                    // визуально на одной строке с длительностью.
                    //
                    // Прежний `VStack` отдавал статусу отдельную строку: пузырь
                    // становился выше на целую строку, а галочка висела под
                    // волной сама по себе и читалась как чужеродный элемент.
                    recordingView(recording)
                        .padding(.bottom, 10)
                        .overlay(alignment: .bottomTrailing) {
                            // Отступы больше, чем у текстового пузыря: там статус
                            // стоит в потоке за текстом, а здесь висит в углу, где
                            // скругление съедает видимое расстояние до края.
                            messageTimeView()
                                .padding(.trailing, MessageView.horizontalTextPadding)
                                .padding(.bottom, 6)
                        }
                }
                
                if message.type == .document {
                    VStack(alignment: .trailing, spacing: 8) {
                        documentView(message)
                            .highPriorityGesture(TapGesture().onEnded {
                                tapDocumentClosure?(message.user, message.id)
                            })
                        messageTimeView()
                            .padding(.bottom, 8)
                            .padding(.trailing, 12)
                    }
                }

                // Дефект 3 (P10): у голосового текст пустой по конструкции — если
                // `recording` по любой причине `nil` (расхождение кеша, провал
                // encode и т.п.), НИ ОДНА из веток выше не срабатывает, стек
                // остаётся пустым, и `bubbleBackground` тоже не рисует заливку
                // (см. её собственное условие) — сообщение существует в списке,
                // но занимает 0pt высоты: выглядит как полностью пропавшее.
                // Плейсхолдер здесь чисто графический (иконка, без текста):
                // у форка нет доступа к нашей локализации на 6 языков, а любой
                // хардкод видимого текста в форке запрещён. Смысл — сделать
                // потерю ВИДИМОЙ, а не восстановить содержимое (сам фикс кеша —
                // отдельная задача).
                if !MessageView.hasRenderableContent(message) {
                    missingContentPlaceholderView()
                }
            }
            .bubbleBackground(message, theme: theme)
            .zIndex(0)
            
            if !isDisplayingMessageMenu && !message.reactions.isEmpty && !message.isDeleted {
                reactionsView(message)
                    .zIndex(1)
            }
        }
        .applyIf(isDisplayingMessageMenu) {
            $0.frameGetter($viewModel.messageFrame)
        }
    }

    /// Дефект 3 (P10): true, если хотя бы одна ветка `standardBubbleView` ниже
    /// нарисует что-то видимое. Список условий продублирован намеренно, а не
    /// вынесен в общий helper — правки этого списка (новый тип вложения) и так
    /// требуют трогать оба места одновременно, дублирование делает пропуск
    /// заметным при ревью, а не молчаливым.
    static func hasRenderableContent(_ message: Message) -> Bool {
        !message.attachments.isEmpty
            || message.publicationAttachment != nil
            || message.type == .geo
            || !message.text.isEmpty
            || message.recording != nil
            || message.type == .document
    }

    /// Нейтральный ГРАФИЧЕСКИЙ плейсхолдер без текста — умышленно: у форка нет
    /// нашей локализации на 6 языков, а хардкод видимой строки здесь запрещён.
    /// Задача — не восстановить содержимое (это отдельный фикс кеша), а не дать
    /// пузырю схлопнуться в 0pt, из-за чего потеря вложения выглядела как
    /// полное исчезновение сообщения.
    @ViewBuilder
    private func missingContentPlaceholderView() -> some View {
        Image(systemName: "questionmark.circle")
            .font(.system(size: 20, weight: .medium))
            .frame(width: 44, height: 44)
            .overlay(alignment: .bottomTrailing) {
                messageTimeView()
                    .padding(.trailing, MessageView.horizontalTextPadding)
                    .padding(.bottom, 6)
            }
    }

    // MARK: - Publication quote card

    /// Карточка-цитата публикации + подвёрнутый снизу пузырь ответа. Пузырь лежит
    /// ПОВЕРХ карточки и выходит за её ЛЕВУЮ границу — в обе стороны переписки,
    /// как в компоузере и в макете. Штатная подложка `bubbleBackground` здесь
    /// не применяется — карточка сама себе фон.
    ///
    /// Высота композиции = высота карточки + подворот, и подворот резервируется
    /// только когда пузырь есть: у ответа без текста (например, голосом) лишние
    /// 14pt под карточкой были бы мёртвой полосой в ленте.
    @ViewBuilder
    private func publicationQuoteComposition(
        _ message: Message,
        _ publication: MessagePublicationAttachment
    ) -> some View {
        VStack(
            alignment: message.user.isCurrentUser ? .leading : .trailing,
            spacing: 0
        ) {
            ZStack(alignment: .bottomLeading) {
                // Развилка ТОЛЬКО по самой карточке. Всё остальное — подворот,
                // бабл, статус, бейдж-искра — общее: композиция настраивалась
                // двумя кругами приёмки, и расщеплять её по видам нельзя.
                Group {
                    if publication.kind == .photo {
                        MessageProfilePhotoCardView(
                            attachment: publication,
                            bottomReserve: quoteCardBottomReserve(message)
                        )
                    } else {
                        MessagePublicationQuoteCardView(
                            attachment: publication,
                            isOutgoing: message.user.isCurrentUser,
                            bottomReserve: quoteCardBottomReserve(message)
                        )
                    }
                }
                .padding(.bottom, quoteReplyTuck(message))

                if !message.text.isEmpty {
                    // Ширина строки = ширина карточки: пузырь обжимает свой текст,
                    // но перенос считается по 236pt, а не по всей доступной
                    // ширине экрана. `alignment: .leading` — чтобы короткая
                    // реплика прижималась к левому краю карточки, а не центру.
                    quoteReplyBubble(message)
                        .sizeGetter($quoteReplyBubbleSize)
                        .frame(maxWidth: replyBubbleMaxWidth(publication), alignment: .leading)
                        .offset(x: -MessageView.quoteReplyOverhang)
                } else if let recording = message.recording {
                    // Голосовая искра. Без этой ветки запись просто пропадала:
                    // текст у неё пуст по построению, ветка выше не срабатывала,
                    // а `message.recording` в этой композиции не читался вовсе —
                    // на экране оставалась одна карточка анкеты, и отправитель
                    // видел «искра ушла, а сообщения нет».
                    // Без внешнего `maxWidth`: ширину пузырь считает сам по длине
                    // записи (`voiceBubbleContentWidth`), иначе волна растянулась
                    // бы на всю карточку и вокруг неё осталась пустая заливка.
                    quoteReplyVoiceBubble(recording, message)
                        .sizeGetter($quoteReplyBubbleSize)
                        .offset(x: -MessageView.quoteReplyOverhang)
                }
            }
            .zIndex(0)

            if !isDisplayingMessageMenu && !message.reactions.isEmpty && !message.isDeleted {
                reactionsView(message)
                    .zIndex(1)
            }
        }
        // Резерв под «кровотечение» композиции влево: свес пузыря (6) + вынос
        // бейджа (14) = 20pt, а входящая строка начинается всего в 12pt от края
        // экрана — кружок срезало ровно на 8pt. См. `quoteReplyLeftBleed`.
        //
        // ТОЛЬКО у входящего: у исходящего карточка прижата к правому краю, и
        // лишний отступ слева оторвал бы её от него.
        //
        // И только когда пузырь есть: без реплики нет и бейджа, а лишний отступ
        // сдвинул бы одинокую карточку вправо относительно соседних сообщений.
        .padding(
            .leading,
            !message.user.isCurrentUser && hasQuoteReply(message)
                ? MessageView.quoteReplyLeftBleed
                : 0
        )
        .applyIf(isDisplayingMessageMenu) {
            $0.frameGetter($viewModel.messageFrame)
        }
    }

    /// Сколько пустоты добрать снизу карточки под пузырь ответа.
    ///
    /// Пузырь перекрывает карточку на `высота пузыря − подворот`. Первые
    /// `contentBottomPadding` этого перекрытия бесплатны — там у карточки и так
    /// пустой отступ; всё сверх того карточка обязана добрать, иначе пузырь
    /// накрывает последнюю строку ответа. Однострочная реплика в отступ
    /// укладывается и карточку не растит вовсе.
    ///
    /// До первого замера (`.zero`) резерв нулевой — кадр без реплики валиден сам
    /// по себе, а `sizeGetter` доводит его на следующем проходе.
    /// Ширина пузыря зависит от того, что под ним за карточка.
    ///
    /// У цитаты справа висит декоративная кавычка, и пузырь обязан оставить ей
    /// колонку. У фото анкеты кавычки нет — там доступна вся ширина карточки.
    private func replyBubbleMaxWidth(_ publication: MessagePublicationAttachment) -> CGFloat {
        publication.kind == .photo
            ? MessageView.photoReplyBubbleMaxWidth
            : MessageView.quoteReplyBubbleMaxWidth
    }

    /// Есть ли под карточкой пузырь-реплика — текстовый ИЛИ голосовой.
    ///
    /// Вся геометрия композиции (резерв под карточкой, подворот) считалась по
    /// `!text.isEmpty`, потому что другого вида реплики не существовало. У
    /// голосовой искры текст пуст, и без этой развилки карточка не оставляла
    /// места под пузырь, а пузырь не подворачивался ей под низ.
    private func hasQuoteReply(_ message: Message) -> Bool {
        !message.text.isEmpty || message.recording != nil
    }

    private func quoteCardBottomReserve(_ message: Message) -> CGFloat {
        guard hasQuoteReply(message) else { return 0 }
        return max(
            0,
            MessageView.quoteReplyOverlap + MessageView.quoteReplyClearance
                - MessagePublicationQuoteCardView.contentBottomPadding
        )
    }

    /// Свес пузыря ниже карточки = его высота минус фиксированный наезд.
    ///
    /// Пока высота не измерена (`.zero`) свеса нет: пузырь стоит по нижнему краю
    /// карточки, следующий проход `sizeGetter` опускает его на место.
    private func quoteReplyTuck(_ message: Message) -> CGFloat {
        guard hasQuoteReply(message) else { return 0 }
        return max(0, quoteReplyBubbleSize.height - MessageView.quoteReplyOverlap)
    }

    /// Статус показывается только у своего сообщения — у чужого его нет вовсе,
    /// и нижний отступ пузыря тогда обычный.
    private func quoteReplyStatus(_ message: Message) -> Message.Status? {
        message.user.isCurrentUser ? message.status : nil
    }

    /// Пузырь ответа. Статус — НЕ в потоке за текстом, а приколот к правому
    /// нижнему углу пузыря, как в макете (`right: 16px; bottom: 3px`).
    ///
    /// Inline-статус вставал сразу за последним словом: на короткой реплике
    /// («Hi ✓») он оказывался посреди пилюли и читался как часть текста, а на
    /// многострочной — прыгал по длине последней строки. В углу он стоит на
    /// одном месте при любой длине; место под него держит увеличенный нижний
    /// отступ, поэтому текст на него не наезжает.
    @ViewBuilder
    /// Ширина содержимого голосовой искры — по длине записи, а не «на всю строку».
    ///
    /// Пузырь обязан обжимать содержимое, как текстовый: у трёхсекундной записи
    /// волна занимала середину, а слева и справа оставалась пустая заливка на
    /// всю ширину карточки. Само по себе это не лечится — волна живёт внутри
    /// `GeometryReader`, а он всегда забирает ВСЁ предложенное место и своей
    /// естественной ширины не имеет. Поэтому ширину задаём снаружи.
    ///
    /// Считаем по числу сэмплов той же формулой, что `RecordWaveformPlaying
    /// .maxLength`, и добавляем колонки кнопки play и статуса. Потолок — ширина
    /// карточки: длинная запись упирается в неё и дальше волна прореживается
    /// сама (`adjustedSamples`). Минимум держит форму капсулы у совсем коротких.
    private func voiceWaveformMaxWidth(_ recording: Recording) -> CGFloat {
        // Естественная длина волны — та же формула, что у `RecordWaveformPlaying
        // .maxLength`. Берём её, а не подобранное число: поменяются `spacing`
        // или `width` полоски — ширина поедет за ними сама.
        let natural = max(
            0,
            (RecordWaveform.spacing + RecordWaveform.width)
                * CGFloat(recording.waveformSamples.count) - RecordWaveform.spacing
        )
        // Потолок — сколько остаётся от карточки после кнопки play и паддингов:
        // длинная запись упирается в него, дальше волна прореживается сама.
        let ceiling = MessageView.photoReplyBubbleMaxWidth - MessageView.voiceBubbleChrome
        return min(ceiling, max(MessageView.voiceWaveformMinWidth, natural))
    }

    /// Голосовая искра: тот же пузырь, что и у текстовой, но с плеером внутри.
    ///
    /// Оформление повторяет `quoteReplyBubble` по частям, а не переиспользует его
    /// целиком: там всё построено вокруг `Text` — резерв под статус СПРАВА в той
    /// же строке, вертикальные паддинги под кегль. У плеера своя геометрия
    /// (фиксированная высота, волна тянется по ширине), поэтому статус уезжает
    /// под запись, а не в строку.
    ///
    /// Заливка, радиус и бейдж — те же константы: пузырь обязан читаться как
    /// искра, независимо от того, текст в нём или запись.
    private func quoteReplyVoiceBubble(_ recording: Recording, _ message: Message) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Предел ставится ВОЛНЕ, а не пузырю: у волны внутри `GeometryReader`,
            // и только там её можно удержать. Ограничение снаружи ужимало
            // `HStack` целиком — кнопка play уезжала за край, волну обрезало.
            recordingView(recording, maxWaveformWidth: voiceWaveformMaxWidth(recording))

            if let status = quoteReplyStatus(message) {
                MessageStatusView(
                    status: status,
                    // Как и у текстовой искры: на золотой заливке капсула-подложка
                    // не нужна, галочки читаются напрямую.
                    needsCapsule: false,
                    colorSet: MessageStatusColorSet(
                        sending: MessageView.quoteReplyOutgoingText.opacity(0.5),
                        sent: MessageView.quoteReplyOutgoingText.opacity(0.5),
                        received: MessageView.quoteReplyOutgoingText.opacity(0.5),
                        read: MessageView.quoteReplyOutgoingText.opacity(0.5)
                    ),
                    onRetry: {
                        if case let .error(draft) = status {
                            viewModel.sendMessage(draft)
                        }
                    }
                )
                .padding(.trailing, 12)
                .padding(.bottom, 8)
            }
        }
        .padding(.bottom, quoteReplyStatus(message) == nil ? 8 : 0)
        // Никаких внешних `frame`: пузырь обжимает содержимое сам, ширину ему
        // диктует ограниченная волна внутри.
        .background(MessageView.quoteReplyBubbleFill)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .topLeading) {
            SparkReplyBadge()
                .offset(x: -SparkReplyBadge.overhang, y: -SparkReplyBadge.riseAboveBubble)
        }
    }

    private func quoteReplyBubble(_ message: Message) -> some View {
        Text(message.text)
            // На макете реплика набрана Manrope 700 против 600 у обычных
            // сообщений — то есть на СТУПЕНЬ жирнее соседей, а не «жирная сама
            // по себе». Приложение целиком на системном шрифте (из кастомных
            // зарегистрирован только `LiberationSerif-Italic` под курсив ответа),
            // где обычное сообщение — regular, поэтому ту же ступень даёт
            // semibold. Кегль и Dynamic Type берём у темы, а не из макета:
            // 15.5px мокапа — это те же 15pt чата.
            .font(Font(UIFont.systemFont(ofSize: font.pointSize, weight: .semibold)))
            // Цвет не зависит от стороны — заливка пузыря одна и та же
            // (см. `quoteReplyBubbleFill`), а на оранжевом читается только
            // тёмно-коричневый из макета.
            .foregroundColor(MessageView.quoteReplyOutgoingText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 14)
            // Место под статус резервируется СПРАВА, а не снизу: тогда у
            // однострочной реплики он встаёт в ту же строку (пилюля остаётся
            // капсулой), а у многострочной — в правый нижний угол, к концу
            // последней строки. Нижний резерв делал из «Ага» узкий высокий
            // прямоугольник с галочками под словом.
            .padding(.trailing, quoteReplyStatus(message) == nil ? 14 : 14 + MessageView.quoteReplyStatusColumn)
            .padding(.vertical, 10)
            .overlay(alignment: .bottomTrailing) {
                if let status = quoteReplyStatus(message) {
                    // Статус рисуем напрямую, а не через `messageTimeView()`: на
                    // оранжевой заливке нужен тёмный набор цветов из макета,
                    // а не `myMessageTime` темы.
                    MessageStatusView(
                        status: status,
                        needsCapsule: false,
                        colorSet: MessageStatusColorSet(
                            sending: MessageView.quoteReplyOutgoingText.opacity(0.5),
                            sent: MessageView.quoteReplyOutgoingText.opacity(0.5),
                            received: MessageView.quoteReplyOutgoingText.opacity(0.5),
                            read: MessageView.quoteReplyOutgoingText.opacity(0.5)
                        ),
                        onRetry: {
                            if case let .error(draft) = status {
                                viewModel.sendMessage(draft)
                            }
                        }
                    )
                    .padding(.trailing, 12)
                    // 11, а не «по нижнему краю»: у однострочной реплики
                    // галочки так стоят по центру строки, у многострочной —
                    // на уровне последней.
                    .padding(.bottom, 11)
                }
            }
        .background(MessageView.quoteReplyBubbleFill)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        // Бейдж — ПОСЛЕ `clipShape`: он по макету выступает за угол пузыря,
        // внутри клипа его срезало бы вместе с ним.
        .overlay(alignment: .topLeading) {
            // −14 = ширина бейджа/2: его правый край встаёт ровно на левый край
            // текста (у пузыря `.padding(.leading, 14)`), поэтому он не наезжает
            // на первые буквы короткой реплики.
            SparkReplyBadge()
                .offset(x: -SparkReplyBadge.overhang, y: -SparkReplyBadge.riseAboveBubble)
        }
    }

    /// Оранжевый градиент пузыря ответа на цитату — из макета, ОДИН на обе
    /// стороны переписки.
    ///
    /// Не заливка темы у входящего: пузырь здесь не обычное сообщение, а метка
    /// «ответ-спарк на эту цитату» — та же роль и та же карточка под ним в обе
    /// стороны, поэтому и цвет один. Со светлой темой это тоже честнее: там
    /// `friendMessage` почти сливался с фоном экрана.
    private static let quoteReplyBubbleFill = LinearGradient(
        colors: [MessageView.quoteReplyOutgoingTop, MessageView.quoteReplyOutgoingBottom],
        startPoint: .top,
        endPoint: .bottom
    )

    @ViewBuilder
    func replyBubbleView(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(message.user.name)
                .fontWeight(.semibold)
                .padding(.horizontal, MessageView.horizontalTextPadding)

            if !message.attachments.isEmpty {
                attachmentsView(message)
                    .padding(.top, 4)
                    .padding(.bottom, message.text.isEmpty ? 0 : 4)
            }

            if !message.text.isEmpty {
                MessageTextView(
                    text: message.text,
                    messageUseMarkdown: messageUseMarkdown,
                    inbound: !message.user.isCurrentUser,
                    anyLinkColor: theme.colors.textMyReply,
                    darkLinkColor: theme.colors.darkLink,
                    isDeleted: message.isDeleted,
                    isStreaming: message.isStreaming,
                    onMentionTap: { id in
                        if let user = groupUsers.first(where: {
                            $0.id.components(separatedBy: "@").first == id
                        }) {
                            tapAvatarClosure?(user, message.id)
                        }
                    }
                )
                .padding(.horizontal, MessageView.horizontalTextPadding)
            }

            if let recording = message.recording {
                recordingView(recording)
            }
        }
        .font(.caption2)
        .padding(.vertical, 8)
        .frame(width: message.attachments.isEmpty ? nil : MessageView.widthWithMedia + additionalMediaInset)
        .bubbleBackground(message, theme: theme, isReply: true)
    }

    @ViewBuilder
    var avatarView: some View {
        if isGroup {
            Group {
                if showAvatar {
                    AvatarView(url: message.user.avatarURL, cachedImage: message.user.avatarCachedImage, avatarSize: avatarSize)
                        .contentShape(Circle())
                        .highPriorityGesture(
                            TapGesture().onEnded {
                                tapAvatarClosure?(message.user, message.id)
                            }
                        )
                } else {
                    Color.clear.viewSize(avatarSize)
                }
            }
            .padding(.horizontal, MessageView.horizontalAvatarPadding)
            .sizeGetter($avatarViewSize)
        } else {
            Spacer()
                .frame(width: MessageView.horizontalTextPadding)
        }
    }

    @ViewBuilder
    func attachmentsView(_ message: Message) -> some View {
        AttachmentsGrid(attachments: message.attachments) {
            viewModel.presentAttachmentFullScreen($0)
        }
        .applyIf(message.attachments.count > 1) {
            $0
                .padding(.top, MessageView.horizontalAttachmentPadding)
                .padding(.horizontal, MessageView.horizontalAttachmentPadding)
        }
        .overlay(alignment: .bottomTrailing) {
            if message.text.isEmpty {
                messageTimeView(needsCapsule: true)
                    .padding(4)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    func textWithTimeView(_ message: Message) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            MessageTextView(
                text: message.text,
                messageUseMarkdown: messageUseMarkdown,
                inbound: !message.user.isCurrentUser,
                anyLinkColor: theme.colors.anyLink,
                darkLinkColor: theme.colors.darkLink,
                isDeleted: message.isDeleted,
                isStreaming: message.isStreaming,
                onMentionTap: { id in
                    if let user = groupUsers.first(where: { $0.id.components(separatedBy: "@").first == id }) {
                        tapAvatarClosure?(user, message.id)
                    }
                }
            )
            .fixedSize(horizontal: false, vertical: true)

            messageTimeView()
                .baselineNudgeDown(6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    func recordingView(_ recording: Recording, maxWaveformWidth: CGFloat? = nil) -> some View {
        // Через `VoiceMessagePlayerView`, а не напрямую: у голосового сообщения
        // источник резолвит приложение (`Message.voicePlayback`). Без разрешения
        // вью прозрачна — играет тот же `RecordWaveformWithButtons`, что и раньше.
        VoiceMessagePlayerView(
            recording: recording,
            playback: message.voicePlayback,
            maxWaveformWidth: maxWaveformWidth,
            colorButton: message.user.isCurrentUser ? theme.colors.myMessage : .white,
            colorButtonBg: message.user.isCurrentUser ? .white : theme.colors.myMessage,
            colorWaveform: message.user.isCurrentUser ? theme.colors.textDarkContext : theme.colors.textLightContext
        )
        .padding(.horizontal, MessageView.horizontalTextPadding)
        .padding(.top, 8)
    }
    
    @ViewBuilder
    func documentView(_ message: Message) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc")
                .resizable()
                .foregroundStyle(message.user.isCurrentUser ? .white : theme.colors.buttonBackground)
                .scaledToFit()
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text.components(separatedBy: "-").first ?? "")
                    .font(.body)
                    .lineLimit(1)
                Text(message.text.components(separatedBy: "-").last ?? "")
                    .font(.footnote)
                
            }
        }
        .padding(.horizontal, MessageView.horizontalTextPadding)
        .padding(.top, 8)
    }
}

public extension View {

    @ViewBuilder
    func bubbleBackground(_ message: Message, theme: ChatTheme, isReply: Bool = false) -> some View {
        let radius: CGFloat = !message.attachments.isEmpty ? 12 : 20
        let additionalMediaInset: CGFloat = message.attachments.count > 1 ? 2 : 0
        self
            .frame(width: message.attachments.isEmpty ? nil : MessageView.widthWithMedia + additionalMediaInset)
            .foregroundColor(message.user.isCurrentUser ? (isReply ? theme.colors.textMyReply : theme.colors.textDarkContext) : theme.colors.textLightContext)
            .background {
                // Дефект 3 (P10): исходное условие не учитывало ни attachments,
                // ни publicationAttachment, ни .geo/.document — для них фон и
                // раньше не рисовался (собственная подложка/полноразмерная
                // медиа). Добавлен ровно один новый случай: контента нет
                // ВООБЩЕ (та самая потеря вложения) — тогда фон обязан
                // появиться, иначе графический плейсхолдер из
                // `missingContentPlaceholderView()` окажется на прозрачном
                // 44×44 пятне без пузыря.
                if isReply || !message.text.isEmpty || message.recording != nil
                    || !MessageView.hasRenderableContent(message) {
                    if message.user.isCurrentUser && !isReply {
                        if let myMessageGradient = theme.colors.myMessageGradient {
                            // Тема-драйвен градиент исходящего пузыря (дизайн-макет).
                            // Задан из аппа → чистый градиент вместо сплошного
                            // myMessage + двух захардкоженных overlay-градиентов.
                            RoundedRectangle(cornerRadius: radius)
                                .fill(myMessageGradient)
                        } else {
                        ZStack {
                            // Base color
                            RoundedRectangle(cornerRadius: radius)
                                .foregroundColor(theme.colors.myMessage)
                            // Gradient from left
                            RoundedRectangle(cornerRadius: radius)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.44, green: 0.31, blue: 0.98),
                                            Color(red: 0.44, green: 0.31, blue: 0.98).opacity(0)
                                        ]),
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                            
                            // Gradient from right
                            RoundedRectangle(cornerRadius: radius)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.39, green: 0.36, blue: 1),
                                            Color(red: 0.44, green: 0.31, blue: 0.98).opacity(0)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                        }
                    } else {
                        RoundedRectangle(cornerRadius: radius)
                            .foregroundColor(message.user.isCurrentUser ? theme.colors.myMessage : theme.colors.friendMessage)
                            .opacity(isReply ? 0.5 : 1)
                    }
                }
            }
            .cornerRadius(radius)
    }
}

// MARK: - Location View

extension MessageView {
    
    @ViewBuilder
    func locationView(_ message: Message) -> some View {
        let coordinates = parseCoordinates(from: message.text)
        let size = CGSize(width: min(UIScreen.main.bounds.width * 0.6, 260), height: 128)
        
        if let lat = coordinates?.latitude, let lon = coordinates?.longitude {
            ZStack {
                MessageMapView(latitude: lat, longitude: lon, snapshotSize: size)
                    .frame(width: size.width, height: size.height)
                    .cornerRadius(20)
                    .overlay(alignment: .bottomTrailing) {
                        messageTimeView(needsCapsule: true)
                            .padding(.bottom, 6)
                            .padding(.trailing, 6)
                    }
                
                    .highPriorityGesture(
                        TapGesture().onEnded {
                            openMaps(latitude: lat, longitude: lon)
                        }
                    )
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    func parseCoordinates(from text: String) -> (latitude: Double, longitude: Double)? {
        let cleanText = text.replacingOccurrences(of: "geo:", with: "")
        let components = cleanText.split(separator: ";").first?.split(separator: ",").compactMap { Double($0) }
        
        if let lat = components?.first, let lon = components?.last {
            return (latitude: lat, longitude: lon)
        }
        return nil
    }
    
    func openMaps(latitude: Double, longitude: Double) {
        let url = URL(string: "http://maps.apple.com/?q=\(latitude),\(longitude)")!
        UIApplication.shared.open(url)
    }
}

extension MessageView {
    @ViewBuilder
    func messageTimeView(needsCapsule: Bool = false) -> some View {
        if showMessageTimeView {
            let spacing: CGFloat = {
                guard let status = message.status else { return -4 }
                if case .error = status { return 4 }
                return -4
            }()

            if message.isDeleted {
                timeOnly(needsCapsule: needsCapsule)
                    .sizeGetter($timeSize)
            } else {
                timeWithOptionalStatus(needsCapsule: needsCapsule, spacing: spacing)
                    .sizeGetter($timeSize)
            }
        }
    }
    
    @ViewBuilder
    private func timeOnly(needsCapsule: Bool) -> some View {
        if needsCapsule {
            CapsuleTimeContainer(
                isCurrentUser: message.user.isCurrentUser,
                theme: theme
            ) {
                MessageTimeText(
                    text: message.time,
                    isCurrentUser: message.user.isCurrentUser,
                    theme: theme, needsCapsule: needsCapsule
                )
            }
        } else {
            MessageTimeText(
                text: message.time,
                isCurrentUser: message.user.isCurrentUser,
                theme: theme, needsCapsule: needsCapsule
            )
        }
    }

    @ViewBuilder
    private func timeWithOptionalStatus(needsCapsule: Bool, spacing: CGFloat) -> some View {
        let content = HStack(spacing: spacing) {
            if message.user.isCurrentUser, let status = message.status {
                MessageStatusView(
                    status: status,
                    needsCapsule: needsCapsule,
                    colorSet: MessageStatusColorSet(
                        sending: theme.colors.myMessageTime,
                        sent: theme.colors.myMessageTime,
                        received: theme.colors.myMessageTime,
                        read: theme.colors.myMessageTime
                    ),
                    onRetry: {
                        if case let .error(draft) = status {
                            viewModel.sendMessage(draft)
                        }
                    }
                )
                .alignmentGuide(.lastTextBaseline) { d in d[.bottom] }
                .sizeGetter($statusSize)
            }

            // MessageTimeText(
            //     text: message.time,
            //     isCurrentUser: message.user.isCurrentUser,
            //     theme: theme, needsCapsule: needsCapsule
            // )
            // .alignmentGuide(.lastTextBaseline) { d in d[.lastTextBaseline] }
        }

        if needsCapsule {
            CapsuleTimeContainer(
                isCurrentUser: message.user.isCurrentUser,
                theme: theme
            ) { content }
        } else {
            content
        }
    }
}

//#if DEBUG
//struct MessageView_Preview: PreviewProvider {
//    static let stan = User(id: "stan", name: "Stan", avatarURL: nil, avatarCachedImage: nil, isCurrentUser: false)
//    static let john = User(id: "john", name: "John", avatarURL: nil, avatarCachedImage: nil, isCurrentUser: true)
//
//    static private var shortMessage = "Hi, buddy!"
//    static private var longMessage = "Hello hello hello hello hello hello hello hello hello hello hello hello hello\n hello hello hello hello d d d d d d d d"
//
//    static private var replyedMessage = Message(
//        id: UUID().uuidString,
//        user: stan,
//        status: .read,
//        text: longMessage,
//        attachments: [
//            Attachment.randomImage(),
//            Attachment.randomImage(),
//            Attachment.randomImage(),
//            Attachment.randomImage(),
//            Attachment.randomImage(),
//        ]
//    )
//
//    static private var message = Message(
//        id: UUID().uuidString,
//        user: stan,
//        status: .read,
//        text: shortMessage,
//        replyMessage: replyedMessage.toReplyMessage()
//    )
//
//    static var previews: some View {
//        ZStack {
//            Color.yellow.ignoresSafeArea()
//
//            MessageView(
//                viewModel: ChatViewModel(),
//                message: replyedMessage,
//                positionInUserGroup: .single,
//                chatType: .conversation,
//                avatarSize: 32,
//                tapAvatarClosure: nil,
//                messageUseMarkdown: false,
//                isDisplayingMessageMenu: false,
//                showMessageTimeView: true,
//                isGroup: false,
//                tapDocumentClosure: nil,
//                font: UIFontMetrics.default.scaledFont(for: UIFont.systemFont(ofSize: 15))
//            )
//        }
//    }
//}
//#endif

private struct BaselineNudgeDown: ViewModifier {
    let points: CGFloat
    func body(content: Content) -> some View {
        content.alignmentGuide(.lastTextBaseline) { d in
            d[.lastTextBaseline] - points
        }
    }
}

private extension View {
    func baselineNudgeDown(_ points: CGFloat) -> some View {
        modifier(BaselineNudgeDown(points: points))
    }
}

