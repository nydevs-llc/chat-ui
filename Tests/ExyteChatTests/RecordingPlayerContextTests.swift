import Testing
import Foundation
@testable import ExyteChat

@MainActor
struct RecordingPlayerContextTests {

    @Test
    func freshPlayer_contextIsNotLoaded() {
        let player = RecordingPlayer()
        #expect(player.context == .notLoaded)
        #expect(player.currentAssetURL == nil)
    }

    // Контекст обязан быть ПРОИЗВОДНЫМ от полей плеера, а не вести
    // самостоятельную жизнь: иначе появится второй источник истины и они
    // разъедутся ровно в тот момент, когда это труднее всего заметить.
    @Test
    func contextMirrorsPublishedFields() {
        let player = RecordingPlayer()
        let url = URL(fileURLWithPath: "/tmp/a.m4a")

        player.applyContextForTesting(
            assetURL: url, progress: 0.5, secondsLeft: 2, isPlaying: true
        )

        #expect(player.context.assetURL == url)
        #expect(player.context.progress == 0.5)
        #expect(player.context.secondsLeft == 2)
        #expect(player.context.isPlaying == true)
    }
}
