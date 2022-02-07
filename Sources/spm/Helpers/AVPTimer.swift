//
//  File.swift
//  
//
//  Created by albert vila on 6/2/22.
//

import Foundation

class AVPTimer: NSObject {
    private var runCount: Int = 0
    private var timer: Timer?
    
    func fireTimer() throws {
        if #available(macOS 10.12, *) {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.runCount = self.runCount == 4 ? 0 : self.runCount
                var text: String {
                    switch self.runCount {
                    case 0: return "Wait."
                    case 1: return "Wait.."
                    case 2: return "Wait..."
                    case 3: return "🙏 🙏 🙏"
                    default: fatalError("glups..") }
                }
                Print.keepingLine(text, .magenta)
                self.runCount += 1
            }
            RunLoop.current.run(mode: .default, before: .distantFuture)
        } else {
            throw "check macOS version"
        }
    }
    func stopTimer() {
        fflush(__stdoutp)
        timer?.invalidate()
        timer = nil
    }
}
