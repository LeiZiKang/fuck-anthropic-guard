import Foundation
import Darwin
struct ProcessIdentity: Codable, Hashable {
    let pid: Int32
    let effectiveUID: uid_t
    let startSeconds: UInt64
    let startMicroseconds: UInt64
    let executablePath: String
}
