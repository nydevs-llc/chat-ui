//
//  MessagePublicationAttachment.swift
//  Chat
//
//  Вложение «ответ на публикацию» — единственный тип вложения-цитаты в переписке.
//
//  Публикация покрывает три случая сразу, потому что на бэкенде это одна сущность:
//  ответ на секрет и ответ на вопрос дня материализуются той же строкой публикации,
//  что и свободный пост, — у первых двух просто заполнен вопрос. Поэтому здесь нет
//  отдельного типа «секрет»: он был бы вторым именем для той же строки.
//
//  Отсюда и правило рендера (`showsQuoteCard`): вопрос ИЛИ голос → большая
//  карточка-цитата над пузырём; ни того, ни другого (свободный пост) → компактная
//  полоска, как было.
//

import Foundation

public struct MessagePublicationAttachment {

    /// Вид процитированного объекта.
    ///
    /// `nil` — публикация (включая секрет и ответ на вопрос дня): прежнее поведение,
    /// развилка отрисовки идёт по `question`/`voice`. Остальные значения — элементы
    /// чужой анкеты, у которых своего id нет: сервер адресует их парой
    /// «получатель искры + вид».
    public enum Kind: String {
        /// Фото анкеты: рисуется САМО ПО СЕБЕ — ни заголовка, ни подписи
        /// (решение владельца вопреки макету: в чат едет элемент, а не обвязка).
        case photo
        case notForMe = "not_for_me"
        case dateIdeas = "date_ideas"
        /// Кино/музыка одним видом: в анкете это единый слайд, где трек и фильм
        /// опциональны по отдельности. Обложка (постер/арт) приезжает в `photoURL`.
        case media
    }

    /// Вид элемента анкеты. `nil` у публикаций.
    public let kind: Kind?

    public let id: Int

    /// Вопрос, на который отвечает публикация: текст секрета или вопрос дня.
    ///
    /// `nil` (или пустая строка) — свободный пост, у которого вопроса нет вовсе.
    /// Именно поэтому поле опциональное: карточка обязана уметь рисоваться без
    /// заголовка, а не считать его обязательным.
    public let question: String?

    /// Ответ — `content` публикации. Остаётся заполненным и при голосовом ответе:
    /// служит фолбеком и источником превью для списка чатов и пуша.
    public let text: String

    public let photoURL: URL?
    public let blurHash: String?

    /// Голосовой ответ. Когда задан — вытесняет текст в карточке (см. `showsVoice`).
    public let voice: Voice?

    /// Слово-префикс accessibility-лейбла («Секрет» / «Вопрос дня» / «Публикация»).
    ///
    /// Используется в ОБОИХ представлениях — и в карточке-цитате, и в компактной
    /// полоске свободного поста, — поэтому обязателен независимо от того, какая
    /// ветка рендера сработает: без него полоска читалась бы голым текстом
    /// публикации, неотличимым от текста самого сообщения.
    ///
    /// Форк не знает про каталог строк приложения и не носит своего, поэтому
    /// локализованные подписи приходят снаружи тем же каналом, что и `onPlay`.
    ///
    /// - Important: у этого параметра и у `voiceAnswerAccessibilityLabel`
    ///   СОЗНАТЕЛЬНО нет значений по умолчанию. С дефолтом забыть их можно молча,
    ///   и на русском интерфейсе VoiceOver прочитал бы английское «Secret». Без
    ///   дефолта это ошибка компиляции у потребителя — единственный способ не
    ///   пропустить строку при бампе версии.
    public let accessibilityTitle: String

    /// Хвост accessibility-лейбла для голосового ответа («Голосовой ответ»):
    /// саму запись VoiceOver прочитать не может, читаем её описание.
    /// Без значения по умолчанию — см. `accessibilityTitle`.
    public let voiceAnswerAccessibilityLabel: String

    /// Резолв короткоживящего URL живёт в приложении — форк не знает про файловый сервис.
    public var onPlay: ((String) -> Void)?

    /// Голос ФАКТИЧЕСКИ заиграл — на вход `fileId`, как и у `onPlay`.
    ///
    /// Нужен потому, что ближайшая доступная приложению точка — «резолв ссылки
    /// завершился» — врёт: на плохой сети ссылка приезжает, а звука может не быть.
    /// Момент старта знает только плеер внутри форка, он и зовёт это замыкание.
    ///
    /// Зовётся на каждый переход плеера в `playing`, то есть и на возобновление
    /// после паузы. Дедупликация — на стороне приложения (защёлка по `fileId`),
    /// потому что ячейки ленты сообщений переиспользуются и хранить защёлку
    /// внутри карточки бессмысленно.
    public var onPlaybackStarted: ((String) -> Void)?

