import Foundation
enum GuardianTimer {
 static func repeating(_ interval: TimeInterval, _ body: @escaping ()->Void) -> Timer {
  let timer=Timer(timeInterval:interval,repeats:true) { _ in body() };RunLoop.main.add(timer,forMode:.common);return timer
 }
}

// One alert per unsafe episode; manual holds do not produce failure alarms.
struct SafetyAlertGate {
 private var alerted = false
 mutating func update(monitoring: Bool, safe: Bool) -> Bool {
  guard monitoring else { alerted = false; return false }
  if safe { alerted = false; return false }
  guard !alerted else { return false }
  alerted = true
  return true
 }
}

enum GuardPresentation {
 static func isSafe(monitoring:Bool,routeMatched:Bool,probeFresh:Bool,active:Bool,blocking:Bool) -> Bool {
  monitoring && routeMatched && probeFresh && active && !blocking
 }
}
