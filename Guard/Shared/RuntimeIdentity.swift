import Foundation
import Security
import Darwin

enum KernelIdentity {
    static func capture(_ pid: Int32) -> ProcessIdentity? {
        guard pid > 1 else { return nil }
        var info = proc_bsdinfo(); let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_status != UInt32(SZOMB) else { return nil }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN)*4)
        guard proc_pidpath(pid,&path,UInt32(path.count)) > 0 else { return nil }
        return ProcessIdentity(pid:pid,effectiveUID:info.pbi_uid,startSeconds:info.pbi_start_tvsec,startMicroseconds:info.pbi_start_tvusec,executablePath:String(cString:path))
    }
    static func verifiedSurge(_ identity: ProcessIdentity) -> Bool {
        guard capture(identity.pid) == identity else { return false }
        var code: SecCode?; var requirement: SecRequirement?
        let text = "anchor apple generic and identifier \"com.nssurge.surge-mac\" and certificate leaf[subject.OU] = \"YCKFLA6N72\""
        return SecCodeCopyGuestWithAttributes(nil,[kSecGuestAttributePid as String:NSNumber(value:identity.pid)] as CFDictionary,[],&code) == errSecSuccess
            && SecRequirementCreateWithString(text as CFString,[],&requirement) == errSecSuccess
            && code.map { SecCodeCheckValidity($0,[],requirement) == errSecSuccess } == true && capture(identity.pid) == identity
    }
}
func captureProcessIdentity(pid: Int32) -> ProcessIdentity? {
    guard geteuid() != 0, let identity = KernelIdentity.capture(pid), identity.effectiveUID == geteuid() else { return nil }
    return identity
}