    public struct Voice: Equatable, Hashable {
        public let fileId: String
        public let durationMs: Int
        public let waveform: [Double]
        /// ТРАНЗИЕНТНОЕ поле: ссылка, резолвнутая в рантайме.
        ///
        /// Почему оно есть здесь и почему его НЕТ в снапшоте вложения на бэкенде
        /// и в кеше: ссылка короткоживущая, вмороженная в снапшот протухнет и
        /// сломает воспроизведение на следующем открытии чата. Персистится только
        /// `fileId`; URL живёт ровно столько, сколько живёт эта вью-модель.
        ///
        /// `nil` → карточка показывает «тап для воспроизведения» и зовёт `onPlay(fileId)`.
        /// Приложение резолвит ссылку и переотдаёт сообщение с заполненным `url` →
        /// карточка играет штатным плеером с прогрессом волны.
        ///
        /// НЕ переносить в persistence и НЕ убирать отсюда — это разные слои.
        public let url: URL?

        public init(fileId: String, durationMs: Int, waveform: [Double], url: URL? = nil) {
            self.fileId = fileId
            self.durationMs = durationMs
            self.waveform = waveform
            self.url = url
        }

        /// Копия с резолвнутой ссылкой — то, что приложение кладёт в сообщение
        /// после ответа файлового сервиса.
        public func withResolvedURL(_ url: URL?) -> Voice {
            Voice(fileId: fileId, durationMs: durationMs, waveform: waveform, url: url)
        }
    }

    public init(
        kind: Kind? = nil,
        id: Int,
        question: String? = nil,
        text: String,
        photoURL: URL? = nil,
        blurHash: String? = nil,
        voice: Voice? = nil,
        accessibilityTitle: String,
        voiceAnswerAccessibilityLabel: String,
        onPlay: ((String) -> Void)? = nil,
        onPlaybackStarted: ((String) -> Void)? = nil
    ) {
        self.kind = kind
        self.id = id
        self.question = question
        self.text = text
        self.photoURL = photoURL
        self.blurHash = blurHash
        self.voice = voice
        self.accessibilityTitle = accessibilityTitle
        self.voiceAnswerAccessibilityLabel = voiceAnswerAccessibilityLabel
        self.onPlay = onPlay
        self.onPlaybackStarted = onPlaybackStarted
    }

    /// Правило рендера: карточка-цитата или компактная полоска.
    ///
    /// Карточку получает публикация, у которой есть вопрос ИЛИ голос, — то есть
    /// ответ на секрет, ответ на вопрос дня и аудио-публикация (последняя в чате
    /// раньше не отображалась вовсе). Свободный пост остаётся на компактной
    /// полоске: цитировать заголовком у него нечего, а раздувать самый частый
    /// случай в карточку на треть экрана — регрессия.
    ///
    /// Пустая строка вопроса считается отсутствием вопроса: бэкенд, отдавший `""`
    /// вместо `null`, не должен молча менять способ отрисовки.
    public var showsQuoteCard: Bool {
        // Фото анкеты идёт большой карточкой всегда: у него нет ни вопроса, ни
        // голоса, и по прежнему правилу оно молча уехало бы в компактную полоску,
        // где картинку показать негде.
        if kind == .photo { return true }
        // Кино/музыка — тоже всегда карточкой: у вида есть обложка, которую в
        // компактной полоске показать негде. Полагаться на непустой `question`
        // (туда мост кладёт название трека/фильма) нельзя — пустое название
        // молча схлопнуло бы карточку в полоску.
        if kind == .media { return true }
        return voice != nil || !(question ?? "").isEmpty
    }

    /// Правило контента внутри карточки: голос вытесняет текст. Текст остаётся
    /// в модели как фолбек и как источник превью для списка чатов/пуша.
    public var showsVoice: Bool { voice != nil }

    /// Копия с резолвнутой ссылкой на голос — приложение зовёт её из `onPlay`,
    /// получив короткоживущий URL, и переотдаёт сообщение в ленту.
    public func withResolvedVoiceURL(_ url: URL?) -> MessagePublicationAttachment {
        MessagePublicationAttachment(
            id: id,
            question: question,
            text: text,
            photoURL: photoURL,
            blurHash: blurHash,
            voice: voice?.withResolvedURL(url),
            accessibilityTitle: accessibilityTitle,
            voiceAnswerAccessibilityLabel: voiceAnswerAccessibilityLabel,
            onPlay: onPlay,
            onPlaybackStarted: onPlaybackStarted
        )
    }
}

// `onPlay` и `onPlaybackStarted` исключены из `==`/`hash`: замыкания несравнимы,
// а без исключения диффабл ленты сообщений сочтёт каждое сообщение изменившимся
// на каждом рендере. Accessibility-подписи, наоборот, сравниваются — это обычные
// строки, и смена языка обязана дойти до ячейки.
extension MessagePublicationAttachment: Equatable, Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.question == rhs.question
            && lhs.text == rhs.text
            && lhs.photoURL == rhs.photoURL
            && lhs.blurHash == rhs.blurHash
            && lhs.voice == rhs.voice
            && lhs.accessibilityTitle == rhs.accessibilityTitle
            && lhs.voiceAnswerAccessibilityLabel == rhs.voiceAnswerAccessibilityLabel
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(question)
        hasher.combine(text)
        hasher.combine(photoURL)
        hasher.combine(blurHash)
        hasher.combine(voice)
        hasher.combine(accessibilityTitle)
        hasher.combine(voiceAnswerAccessibilityLabel)
    }
}
