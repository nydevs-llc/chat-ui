//
//  MessagePublicationQuoteCardView.swift
//  Chat
//
//  Карточка-цитата публикации: вопрос (секрет / вопрос дня) + ответ владельца
//  анкеты, текстом или голосом. Показывается только тем публикациям, у которых
//  есть вопрос ИЛИ голос (`MessagePublicationAttachment.showsQuoteCard`);
//  свободный пост остаётся на компактной `MessagePublicationCardView`.
//
//  Вопрос ОПЦИОНАЛЕН: аудио-публикация без вопроса рисуется без заголовка —
//  только разделитель и плеер.
//
//  Карточка одинакова для входящего и исходящего — это цитата ЧУЖОЙ публикации
//  в обе стороны; зеркалится только пузырь ответа поверх неё (см. MessageView).
//
//  Эталон оформления — карточка того же секрета в компоузере приложения
//  (`SparkSecretReplyCardView` + `SecretQuoteCardStyle`). Один и тот же секрет
//  обязан выглядеть одинаково в компоузере и в переписке, поэтому палитра,
//  геометрия, кегли и правило «уменьшаем кегль, НЕ обрезаем» перенесены оттуда
//  один в один. Расходится сознательно только высота: в компоузере карточка
//  тянется к пропорции макета 236×408, в ленте сообщений столько занимать нельзя,
//  поэтому здесь она обнимает контент.
//

import SwiftUI
import UIKit

struct MessagePublicationQuoteCardView: View {

    let attachment: MessagePublicationAttachment
    /// Не влияет на оформление карточки (она одинакова в обе стороны) — оставлен
    /// в сигнатуре как контекст композиции и точка расширения.
    let isOutgoing: Bool
    /// Пустота, добираемая снизу под подвёрнутый пузырь ответа.
    ///
    /// Карточка в переписке обнимает контент, а пузырь ложится ПОВЕРХ её нижнего
    /// края — без резерва он накрывал бы последнюю строку ответа (на макете он
    /// ложится на пустое место карточки в 408pt, здесь такой пустоты нет).
    /// Считает композиция (`MessageView`): только она знает высоту пузыря.
    var bottomReserve: CGFloat = 0

    // MARK: - Layout (значения компоузера)

    private enum Layout {
        static let width: CGFloat = 236
        static let corner: CGFloat = 28
        static let paddingHorizontal: CGFloat = 22
        static let paddingVertical: CGFloat = 30
        static let accentLineWidth: CGFloat = 4
        /// Отступ вопроса от левой черты.
        static let questionSpacing: CGFloat = 10
        static let dividerWidth: CGFloat = 88
        static let dividerHeight: CGFloat = 4
        static let dividerTop: CGFloat = 18
        static let answerTop: CGFloat = 20
        static let quoteFontSize: CGFloat = 110
        static let quoteOpacity: Double = 0.10
    }

    /// Нижний паддинг карточки — сколько пустоты у неё есть под последней строкой
    /// ответа. Ровно на столько пузырь ответа может лечь на карточку бесплатно,
    /// не требуя резерва (см. `bottomReserve`).
    static let contentBottomPadding: CGFloat = Layout.paddingVertical

    /// Ширина контента карточки: 236 − 2×22 = 192pt.
    ///
    /// Не косметика: на неё рассчитаны пороги адаптивного кегля ниже, и по ней же
    /// прореживается волна голосового ответа (`PublicationVoicePill`), иначе она
    /// требует ширины по числу сэмплов и вылезает за границу карточки.
    static let contentWidth: CGFloat = Layout.width - 2 * Layout.paddingHorizontal

