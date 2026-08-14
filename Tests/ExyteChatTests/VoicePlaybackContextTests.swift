import Testing
import Foundation
@testable import ExyteChat

struct VoicePlaybackContextTests {

    private let mine = URL(fileURLWithPath: "/tmp/mine.m4a")
    private let other = URL(fileURLWithPath: "/tmp/other.m4a")

    @Test
    func matching_sameURL_returnsSelf() {
        let context = VoicePlaybackContext(
            assetURL: mine, progress: 0.42, secondsLeft: 3, isPlaying: true
        )
        #expect(context.matching(mine) == context)
    }

    @Test
    func matching_foreignURL_returnsNotLoaded() {
        let context = VoicePlaybackContext(
            assetURL: other, progress: 0.42, secondsLeft: 3, isPlaying: true
        )
        #expect(context.matching(mine) == .notLoaded)
    }

    @Test
    func matching_nilURL_returnsNotLoaded() {
        let context = VoicePlaybackContext(
            assetURL: mine, progress: 0.42, secondsLeft: 3, isPlaying: true
        )
        #expect(context.matching(nil) == .notLoaded)
    }

    // Ключевое свойство для производительности: неиграющая строка на каждом
    // тике плеера обязана получать ОДНО И ТО ЖЕ значение, иначе SwiftUI будет
    // перерисовывать всю ленту 5-10 раз в секунду.
    @Test
    func matching_foreignURL_isStableAcrossTicks() {
        let tick1 = VoicePlaybackContext(
            assetURL: other, progress: 0.1, secondsLeft: 9, isPlaying: true
        )
        let tick2 = VoicePlaybackContext(
            assetURL: other, progress: 0.9, secondsLeft: 1, isPlaying: true
        )
        #expect(tick1.matching(mine) == tick2.matching(mine))
    }

    @Test
    func notLoaded_isIdle() {
        #expect(VoicePlaybackContext.notLoaded.assetURL == nil)
        #expect(VoicePlaybackContext.notLoaded.progress == 0)
        #expect(VoicePlaybackContext.notLoaded.isPlaying == false)
    }
}
