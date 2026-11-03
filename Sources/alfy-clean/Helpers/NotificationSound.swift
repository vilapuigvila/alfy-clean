//
//  NotificationSound.swift
//
//  The sounds that can play with a notification. No audio file ships with the binary: each WAV is synthesized
//  here, written to ~/Library/Caches/alfy-clean and played with afplay. `funkDetuned` is played when a row finishes and `funk` when the menu is ready; the
//  other styles are only synthesized so they can be listened to, and nothing selects them yet.
//

import Foundation

enum NotificationSound {
    /// The synthesized sounds. `NotificationSound.notificationStyle` is the one `sendNotification` plays.
    enum Style: String, CaseIterable {
        case chime, marimba, bell, gong, funk, funkReversed, funkRitardando, funkDetuned

        /// Cache file name: `done.wav` for the chime, `done-<style>.wav` for the others.
        var fileName: String {
            self == .chime ? "done.wav" : "done-\(rawValue).wav"
        }
    }

    /// The sound of the notification that says a row has finished, and the default of the functions below.
    static let notificationStyle: Style = .funkDetuned

    /// The sound of the notification that says the menu is ready (the sizes are measured and the options are shown).
    static let menuReadyStyle: Style = .funk

    static let sampleRate = 44_100

    /// Plays the sound in its own afplay process and returns at once, so the cleanup doesn't wait for it.
    /// Silently does nothing if the file can't be written or afplay can't be started.
    static func play(style: Style = NotificationSound.notificationStyle) {
        guard let url = cachedFileURL(style: style) else { return }
        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = [url.path]
        player.environment = ["PATH": systemSearchPath]
        player.standardInput = FileHandle.nullDevice
        player.standardOutput = FileHandle.nullDevice
        player.standardError = FileHandle.nullDevice
        try? player.run()
    }

