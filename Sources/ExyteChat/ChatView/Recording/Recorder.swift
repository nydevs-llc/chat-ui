//
//  Recorder.swift
//
//
//  Created by Alisa Mylnikova on 09.03.2023.
//

import Foundation
import AVFoundation
import SwiftOGG

final class Recorder {

    // duration and waveform samples
    typealias ProgressHandler = (Double, [CGFloat]) -> Void

    /// Пауза между активацией входного маршрута и началом записи в файл.
    ///
    /// `setActive(true)` только ЗАПУСКАЕТ вход; первые буферы, которые отдаёт
    /// HAL, содержат переходный процесс тракта (замер на реальных записях
    /// симулятора: широкополосный всплеск 6–50 мс с пиком −30 dBFS при уровне
    /// соседних участков −85…−100 dBFS — это и есть слышимый «пшик»). Дальше
    /// AGC ещё ~100 мс отдаёт почти нули.
    ///
    /// 0.1 с — вдвое больше измеренной длительности всплеска и при этом не
    /// съедает речь: в эти 100 мс микрофон физически не отдаёт валидный сигнал,
    /// так что терять нечего — вопрос только в том, попадёт ли мусор в файл.
    private static let inputWarmUp: TimeInterval = 0.1

    /// Шаг опроса metering. Один сэмпл в секунду (было) — это одна полоска волны
    /// в секунду: первую секунду записи волна стоит на месте. 0.06 с совпадает с
    /// дейтинговым `VoiceRecorderService`, где волна визуально плотная.
    private static let meteringInterval: TimeInterval = 0.06

    private let audioSession = AVAudioSession()
    private var audioRecorder: AVAudioRecorder?
    private var audioTimer: Timer?

    private var soundSamples: [CGFloat] = []
    private var m4aRecordingUrl: URL?

    var isAllowedToRecordAudio: Bool {
        audioSession.recordPermission == .granted
    }

    var isRecording: Bool {
        audioRecorder?.isRecording ?? false
    }

    func startRecording(durationProgressHandler: @escaping ProgressHandler) async -> URL? {
        if !isAllowedToRecordAudio {
            let granted = await audioSession.requestRecordPermission()
            if granted {
                return startRecordingInternal(durationProgressHandler)
            }
            return nil
        } else {
            return startRecordingInternal(durationProgressHandler)
        }
    }

    private func startRecordingInternal(_ durationProgressHandler: @escaping ProgressHandler) -> URL? {
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        soundSamples = []
        let recordingUrl = FileManager.tempAudioFile
        m4aRecordingUrl = recordingUrl

        do {
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true)
            let recorder = try AVAudioRecorder(url: recordingUrl, settings: settings)
            audioRecorder = recorder
            recorder.isMeteringEnabled = true

            // `prepareToRecord()` обязателен по двум причинам. Первая: только
            // после него `deviceCurrentTime` определён (до подготовки часы
            // устройства читать нельзя). Вторая: он создаёт файл и поднимает
            // очередь заранее, поэтому старт по расписанию ниже точен.
            guard recorder.prepareToRecord() else {
                stopRecording()
                return nil
            }

            // Старт по расписанию, а не `record()`. `AudioQueueStart` запускает
            // устройство немедленно и лишь ОТКРЫВАЕТ поток в файл в назначенный
            // момент — тракт успевает устояться «вхолостую», и переходный
            // процесс в файл не попадает. `record()` пишет с первого же буфера.
            guard recorder.record(atTime: recorder.deviceCurrentTime + Self.inputWarmUp) else {
                stopRecording()
                return nil
            }
            durationProgressHandler(0.0, [])

            NotificationCenter.default.post(name: .recordingStarted, object: self)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let timer = Timer(timeInterval: Self.meteringInterval, repeats: true) { [weak self] _ in
                    self?.onTimer(durationProgressHandler)
                }
                // `.common`, а не `scheduledTimer` (тот встаёт в `.default`).
                // На секундном шаге это было незаметно, но 16 тиков в секунду
                // обязаны идти и во время трекинга жеста, иначе волна замирает
                // ровно на то время, пока палец держит кнопку записи.
                RunLoop.main.add(timer, forMode: .common)
                self.audioTimer = timer
            }

            return recordingUrl
        } catch {
            stopRecording()
            return nil
        }
    }

    func onTimer(_ durationProgressHandler: @escaping ProgressHandler) {
        guard let audioRecorder else { return }
        // До назначенного момента старта запись ещё не идёт: метр отдал бы
        // −160 dB «тишины», которой в файле нет, а `currentTime` — ноль.
        // Полоску за этот тик не рисуем, чтобы волна не начиналась с провала.
        guard audioRecorder.isRecording, audioRecorder.currentTime > 0 else { return }

        audioRecorder.updateMeters()
        let power = audioRecorder.averagePower(forChannel: 0)
        // power from 0 db (max) to -60 db (roughly min)
        let adjustedPower = 1 - (max(power, -60) / 60 * -1)
        soundSamples.append(CGFloat(adjustedPower))
        durationProgressHandler(audioRecorder.currentTime, soundSamples)
    }

    func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        audioTimer?.invalidate()
        audioTimer = nil
        NotificationCenter.default.post(name: .recordingStopped, object: self)
    }

    /// Converts the last recorded m4a file to Opus/OGG format.
    /// Returns the OGG file URL on success, nil on failure.
    func convertLastRecordingToOGG() -> URL? {
        guard let m4aUrl = m4aRecordingUrl else { return nil }
        let oggUrl = FileManager.tempOggFile
        do {
            try OGGConverter.convertM4aFileToOpusOGG(src: m4aUrl, dest: oggUrl)
            try? FileManager.default.removeItem(at: m4aUrl)
            m4aRecordingUrl = nil
            return oggUrl
        } catch {
            print("OGG conversion failed: \(error.localizedDescription)")
            return nil
        }
    }
}

extension AVAudioSession {
    func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
