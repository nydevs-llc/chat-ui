//
//  RecordWaveform.swift
//  
//
//  Created by Alisa Mylnikova on 14.03.2023.
//

import SwiftUI

struct RecordWaveformWithButtons: View {

    @Environment(\.chatTheme) private var theme

    @StateObject var recordPlayer = RecordingPlayer()

    var recording: Recording

    var colorButton: Color
    var colorButtonBg: Color
    var colorWaveform: Color
    /// Внешний обработчик тапа по play. Когда задан — форк не проигрывает сам:
    /// URL короткоживущий и резолвится в приложении (карточка секрета).
    /// Штатные вызовы параметр не передают и работают как раньше.
    var onPlayTap: (() -> Void)? = nil
    /// Однократный триггер отложенного старта: пользователь уже нажал play, но
    /// ссылки тогда ещё не было. Как только `recording.url` приезжает,
    /// воспроизведение стартует само и флаг сбрасывается.
    ///
    /// Не «играть при появлении готового URL»: флаг поднимает только явный тап,
    /// поэтому ячейка, приехавшая на экран с уже готовой ссылкой, молчит.
    /// Штатные вызовы параметр не передают → `onChange` ниже ничего не делает.
    var pendingPlayAfterResolve: Binding<Bool>? = nil
    /// Звук ФАКТИЧЕСКИ пошёл: playhead сдвинулся с нуля.
    ///
    /// Сигнал снят с `recordPlayer.progress`, а НЕ с `playing`, и это принципиально.
    /// `RecordingPlayer.play()` делает `player?.play(); playing = true` без единой
    /// проверки статуса item'а: протухшая ссылка, `.failed` или провал декода дадут
    /// `playing == true` вообще без звука — ровно на плохой сети, ради которой
    /// метрика и заводится.
    ///
    /// `progress` же заполняет периодический наблюдатель времени, и только после
    /// `guard !item.duration.seconds.isNaN`: ненулевое значение означает, что asset
    /// разобран, длительность известна и playhead реально едет. Это ближайшее к
    /// «звук слышно», что доступно, — и достигается без единой правки плеера
    /// (`progress` уже `@Published`).
    ///
    /// Альтернативу `playerItem.status == .readyToPlay` не выбрал: статус живёт
    /// приватным полем `RecordingPlayer`, наружу не публикуется, и его пришлось бы
    /// прокидывать новым `@Published` — правка плеера ради сигнала слабее (готовность
    /// играть ≠ playhead поехал).
    ///
    /// Зовётся и на возобновление после паузы: защёлка снимается, когда плеер уходит
    /// из `playing`. Дедупликация — на стороне приложения, где она переживает
    /// переиспользование ячеек.
    ///
    /// Штатные голосовые сообщения параметр не передают: замыкание `nil`, и оба
    /// `onChange` ниже выходят по первому же `guard`, не трогая даже `@State`.
    var onPlaybackStarted: (() -> Void)? = nil

    /// Защёлка на одно проигрывание: `progress` тикает каждые 0.2 с, и без неё
    /// «старт» улетал бы десятками раз за трек.
    @State private var didReportPlaybackStart = false

    var duration: Int {
        return max(Int((recordPlayer.secondsLeft != 0 ? recordPlayer.secondsLeft : recording.duration)), 0)
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if recordPlayer.playing {
                    theme.images.message.pauseAudio
                        .renderingMode(.template)
                } else {
                    theme.images.message.playAudio
                        .renderingMode(.template)
                }
            }
            .foregroundColor(colorButton)
            .viewSize(40)
            .circleBackground(colorButtonBg)
            .highPriorityGesture(TapGesture().onEnded {
                if let onPlayTap {
                    onPlayTap()
                } else {
                    recordPlayer.togglePlay(recording)
                }
            })
            