    /// `~/Library/Caches/alfy-clean/<style.fileName>`, written first when it is missing or differs from the built-in
    /// sound. Nil if it can't be written.
    static func cachedFileURL(style: Style = NotificationSound.notificationStyle) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let directory = caches.appendingPathComponent("alfy-clean", isDirectory: true)
        let url = directory.appendingPathComponent(style.fileName)
        let wav = wavData(style: style)
        if (try? Data(contentsOf: url)) != wav {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try wav.write(to: url, options: .atomic)
            } catch {
                return nil
            }
        }
        return url
    }

    /// A complete RIFF/WAVE file: 16-bit PCM, mono, `sampleRate` Hz.
    static func wavData(style: Style = NotificationSound.notificationStyle) -> Data {
        let pcm = samples(for: style)
        let dataSize = pcm.count * 2
        var wav = Data()
        func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) }
        }
        wav.append(contentsOf: Array("RIFF".utf8))
        appendLittleEndian(UInt32(36 + dataSize))
        wav.append(contentsOf: Array("WAVEfmt ".utf8))
        appendLittleEndian(UInt32(16))                  // fmt chunk size
        appendLittleEndian(UInt16(1))                   // PCM
        appendLittleEndian(UInt16(1))                   // mono
        appendLittleEndian(UInt32(sampleRate))
        appendLittleEndian(UInt32(sampleRate * 2))      // byte rate: sampleRate x 1 channel x 2 bytes
        appendLittleEndian(UInt16(2))                   // block align
        appendLittleEndian(UInt16(16))                  // bits per sample
        wav.append(contentsOf: Array("data".utf8))
        appendLittleEndian(UInt32(dataSize))
        for sample in pcm {
            appendLittleEndian(sample)
        }
        return wav
    }

    /// The 16-bit mono samples of `style`, at `sampleRate`.
    static func samples(for style: Style = NotificationSound.notificationStyle) -> [Int16] {
        switch style {
        case .chime: return chimeSamples()
        case .marimba: return marimbaSamples()
        case .bell: return bellSamples()
        case .gong: return gongSamples()
        case .funk: return funkSamples()
        case .funkReversed: return funkReversedSamples()
        case .funkRitardando: return funkRitardandoSamples()
        case .funkDetuned: return funkDetunedSamples()
        }
    }

    /// Two rising notes (C6 then G6, a fifth apart). Each is a sine with a soft octave overtone, a 6 ms attack
    /// and an exponential decay.
    static func chimeSamples() -> [Int16] {
        let duration = 0.75
        let notes: [(start: Double, frequency: Double, level: Double)] = [(0.0, 1046.5, 1.0), (0.16, 1568.0, 0.8)]
        let count = Int(duration * Double(sampleRate))
        var mix = [Double](repeating: 0, count: count)
        for note in notes {
            let onset = Int(note.start * Double(sampleRate))
            for index in onset..<count {
                let t = Double(index - onset) / Double(sampleRate)
                let envelope = min(1, t / 0.006) * exp(-6 * t)
                let phase = 2 * Double.pi * note.frequency * t
                mix[index] += note.level * envelope * (sin(phase) + 0.2 * sin(2 * phase))
            }
        }
        return quantize(mix, fadeOut: 0.02)
    }

    /// "Tok, tok, tok": three soft strikes on one wooden bar (E5), each a little quieter than the last. A strike is a
    /// sine with a fast decay, a fainter partial near four times the pitch that dies sooner, a 1.5 ms attack, and a
    /// few milliseconds of low-passed noise for the mallet's contact.
    static func marimbaSamples() -> [Int16] {
        let duration = 0.7
        let frequency = 659.25
        let strikes: [(start: Double, level: Double)] = [(0.0, 1.0), (0.15, 0.8), (0.30, 0.65)]
        let count = Int(duration * Double(sampleRate))
        var mix = [Double](repeating: 0, count: count)
        for (number, strike) in strikes.enumerated() {
            let onset = Int(strike.start * Double(sampleRate))
            var noise = Noise(seed: UInt32(number + 1))
            var contact = 0.0
            for index in onset..<count {
                let t = Double(index - onset) / Double(sampleRate)
                let phase = 2 * Double.pi * frequency * t
                let fundamental = sin(phase) * exp(-9 * t)
                let fourth = 0.3 * sin(3.93 * phase) * exp(-30 * t)
                let highPartial = 0.08 * sin(9.2 * phase) * exp(-60 * t)
                let tone = min(1, t / 0.0015) * (fundamental + fourth + highPartial)
                contact += 0.3 * (noise.next() - contact)
                let click = 0.12 * contact * exp(-t / 0.002)
                mix[index] += strike.level * (tone + click)
            }
        }
        return quantize(mix, fadeOut: 0.02)
    }

    /// A gentle descending bell figure: A5, F#5, D5, about 0.17 s apart. Each note is a fundamental with a faint
    /// detuned twin (slow beating) and two inharmonic partials that die sooner, so it rings softly and darkens.
    /// A 5.5 Hz tremolo adds the shimmer.
    static func bellSamples() -> [Int16] {
        let duration = 0.85
        let notes: [(start: Double, frequency: Double, level: Double)] = [
            (0.0, 880.0, 1.0), (0.17, 739.99, 0.85), (0.34, 587.33, 0.75),
        ]
        let count = Int(duration * Double(sampleRate))
        var mix = [Double](repeating: 0, count: count)
        for note in notes {
            let onset = Int(note.start * Double(sampleRate))
            for index in onset..<count {
                let t = Double(index - onset) / Double(sampleRate)
                let phase = 2 * Double.pi * note.frequency * t
                let twin = sin(phase * 1.002)
                let fundamental = 0.5 * (sin(phase) + twin) * exp(-5 * t)
                let partialA = 0.35 * sin(2.76 * phase) * exp(-9 * t)
                let partialB = 0.12 * sin(5.4 * phase) * exp(-16 * t)
                let shimmer = 1 + 0.12 * sin(2 * Double.pi * 5.5 * t)
                let attack = min(1, t / 0.003)
                mix[index] += note.level * attack * shimmer * (fundamental + partialA + partialB)
            }
        }
        return quantize(mix, fadeOut: 0.05)
    }

    /// A low, calm "done": two soft gong strikes, C3 then G2, a quarter second apart. The partials are inharmonic and
    /// the upper ones die first, so the tone darkens as it fades, like a closing low-pass filter. A 15 ms swell
    /// replaces a hard attack, a sub-bass sine blooms in over 60 ms, and a little low-passed noise gives a soft thump.
    static func gongSamples() -> [Int16] {
        let duration = 0.88
        let notes: [(start: Double, frequency: Double, level: Double)] = [(0.0, 130.81, 1.0), (0.25, 98.0, 0.8)]
        let count = Int(duration * Double(sampleRate))
        var mix = [Double](repeating: 0, count: count)
        for (number, note) in notes.enumerated() {
            let onset = Int(note.start * Double(sampleRate))
            var noise = Noise(seed: UInt32(number + 7))
            var contact = 0.0
            for index in onset..<count {
                let t = Double(index - onset) / Double(sampleRate)
                let phase = 2 * Double.pi * note.frequency * t
                let fundamental = sin(phase) * exp(-4 * t)
                let partialA = 0.35 * sin(1.42 * phase) * exp(-7 * t)
                let partialB = 0.2 * sin(2 * phase) * exp(-11 * t)
                let partialC = 0.08 * sin(2.9 * phase) * exp(-20 * t)
                let body = min(1, t / 0.015) * (fundamental + partialA + partialB + partialC)
                let sub = 0.4 * sin(0.5 * phase) * min(1, t / 0.06) * exp(-4 * t)
                contact += 0.06 * (noise.next() - contact)
                let thump = 0.5 * contact * exp(-t / 0.008)
                mix[index] += note.level * (body + sub + thump)
            }
        }
        return quantize(mix, fadeOut: 0.06)
    }

    /// The funk groove's notes: the 16th-note step they start on (a step is 0.125 s at 120 bpm), pitch (A minor), length and level.
    private static let funkNotes: [(step: Double, frequency: Double, length: Double, level: Double)] = [
        (0, 55.0, 0.08, 1.0), (3, 110.0, 0.06, 0.7), (4, 98.0, 0.08, 0.9),
        (6, 55.0, 0.08, 0.9), (8, 73.42, 0.08, 0.8), (9, 55.0, 0.16, 1.0)
    ]

    /// One plucked note: a sawtooth-like tone (harmonics 1...24, each 1/n^0.8 as strong), a 3 ms attack, a quick exponential
    /// decay and a small downward pitch settle at the start of the pluck. The higher harmonics die faster, so each pluck
    /// starts bright and gets rounder. The notes (50-110 Hz) are below what laptop speakers can play, so the harmonics
    /// under 100 Hz are left out and those up to 250 Hz fade in: the ear still hears the note's pitch from the ones above.
    private static func funkPluck(frequency: Double, length: Double, level: Double) -> [Double] {
        let noteSamples = Int(length * Double(sampleRate))
        let harmonics = 1...24
        return (0..<noteSamples).map { offset in
            let t = Double(offset) / Double(sampleRate)
            let settled = frequency * (1 + 0.04 * exp(-t / 0.01))
            let phase = 2 * Double.pi * settled * t
            let tone = harmonics.reduce(0.0) { sum, n in
                let number = Double(n)
                let audible = min(1, max(0, (number * frequency - 100) / 150))
                return sum + audible * sin(number * phase) * pow(number, -0.8) * exp(-3 * (number - 1) * t)
            }
            let release = min(1, Double(noteSamples - offset) / (0.01 * Double(sampleRate)))
            let envelope = min(1, t / 0.003) * exp(-12 * t) * release
            return level * envelope * tone
        }
    }

    /// Rounds off the sharp attack peaks of a mix (tanh soft limiting) so the body of the notes comes out louder once the
    /// mix is scaled to its peak. Without it the bright pluck spikes set the peak and the notes sound quiet.
    private static func softLimited(_ mix: [Double]) -> [Double] {
        let peak = mix.map { abs($0) }.max() ?? 0
        guard peak > 0 else { return mix }
        return mix.map { tanh(4 * $0 / peak) }
    }

    /// An original dry, syncopated synth-bass groove in A minor (16th-note feel at 120 bpm): short, tight plucked notes with
    /// clear silence between them, then a slightly longer last note.
    /// `tempo` scales the speed of the groove: 0.67 is a third slower (the notes keep their pitch and length).
    /// `semitones` detunes every note (-1.5 is a semitone and a half lower) without changing the tempo.
    static func funkSamples(tempo: Double = 1.0, semitones: Double = 0) -> [Int16] {
        let duration = 1.3 / tempo
        let step = 0.125 / tempo
        let count = Int(duration * Double(sampleRate))
        var mix = [Double](repeating: 0, count: count)
        for note in funkNotes {
            let onset = Int(note.step * step * Double(sampleRate))
            let pluck = funkPluck(frequency: note.frequency * pow(2, semitones / 12), length: note.length, level: note.level)
            for (offset, value) in pluck.enumerated() where onset + offset < count {
                mix[onset + offset] += value
            }
        }
        return quantize(softLimited(mix), fadeOut: 0.05)
    }

    static let funkReversedTempo = 0.5

    /// The funk groove played backwards and at half speed (tempo 0.5, so the notes are further apart): each pluck becomes a swell into its note, and
    /// the groove ends on its first note. The forward version starts and ends at silence, so the reversed one does too.
    static func funkReversedSamples() -> [Int16] {
        Array(funkSamples(tempo: funkReversedTempo).reversed())
    }

    /// How far `funkDetunedSamples` is tuned down, in semitones.
    static let funkDetuneSemitones = -2.0

    /// The funk groove at its original tempo, played backwards and tuned down two semitones. Each pluck is
    /// reversed, so it swells into its note; the notes keep their length and the groove keeps its tempo.
    static func funkDetunedSamples() -> [Int16] {
        Array(funkSamples(semitones: funkDetuneSemitones).reversed())
    }

    /// How much slower the ritardando ends than it starts: the tempo falls by this share (75%), so it ends at 25%.
    static let ritardandoTempoDrop = 0.75

    /// When each note of `funkRitardandoSamples` starts, in seconds. The groove is played backwards, so its steps
    /// run in reverse order. The tempo falls steadily from 1 to `1 - ritardandoTempoDrop` over the whole groove,
    /// and the time of a gap is the integral of 1 / tempo over its steps.
    static func funkRitardandoOnsets() -> [Double] {
        let steps = funkNotes.map { $0.step }
        let totalSteps = (steps.last ?? 0) - (steps.first ?? 0)
        guard totalSteps > 0 else { return [0] }
        let secondsPerStep = 0.125
        var onsets = [0.0]
        var progress = 0.0
        for index in stride(from: steps.count - 1, to: 0, by: -1) {
            let next = progress + (steps[index] - steps[index - 1]) / totalSteps
            let tempoBefore = 1 - ritardandoTempoDrop * progress
            let tempoAfter = 1 - ritardandoTempoDrop * next
            let seconds = secondsPerStep * totalSteps / ritardandoTempoDrop * log(tempoBefore / tempoAfter)
            onsets.append((onsets.last ?? 0) + seconds)
            progress = next
        }
        return onsets
    }

    /// The funk groove played backwards with a ritardando: it starts at the original tempo and slows steadily until it
    /// is 75% slower. Each pluck is reversed, so it swells into its note; the notes keep their pitch and length.
    static func funkRitardandoSamples() -> [Int16] {
        let onsets = funkRitardandoOnsets()
        let notes = Array(funkNotes.reversed())
        let end = (onsets.last ?? 0) + (notes.last?.length ?? 0)
        var mix = [Double](repeating: 0, count: Int(end * Double(sampleRate)) + 1)
        for (note, onsetSeconds) in zip(notes, onsets) {
            let onset = Int(onsetSeconds * Double(sampleRate))
            let pluck = funkPluck(frequency: note.frequency, length: note.length, level: note.level)
            for (offset, value) in pluck.reversed().enumerated() where onset + offset < mix.count {
                mix[onset + offset] += value
            }
        }
        return quantize(softLimited(mix), fadeOut: 0.005)
    }

    /// Scales a mix so its peak sits at about -6 dBFS, and fades its last `fadeOut` seconds to zero so that playback
    /// stopping on the last sample can't click. Doubles become 16-bit samples.
    private static func quantize(_ mix: [Double], fadeOut: Double) -> [Int16] {
        let count = mix.count
        let fadeLength = fadeOut * Double(sampleRate)
        let peak = max(mix.map { abs($0) }.max() ?? 0, 1e-9)
        let scale = 0.5 * Double(Int16.max) / peak
        return mix.enumerated().map { index, value in
            let fade = min(1, Double(count - index) / fadeLength)
            return Int16((value * scale * fade).rounded())
        }
    }

    /// White noise from a linear congruential generator, so the synthesized files are identical on every run.
    private struct Noise {
        private var state: UInt32

        init(seed: UInt32) {
            state = seed
        }

        /// The next value, between -1 and 1.
        mutating func next() -> Double {
            state = state &* 1_664_525 &+ 1_013_904_223
            return Double(state) / Double(UInt32.max) * 2 - 1
        }
    }
}