    // MARK: - Colors
    //
    // ⚠️ ЗЕРКАЛО, А НЕ ИСТОЧНИК ПРАВДЫ. Эти литералы (и геометрия в `Layout` выше)
    // дублируют общий стиль приложения:
    //
    //   ours-ios → Modules/Foundation/UI/Sources/DesignSystem/SwiftUI/SecretQuoteCardStyle.swift
    //   (потребители там: FeedQuoteCard — слайд ленты, SparkSecretReplyCardView — компоузер)
    //
    // Разделить нельзя: форк — отдельный репозиторий и не зависит от Foundation/UI.
    // Поэтому правка палитры или геометрии карточки секрета обязана идти в ОБА
    // репозитория одним заходом, иначе один и тот же секрет молча разъедется
    // между лентой/компоузером и перепиской. Ровно это уже случалось — расхождение
    // нашлось только финальным ревью, когда сверили карточки между собой, а не
    // каждую с макетом по отдельности.

    /// #6A4CE0
    private static let gradientTop = Color(red: 106 / 255, green: 76 / 255, blue: 224 / 255)
    /// #4B33B6
    private static let gradientMid = Color(red: 75 / 255, green: 51 / 255, blue: 182 / 255)
    /// #2E2185
    private static let gradientBottom = Color(red: 46 / 255, green: 33 / 255, blue: 133 / 255)
    /// #C9BCF2
    private static let questionColor = Color(red: 201 / 255, green: 188 / 255, blue: 242 / 255)
    /// #B79BFF
    private static let accentLineColor = Color(red: 183 / 255, green: 155 / 255, blue: 255 / 255)
    /// #8B6BFF
    private static let dividerColor = Color(red: 139 / 255, green: 107 / 255, blue: 255 / 255)
    private static let strokeColor = Color.white.opacity(0.14)
    /// #4A2DB4 × 0.4
    private static let shadowColor = Color(red: 74 / 255, green: 45 / 255, blue: 180 / 255).opacity(0.4)

    // MARK: - Body

    /// Порядок модификаторов повторяет компоузер и значим:
    /// градиент и блик — фоном/оверлеем ДО `clipShape`, кавычки — оверлеем ПОСЛЕ,
    /// иначе глиф режется скруглённым углом карточки.
    var body: some View {
        content
            .padding(.horizontal, Layout.paddingHorizontal)
            .padding(.vertical, Layout.paddingVertical)
            .padding(.bottom, bottomReserve)
            .frame(width: Layout.width, alignment: .leading)
            .background(cardGradient)
            .overlay(highlight.allowsHitTesting(false))
            .clipShape(RoundedRectangle(cornerRadius: Layout.corner, style: .continuous))
            .overlay(quoteGlyph.padding(.leading, 10).padding(.top, -6), alignment: .topLeading)
            .overlay(
                quoteGlyph.rotationEffect(.degrees(180)).padding(.trailing, 10).padding(.bottom, -6),
                alignment: .bottomTrailing
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.corner, style: .continuous)
                    .stroke(Self.strokeColor, lineWidth: 1)
            )
            .shadow(color: Self.shadowColor, radius: 20, y: 12)
            .accessibilityElement(children: accessibilityChildBehavior)
            .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let question = question {
                questionBlock(question)
            }

            // Разделитель рисуется всегда, в том числе без заголовка: он держит
            // верхний край блока ответа. Отступ сверху нужен только когда над ним
            // действительно есть вопрос — иначе карточка начиналась бы с пустоты.
            RoundedRectangle(cornerRadius: Layout.dividerHeight / 2, style: .continuous)
                .fill(Self.dividerColor)
                .frame(width: Layout.dividerWidth, height: Layout.dividerHeight)
                .padding(.top, question == nil ? 0 : Layout.dividerTop)

            // Правило контента: голос вытесняет курсивную цитату.
            if let voice = attachment.voice {
                PublicationVoicePill(
                    voice: voice,
                    onPlay: attachment.onPlay,
                    onPlaybackStarted: attachment.onPlaybackStarted
                )
                .padding(.top, Layout.answerTop)
            } else if !attachment.text.isEmpty {
                Text(attachment.text)
                    .font(Self.answerFont(size: Self.answerFontSize(for: attachment.text)))
                    .foregroundColor(.white)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Layout.answerTop)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Вопрос, если он есть и непустой. Пустая строка приравнена к отсутствию —
    /// то же правило, что в `MessagePublicationAttachment.showsQuoteCard`, иначе
    /// карточка нарисовала бы черту и отступ вокруг пустоты.
    private var question: String? {
        guard let question = attachment.question, !question.isEmpty else { return nil }
        return question
    }

