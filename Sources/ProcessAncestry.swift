import Foundation

struct AncestryNode {
    let pid: Int32
    let parent: Int32
    let uid: UInt32
    let startedBefore: UInt64
    let startedAfter: UInt64
    let officialSignature: Bool
}
enum VerifiedAncestry {
    /// Every link must be stable and same-user. Names are never considered.
    static func containsOfficialParent(of pid: Int32, uid: UInt32, read: (Int32) -> AncestryNode?) -> Bool {
        var current = pid
        var seen = Set<Int32>()
        var chain: [AncestryNode] = []
        for depth in 0..<16 {
            guard current > 1, seen.insert(current).inserted, let node = read(current), node.pid == current,
                  node.uid == uid, node.startedBefore == node.startedAfter else { return false }
            if let child = chain.last, node.startedBefore > child.startedBefore { return false }
            chain.append(node)
            if depth > 0 && node.officialSignature {
                // Re-read every edge after traversing the chain; PID reuse or
                // reparenting during the walk is not proof of ancestry.
                return chain.allSatisfy { old in
                    guard let fresh = read(old.pid) else { return false }
                    return fresh.parent == old.parent && fresh.uid == old.uid
                        && fresh.startedBefore == old.startedBefore && fresh.startedAfter == old.startedAfter
                        && fresh.officialSignature == old.officialSignature
                }
            }
            current = node.parent
        }
        return false
    }
}
