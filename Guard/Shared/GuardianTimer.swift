import Foundation
enum GuardianTimer {
 static func repeating(_ interval: TimeInterval, _ body: @escaping ()->Void) -> Timer {
  let timer=Timer(timeInterval:interval,repeats:true) { _ in body() };RunLoop.main.add(timer,forMode:.common);return timer
 }
}