    private func questionBlock(_ question: String) -> some View {
        HStack(alignment: .top, spacing: Layout.questionSpacing) {
            RoundedRectangle(cornerRadius: Layout.accentLineWidth / 2, style: .continuous)
                .fill(Self.accentLineColor)
                .frame(width: Layout.accentLineWidth)

            Text(question)
                .font(.system(size: Self.questionFontSize(for: question), weight: .bold))
                .foregroundColor(Self.questionColor)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Adaptive type

    // Длинный секрет НЕ обрезается, а уменьшает кегль — правило дизайн-спеки,
    // общее для ленты, компоузера и переписки: иначе один и тот же секрет
    // читался бы по-разному в трёх местах. Пороги взяты из компоузера дословно —
    // они рассчитаны ровно на эту контентную ширину (236 − 2×22 = 192pt),
    // а карточка здесь той же ширины и с теми же паддингами.

    private static func answerFontSize(for answer: String) -> CGFloat {
        switch answer.count {
        case ...50: return 20
        case ...90: return 18
        case ...140: return 16
        default: return 14
        }
    }

    private static func questionFontSize(for question: String) -> CGFloat {
        switch question.count {
        case ...40: return 15
        case ...70: return 14
        default: return 13
        }
    }

    // MARK: - Fonts

    /// PostScript-имя курсивного serif'а приложения.
    private static let serifItalicPostScriptName = "LiberationSerif-Italic"

    /// Курсивный serif ответа.
    ///
    /// `.custom(…).italic()` до iOS 16 НЕ работает: на кастомном шрифте модификатор
    /// молча игнорируется, и на iOS 15 ответ в переписке был бы прямым, тогда как в
    /// компоузере — курсивным. Поэтому берём готовое курсивное начертание по имени,
    /// а не пытаемся наклонить прямое.
    ///
    /// Шрифт носит и регистрирует ПРИЛОЖЕНИЕ — `AppFont.registerCustomFontsIfNeeded()`
    /// через `CTFontManagerRegisterFontsForURL` со скоупом `.process` (в Info.plist
    /// `UIAppFonts` нет). Скоуп `.process` делает шрифт видимым и отсюда, но
    /// регистрация ЛЕНИВАЯ — на первом обращении к `AppFont`. Поэтому имя резолвится
    /// на каждом рендере, а не один раз в статике: карточка, отрисованная раньше
    /// первого обращения приложения к `AppFont`, подхватит шрифт на следующем рендере.
    ///
    /// Не резолвится вовсе (форк собран отдельно, демо-приложение) — системный
    /// serif-курсив. Это тот же фолбек, что и внутри `AppFont`, так что расхождения
    /// с компоузером не будет ни в одном из случаев.
    ///
    /// `Font(uiFont)`, а не `.custom(_:size:)`, — тоже ради совпадения: `.custom`
    /// масштабируется Dynamic Type, `Font(uiFont)` нет, а компоузер использует второе.
    private static func answerFont(size: CGFloat) -> Font {
        if let uiFont = UIFont(name: serifItalicPostScriptName, size: size) {
            return Font(uiFont)
        }
        return .system(size: size, design: .serif).italic()
    }

    // MARK: - Background

    private var cardGradient: some View {
        // 158° из макета: направление (sin158°, cos158°) в экранных координатах.
        LinearGradient(
            stops: [
                .init(color: Self.gradientTop, location: 0),
                .init(color: Self.gradientMid, location: 0.46),
                .init(color: Self.gradientBottom, location: 1)
            ],
            startPoint: UnitPoint(x: 0.31, y: 0.04),
            endPoint: UnitPoint(x: 0.69, y: 0.96)
        )
    }

    /// Радиальный блик сверху — объём карточки на макете.
    private var highlight: some View {
        RadialGradient(
            colors: [Color.white.opacity(0.18), Color.white.opacity(0)],
            center: UnitPoint(x: 0.5, y: 0),
            startRadius: 0,
            endRadius: Layout.width * 0.9
        )
    }

    /// Декоративная кавычка Georgia. Закрывающая — та же глифа, повёрнутая на 180°.
    ///
    /// - Note: `allowsHitTesting(false)` убирает только касания — от VoiceOver это
    ///   не прячет, и скринридер читал бы по два символа кавычки на карточку.
    ///   Прячет именно `accessibilityHidden(true)`.
    private var quoteGlyph: some View {
        Text(verbatim: "\u{201C}")
            .font(.custom("Georgia", size: Layout.quoteFontSize))
            .foregroundColor(Color.white.opacity(Layout.quoteOpacity))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .fixedSize()
    }

    // MARK: - Accessibility

    /// Текстовый ответ читается ОДНИМ элементом (`.combine`) — интерактивных детей
    /// внутри нет, терять нечего.
    ///
    /// У голосового — `.contain`: `.combine` схлопнул бы кнопку play в общий элемент,
    /// и единственное интерактивное место карточки перестало бы быть отдельно
    /// достижимым. Здесь лейбл работает как имя группы, а плеер остаётся
    /// самостоятельным элементом.
    private var accessibilityChildBehavior: AccessibilityChildBehavior {
        attachment.voice == nil ? .combine : .contain
    }

    /// «Секрет. <вопрос>. <ответ | Голосовой ответ>» — тот же лейбл, что в компоузере.
    /// Пустые куски отфильтровываются, поэтому публикация без вопроса читается
    /// «Секрет. Голосовой ответ», без дыры в середине.
    private var accessibilityLabel: String {
        let tail = attachment.voice != nil
            ? attachment.voiceAnswerAccessibilityLabel
            : attachment.text
        return [attachment.accessibilityTitle, question ?? "", tail]
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }
}

// MARK: - Voice

/// Плеер не собственный: переиспользуем `RecordWaveformWithButtons`, которым уже
/// рисуются голосовые сообщения.
///
/// Два состояния, разделённые ровно наличием транзиентного `voice.url`:
/// - `url == nil` — ссылка ещё не резолвнута: тап уходит в приложение через
///   `onPlay(fileId)`, форк сам ничего не проигрывает (он не знает про файловый сервис).
/// - `url != nil` — приложение вернуло короткоживущую ссылку: играем штатным
///   путём, тем же, которым играют обычные голосовые, — с прогрессом волны.
struct PublicationVoicePill: View {

    let voice: MessagePublicationAttachment.Voice
    let onPlay: ((String) -> Void)?
    /// Плеер действительно заиграл. См. докблок в `MessagePublicationAttachment`.
    let onPlaybackStarted: ((String) -> Void)?

    /// Поднимается ТОЛЬКО явным тапом по play при отсутствующей ссылке. Живёт до
    /// прихода `url`, после чего плеер стартует сам и флаг сбрасывается. Ячейка,
    /// приехавшая на экран с уже готовым `url`, флаг не поднимает и молчит.
    @State private var pendingPlayAfterResolve = false
    @State private var resolveTimeoutTask: Task<Void, Never>?

    /// Сколько ждём ссылку, прежде чем молча погасить намерение.
    ///
    /// 15 с — потолок самого запроса в приложении (`timeoutIntervalForRequest`),
    /// плюс 3 с на переотдачу сообщения в ленту и реконфиг ячейки. Позже этого
    /// срока легитимной ссылки по этому тапу уже не будет — запрос отвалился сам,
    /// и всё, что могло бы приехать, дало бы только неожиданный звук.
    private static let resolveTimeout: TimeInterval = 18

    private static let buttonColor = Color(red: 75 / 255, green: 51 / 255, blue: 182 / 255)

    /// Кнопка play (40) + отступ `HStack` до волны (12).
    private static let controlsWidth: CGFloat = 40 + 12

    /// Сколько пикселей остаётся волне внутри карточки.
    private static var waveformWidth: CGFloat {
        MessagePublicationQuoteCardView.contentWidth - controlsWidth
    }

    /// Волна, прореженная под ширину карточки.
    ///
    /// 🐞 Иначе она карточку разрывает. `RecordWaveformPlaying` фиксирует свою
    /// ширину через `.fixedSize(horizontal: true)` по ЧИСЛУ СЭМПЛОВ
    /// (`4 × count − 2`), а прореживает только под ширину ЭКРАНА — для голосового
    /// сообщения во всю ширину пузыря этого достаточно, для карточки в 236pt нет.
    /// Продакшеновая запись 12 с — это ~207 сэмплов, то есть ~826pt при доступных
    /// 140: хвост волны срезал `clipShape`, а вместе с ним ломался и перенос
    /// вопроса — раздутая ширина ребёнка уезжала в родительский `VStack`.
    ///
    /// Прореживаем здесь, а не в общем компоненте: у обычных голосовых своя
    /// ширина, и менять её нельзя. Алгоритм — тот же `downsampled`, которым
    /// `RecordWaveformPlaying` ужимает волну под экран, поэтому рисунок остаётся
    /// узнаваемым, а не обрезанным. Побочно чинится и маска прогресса: она
    /// считается от `samples.count`, и на несогласованном числе сэмплов ехала.
    private var recording: Recording {
        Recording(
            duration: Double(voice.durationMs) / 1000,
            waveformSamples: RecordWaveformPlaying.downsampled(
                voice.waveform.map { CGFloat($0) },
                fitting: Self.waveformWidth
            ),
            url: voice.url
        )
    }

    var body: some View {
        RecordWaveformWithButtons(
            recording: recording,
            colorButton: Self.buttonColor,
            colorButtonBg: .white,
            colorWaveform: .white,
            // Ссылки ещё нет — тап только просит приложение её резолвнуть и
            // запоминает намерение. Как только `url` придёт, override снимается,
            // работает штатный плеер, а отложенный старт срабатывает сам —
            // второй тап пользователю не нужен.
            onPlayTap: voice.url == nil ? {
                pendingPlayAfterResolve = true
                onPlay?(voice.fileId)
                startResolveTimeout()
            } : nil,
            pendingPlayAfterResolve: $pendingPlayAfterResolve,
            // Приложению нужен ФАКТ старта, а не факт резолва: между ссылкой и
            // звуком лежат загрузка и декод, и на плохой сети они не доезжают.
            onPlaybackStarted: onPlaybackStarted.map { report in { report(voice.fileId) } }
        )
        // Пересоздавать вью по смене URL не нужно и вредно: `RecordingPlayer.togglePlay`
        // сам замечает новый `recording.url`, а смена identity убила бы уже идущее
        // воспроизведение, если приложение перевыпустит протухшую ссылку.
        .onChange(of: voice.url) { newURL in
            // Ссылка приехала — ждать больше нечего. Сам флаг гасит плеер,
            // стартуя воспроизведение; здесь только снимаем таймер.
            if newURL != nil { cancelResolveTimeout() }
        }
        .onDisappear {
            // Карточка ушла с экрана — намерение больше не актуально: вернувшись,
            // пользователь не ждёт, что голос заиграет сам.
            cancelResolveTimeout()
            pendingPlayAfterResolve = false
        }
    }

    private func startResolveTimeout() {
        resolveTimeoutTask?.cancel()
        resolveTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.resolveTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            // Молча: повторный тап никто не запрещает.
            pendingPlayAfterResolve = false
            resolveTimeoutTask = nil
        }
    }

    private func cancelResolveTimeout() {
        resolveTimeoutTask?.cancel()
        resolveTimeoutTask = nil
    }
}