            VStack(alignment: .leading, spacing: 5) {
                RecordWaveformPlaying(samples: recording.waveformSamples, progress: recordPlayer.progress, color: colorWaveform, addExtraDots: false)
                Text(DateFormatter.timeString(duration))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundColor(colorWaveform)
            }
        }
        .onChange(of: recording.url) { newURL in
            // Ссылка доехала после того, как пользователь нажал play, — стартуем
            // сами. Для штатных голосовых `recording.url` не меняется, а
            // `pendingPlayAfterResolve` не передан, так что путь мёртв.
            guard newURL != nil,
                  pendingPlayAfterResolve?.wrappedValue == true,
                  !recordPlayer.playing else { return }
            pendingPlayAfterResolve?.wrappedValue = false
            var resolved = recording
            resolved.url = newURL
            recordPlayer.togglePlay(resolved)
        }
        .onChange(of: recordPlayer.progress) { progress in
            // `onPlaybackStarted` в guard первым: у штатных голосовых он nil, и
            // ветка выходит здесь же, не трогая `@State` и не вызывая перерисовку.
            guard let onPlaybackStarted,
                  !didReportPlaybackStart,
                  progress > 0,
                  recordPlayer.playing else { return }
            didReportPlaybackStart = true
            onPlaybackStarted()
        }
        .onChange(of: recordPlayer.playing) { isPlaying in
            // Пауза/конец трека снимают защёлку: возобновление — это снова старт.
            guard onPlaybackStarted != nil, !isPlaying else { return }
            didReportPlaybackStart = false
        }
    }
}

struct RecordWaveformPlaying: View {

    var samples: [CGFloat] // 0...1
    var progress: CGFloat
    var color: Color
    var addExtraDots: Bool

    var maxLength: CGFloat {
        max((RecordWaveform.spacing + RecordWaveform.width) * CGFloat(samples.count) - RecordWaveform.spacing, 0)
    }

    var body: some View {
        GeometryReader { g in
            ZStack {
                let adjusted = adjustedSamples(g.size.width)
                RecordWaveform(samples: adjusted, addExtraDots: addExtraDots)
                    .foregroundColor(color.opacity(0.4))
                RecordWaveform(samples: adjusted, addExtraDots: addExtraDots)
                    .foregroundColor(color)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: maxLength * progress, height: 2*RecordWaveform.maxSampleHeight)
                    }
            }
            .frame(height: RecordWaveform.maxSampleHeight)
        }
        .frame(height: RecordWaveform.maxSampleHeight)
        .applyIf(!addExtraDots) {
            $0.frame(width: maxLength)
        }
        .frame(maxWidth: addExtraDots ? .infinity : maxLength)
        .fixedSize(horizontal: !addExtraDots, vertical: true)
    }

    func adjustedSamples(_ width: CGFloat) -> [CGFloat] {
        let maxWidth = addExtraDots ? width : UIScreen.main.bounds.width
        let maxSamples = Int(maxWidth / (RecordWaveform.width + RecordWaveform.spacing))

        var adjusted = samples
        var temp = [CGFloat]()
        while adjusted.count > maxSamples {
            var i = 0
            while i < adjusted.count {
                if i == adjusted.count - 1 {
                    temp.append(adjusted[i])
                    break
                }

                temp.append((adjusted[i] + adjusted[i+1])/2)
                i+=2
            }
            adjusted = temp
            temp = []
        }
        return adjusted
    }
}

struct RecordWaveform: View {

    var samples: [CGFloat] // 0...1
    var addExtraDots: Bool

    static let spacing: CGFloat = 2
    static let width: CGFloat = 2
    static let maxSampleHeight: CGFloat = 20

    var body: some View {
        GeometryReader { g in
            HStack(alignment: .bottom, spacing: RecordWaveform.spacing) {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, s in
                    Capsule()
                        .frame(width: RecordWaveform.width, height: RecordWaveform.maxSampleHeight * CGFloat(s))
                }

                if addExtraDots {
                    ForEach(samples.count..<Int(g.size.width / (RecordWaveform.width + RecordWaveform.spacing)), id: \.self) { _ in
                        Capsule()
                            .viewSize(RecordWaveform.width)
                    }
                }
            }
            .frame(height: RecordWaveform.maxSampleHeight)
        }
        .frame(height: RecordWaveform.maxSampleHeight)
        .fixedSize(horizontal: !addExtraDots, vertical: true)
    }
}
