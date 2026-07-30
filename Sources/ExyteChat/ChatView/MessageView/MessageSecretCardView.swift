//
//  MessageSecretCardView.swift
//  Chat
//
//  Карточка-цитата секрета: вопрос + ответ владельца анкеты (текст или голос).
//  Карточка одинакова для входящего и исходящего — это цитата ЧУЖОГО секрета
//  в обе стороны; зеркалится только пузырь ответа поверх неё (см. MessageView).
//

import SwiftUI

struct MessageSecretCardView: View {

    let attachment: MessageSecretAttachment
    /// Не влияет на оформление карточки (она одинакова в обе стороны) — оставлен
    /// в сигнатуре как контекст композиции и точка расширения.
    let isOutgoing: Bool

    // MARK: - Layout

    private enum Layout {
        static let width: CGFloat = 236
        static let corner: CGFloat = 24
        static let padding: CGFloat = 24
        static let answerLineLimit: Int = 4
        static let accentLineWidth: CGFloat = 4
        static let dividerWidth: CGFloat = 88
        static let dividerHeight: CGFloat = 4
        static let quoteFontSize: CGFloat = 56
    }

    // MARK: - Colors (макет «Ответ на секрет»)

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

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: Layout.accentLineWidth / 2)
                    .fill(Self.accentLineColor)
                    .frame(width: Layout.accentLineWidth)

                Text(attachment.question)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Self.questionColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)

            RoundedRectangle(cornerRadius: Layout.dividerHeight / 2)
                .fill(Self.dividerColor)
                .frame(width: Layout.dividerWidth, height: Layout.dividerHeight)
                .padding(.top, 14)
                .padding(.leading, 16)

            content
                .padding(.top, 18)
        }
        .padding(Layout.padding)
        .frame(width: Layout.width, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Layout.corner, style: .continuous))
    }

    // MARK: - Content

    /// Правило контента: голос вытесняет курсивную цитату.
    @ViewBuilder
    private var content: some View {
        if let voice = attachment.voice {
            SecretVoicePill(voice: voice, onPlay: attachment.onPlay)
        } else if let answer = attachment.answer, !answer.isEmpty {
            Text(answer)
                .font(.custom("Times New Roman", size: 20).italic())
                .foregroundColor(.white)
                .lineLimit(Layout.answerLineLimit)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Background

    private var cardBackground: some View {
        ZStack {
            // 158° из макета: направление (sin158°, cos158°) в экранных координатах.
            LinearGradient(
                colors: [Self.gradientTop, Self.gradientMid, Self.gradientBottom],
                startPoint: UnitPoint(x: 0.313, y: 0.036),
                endPoint: UnitPoint(x: 0.687, y: 0.964)
            )

            RadialGradient(
                colors: [Color.white.opacity(0.18), Color.white.opacity(0)],
                center: UnitPoint(x: 0.5, y: 0),
                startRadius: 0,
                endRadius: Layout.width * 0.85
            )

            decorativeQuotes
        }
    }

    /// Кавычки Georgia 10% белого: верхняя слева, нижняя справа повёрнута на 180°.
    private var decorativeQuotes: some View {
        ZStack {
            Text(verbatim: "\u{201C}")
                .font(.custom("Georgia", size: Layout.quoteFontSize))
                .foregroundColor(Color.white.opacity(0.1))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 10)
                .padding(.top, -4)

            Text(verbatim: "\u{201C}")
                .font(.custom("Georgia", size: Layout.quoteFontSize))
                .foregroundColor(Color.white.opacity(0.1))
                .rotationEffect(.degrees(180))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 10)
                .padding(.bottom, -4)
        }
        .allowsHitTesting(false)
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
struct SecretVoicePill: View {

    let voice: MessageSecretAttachment.Voice
    let onPlay: ((String) -> Void)?

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

    private var recording: Recording {
        Recording(
            duration: Double(voice.durationMs) / 1000,
            waveformSamples: voice.waveform.map { CGFloat($0) },
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
            pendingPlayAfterResolve: $pendingPlayAfterResolve
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
