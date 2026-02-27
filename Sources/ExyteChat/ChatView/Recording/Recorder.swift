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
            audioRecorder = try AVAudioRecorder(url: recordingUrl, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            durationProgressHandler(0.0, [])

            NotificationCenter.default.post(name: .recordingStarted, object: self)

            DispatchQueue.main.async { [weak self] in
                self?.audioTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    self?.onTimer(durationProgressHandler)
                }
            }

            return recordingUrl
        } catch {
            stopRecording()
            return nil
        }
    }

    func onTimer(_ durationProgressHandler: @escaping ProgressHandler) {
        audioRecorder?.updateMeters()
        if let power = audioRecorder?.averagePower(forChannel: 0) {
            // power from 0 db (max) to -60 db (roughly min)
            let adjustedPower = 1 - (max(power, -60) / 60 * -1)
            soundSamples.append(CGFloat(adjustedPower))
        }
        if let time = audioRecorder?.currentTime {
            durationProgressHandler(time, soundSamples)
        }
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
