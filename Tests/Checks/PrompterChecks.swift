@testable import Ada
@testable import AdaCore
import AppKit
import SwiftUI

enum PrompterChecks {
 @MainActor static func main() {
    let store = PrompterStore()
    store.replaceScript("Teleprompter deneme metni.\nİkinci satır.")
    assert(store.hasScript)
    store.setTravel(100)
    store.play()
    RunLoop.main.run(until: Date().addingTimeInterval(0.12))
    assert(store.offset > 0 && store.isPlaying)
    store.pause()
    let paused = store.offset
    RunLoop.main.run(until: Date().addingTimeInterval(0.08))
    assert(store.offset == paused && !store.isPlaying)
    store.scrub(translation: -20)
    assert(abs(store.offset - (paused + 20)) < 0.1)
    store.endScrub()
    store.reset()
    assert(store.offset == 0 && !store.isPlaying)
    store.speed = 100
    store.setTravel(5)
    store.play()
    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    assert(store.finished && !store.isPlaying && store.progress == 1)
    let restored = PrompterStore()
    assert(restored.script == store.script && restored.speed == 100)
    print("PASS: teleprompter playback, pause, scrubbing, reset, completion and persistence")
}

}
