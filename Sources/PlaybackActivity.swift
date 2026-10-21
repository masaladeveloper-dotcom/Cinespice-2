import Foundation

/// VLC can report buffering while decoding continues. Show a spinner only when
/// playback has actually stopped advancing for a sustained interval.
struct PlaybackActivity {
    private var lastTime: Double?
    private var lastAdvance: Date?
    mutating func stalled(time: Double, waiting: Bool, paused: Bool, now: Date = Date()) -> Bool {
        if lastTime == nil || abs(time - (lastTime ?? time)) > 0.05 || paused {
            lastAdvance = now
        }
        lastTime = time
        return waiting && !paused && now.timeIntervalSince(lastAdvance ?? now) >= 2
    }
}
