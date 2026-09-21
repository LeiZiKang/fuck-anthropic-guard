import Foundation
struct RegionObservation { let path: RegionPath; let country: String?; let failure: LocalizedMessage?; var exitAddress: String? = nil }
enum RegionPath { case system, ipv6 }
struct RegionReport {
 let checkedAt: Date
 var checkedUptime = LeaseClock.now
 let ipv6Available: Bool?
 let observations: [RegionObservation]
 var proxyOwner: ProcessIdentity? = nil
 func canProvideFilterLease(at now: Date, uptime: TimeInterval) -> Bool {
  uptime >= checkedUptime && uptime-checkedUptime < 8 && now.timeIntervalSince(checkedAt) >= 0 && now.timeIntervalSince(checkedAt) < 8 && observations.count == 1 && observations[0].path == .system && observations[0].failure == nil && observations[0].exitAddress != nil
 }
}
