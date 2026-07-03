//
//  File.swift
//  
//
//  Created by albert vila on 6/2/22.
//

import Darwin
import Foundation

class AVPTimer: NSObject {
    private var runCount: Int = 0
    private(set) var timer: Timer?
    
    func fireTimer() throws {
        if #available(macOS 10.12, *) {
            timer = DispatchQueue.runThisEvery(seconds: 1, handler: { [weak self] _ in
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
            })
//            
//            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
//            }
//            guard let tim = timer else {
//                throw "Error timer doesn't exist"
//            }
//            RunLoop.current.add(tim, forMode: RunLoop.Mode("com.rderik.myevents"))
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

extension DispatchQueue {
    @discardableResult
    static func runThisEvery(
        seconds: TimeInterval,
        startAfterSeconds: TimeInterval = 0.0,
        handler: @escaping (CFRunLoopTimer?) -> Void)
    -> Timer? {
        let fireDate = startAfterSeconds + CFAbsoluteTimeGetCurrent()
        let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, fireDate, seconds, 0, 0, handler)
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, CFRunLoopMode.commonModes)
        return timer
    }
}
