import XCTest
@testable import alfy_clean

final class NotificationSoundTests: XCTestCase {
    /// Reads a little-endian unsigned integer of `bytes` bytes at `offset`.
    private func littleEndian(_ data: Data, at offset: Int, bytes: Int) -> Int {
        (0..<bytes).reduce(0) { $0 | Int(data[offset + $1]) << (8 * $1) }
    }

    private func ascii(_ data: Data, at offset: Int) -> String {
        String(decoding: Array(data[offset..<offset + 4]), as: UTF8.self)
    }

    func testWAVHeaderIsMono16BitPCMAt44100Hz() {
        for style in NotificationSound.Style.allCases {
            let wav = NotificationSound.wavData(style: style)

            XCTAssertEqual(ascii(wav, at: 0), "RIFF", "\(style)")
            XCTAssertEqual(ascii(wav, at: 8), "WAVE", "\(style)")
            XCTAssertEqual(ascii(wav, at: 12), "fmt ", "\(style)")
            XCTAssertEqual(ascii(wav, at: 36), "data", "\(style)")

            XCTAssertEqual(littleEndian(wav, at: 4, bytes: 4), wav.count - 8, "\(style) RIFF size")
            XCTAssertEqual(littleEndian(wav, at: 16, bytes: 4), 16, "\(style) fmt chunk size")
            XCTAssertEqual(littleEndian(wav, at: 20, bytes: 2), 1, "\(style) PCM format")
            XCTAssertEqual(littleEndian(wav, at: 22, bytes: 2), 1, "\(style) mono")
            XCTAssertEqual(littleEndian(wav, at: 24, bytes: 4), 44_100, "\(style) sample rate")
            XCTAssertEqual(littleEndian(wav, at: 28, bytes: 4), 88_200, "\(style) byte rate")
            XCTAssertEqual(littleEndian(wav, at: 32, bytes: 2), 2, "\(style) block align")
            XCTAssertEqual(littleEndian(wav, at: 34, bytes: 2), 16, "\(style) bits per sample")
            XCTAssertEqual(littleEndian(wav, at: 40, bytes: 4), wav.count - 44, "\(style) data size")
        }
    }

    func testEverySoundIsBetween0Point4And2Point7Seconds() {
        for style in NotificationSound.Style.allCases {
            let seconds = Double(NotificationSound.samples(for: style).count) / Double(NotificationSound.sampleRate)
            XCTAssertTrue((0.4...2.7).contains(seconds), "\(style): \(seconds) s")
        }
    }

    func testEverySoundIsAudibleButNotClipped() {
        for style in NotificationSound.Style.allCases {
            let peak = NotificationSound.samples(for: style).map { abs(Int($0)) }.max() ?? 0
            XCTAssertGreaterThan(peak, Int(Int16.max) / 4, "\(style) is silent")
            XCTAssertLessThan(peak, Int(Int16.max), "\(style) clips")
        }
    }

    func testEverySoundEndsWithoutAClick() {
        for style in NotificationSound.Style.allCases {
            XCTAssertLessThan(abs(Int(NotificationSound.samples(for: style).last ?? 0)), 50, "\(style)")
        }
    }

    func testFunkDetunedIsTheDefaultStyle() {
        XCTAssertEqual(NotificationSound.wavData(), NotificationSound.wavData(style: .funkDetuned))
        XCTAssertEqual(NotificationSound.samples(), NotificationSound.samples(for: .funkDetuned))
    }

    func testFunkReversedIsTheFunkGrooveBackwardsAndSlower() {
        let forward = NotificationSound.funkSamples(tempo: NotificationSound.funkReversedTempo)
        XCTAssertEqual(NotificationSound.funkReversedSamples(), Array(forward.reversed()))
        XCTAssertEqual(
            Double(forward.count), Double(NotificationSound.funkSamples().count) / NotificationSound.funkReversedTempo, accuracy: 2
        )
    }

    func testRitardandoSlowsDownByThreeQuartersOverTheGroove() {
        let onsets = NotificationSound.funkRitardandoOnsets()
        XCTAssertEqual(onsets.count, 6)
        // Played backwards, the gaps in 16th-note steps are 1, 2, 2, 1, 3 (the original groove read from the end).
        let steps = [1.0, 2, 2, 1, 3]
        let secondsPerStep = zip(zip(onsets, onsets.dropFirst()), steps).map { ($0.1 - $0.0) / $1 }
        XCTAssertEqual(secondsPerStep.first ?? 0, 0.125, accuracy: 0.015)
        for (before, after) in zip(secondsPerStep, secondsPerStep.dropFirst()) {
            XCTAssertLessThan(before, after, "each step lasts longer than the last")
        }
        // The last gap averages the tempo between 50% and 25%: its steps are 0.125 / 0.5 ... 0.125 / 0.25 s long.
        XCTAssertGreaterThan(secondsPerStep.last ?? 0, 0.125 / 0.5)
        XCTAssertLessThan(secondsPerStep.last ?? 0, 0.125 / 0.25)
    }

    func testFunkDetunedIsTheOriginalGrooveBackwardsAndTunedDown() {
        let detuned = NotificationSound.funkDetunedSamples()
        XCTAssertEqual(detuned, Array(NotificationSound.funkSamples(semitones: NotificationSound.funkDetuneSemitones).reversed()))
        XCTAssertEqual(NotificationSound.funkDetuneSemitones, -2.0)
        // Same tempo and length as the original groove, but a different sound.
        XCTAssertEqual(detuned.count, NotificationSound.funkSamples().count)
        XCTAssertNotEqual(detuned, Array(NotificationSound.funkSamples().reversed()))
    }

    func testStylesSoundDifferent() {
        let styles = NotificationSound.Style.allCases
        for (i, first) in styles.enumerated() {
            for second in styles[(i + 1)...] {
                XCTAssertNotEqual(NotificationSound.samples(for: first), NotificationSound.samples(for: second),
                                  "\(first) and \(second) are identical")
            }
        }
    }

    func testCacheFileNames() {
        XCTAssertEqual(NotificationSound.Style.chime.fileName, "done.wav")
        XCTAssertEqual(NotificationSound.Style.marimba.fileName, "done-marimba.wav")
        XCTAssertEqual(NotificationSound.Style.bell.fileName, "done-bell.wav")
        XCTAssertEqual(NotificationSound.Style.gong.fileName, "done-gong.wav")
    }
}
