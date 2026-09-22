import Foundation
import Darwin

/// This describes a client socket constraint, not proof of the proxy's remote route.
struct ProxyEndpoint: Codable, Equatable {
    let address: String
    let port: UInt16
    var kind: String = "http"
    static func parse(address: String, port: String, kind: String = "http") -> ProxyEndpoint? {
        guard ["http", "socks"].contains(kind), let normalized = IPAddress.normalize(address), let number = UInt16(port), number > 0,
              normalized == "::1" || normalized.hasPrefix("127.") else { return nil }
        return ProxyEndpoint(address: normalized, port: number, kind: kind)
    }
    func matches(address: String?, port: String?, tcp: Bool) -> Bool {
        guard tcp, let address, let port else { return false }
        return IPAddress.normalize(address) == self.address && UInt16(port) == self.port
    }
    var label: String { address.contains(":") ? "[\(address)]:\(port)" : "\(address):\(port)" }
}

enum IPAddress {
    static func normalize(_ text: String) -> String? {
        guard !text.isEmpty, !text.contains("%"), !text.contains("\n"), text == text.trimmingCharacters(in: .whitespaces) else { return nil }
        for family in [AF_INET, AF_INET6] {
            var bytes = [UInt8](repeating: 0, count: 16)
            if text.withCString({ inet_pton(family, $0, &bytes) }) == 1 {
                // Canonicalize IPv4-mapped IPv6 so equivalent socket endpoints match.
                if family == AF_INET6 && bytes.prefix(10).allSatisfy({ $0 == 0 }) && bytes[10] == 255 && bytes[11] == 255 {
                    return bytes.suffix(4).map(String.init).joined(separator: ".")
                }
                var output = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                guard inet_ntop(family, &bytes, &output, socklen_t(output.count)) != nil else { return nil }
                return String(cString: output)
            }
        }
        return nil
    }
}

struct RouteRequirements: Codable, Equatable {
    var proxy: ProxyEndpoint?
    var expectedExitAddresses: [String] = []
    var protectedBundleIDs: [String] = []
    var expectedProfileDigest: String = ""
    var surgePolicy = ""
    var localAuditConfigured: Bool {
        isConfigured && proxy?.kind == "http" && ![6152,6153,6162,6163].contains(proxy?.port ?? 0)
            && expectedProfileDigest.count == 64 && expectedProfileDigest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
            && !surgePolicy.isEmpty && !surgePolicy.contains(where: { ",\n\r".contains($0) })
    }
    var isConfigured: Bool {
        guard let proxy, ProxyEndpoint.parse(address: proxy.address, port: String(proxy.port), kind: proxy.kind) == proxy,
              !expectedExitAddresses.isEmpty, expectedExitAddresses.count <= 16,
              protectedBundleIDs.count <= 128, protectedBundleIDs.allSatisfy(FilterDecisionState.validBundleID) else { return false }
        return expectedExitAddresses.allSatisfy { IPAddress.normalize($0) == $0 }
    }
    static func parse(proxyAddress: String, proxyPort: String, exits: String, kind: String = "http", scope: String = "") -> RouteRequirements? {
        let values = exits.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
        guard let proxy = ProxyEndpoint.parse(address: proxyAddress, port: proxyPort, kind: kind), !values.isEmpty, values.count <= 16 else { return nil }
        let canonical = values.compactMap(IPAddress.normalize)
        guard canonical.count == values.count else { return nil }
        let identifiers = Array(Set(scope.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init))).sorted()
        guard identifiers.count <= 128, identifiers.allSatisfy(FilterDecisionState.validBundleID) else { return nil }
        return RouteRequirements(proxy: proxy, expectedExitAddresses: Array(Set(canonical)).sorted(), protectedBundleIDs: identifiers)
    }
    func evaluateProbe(report: RegionReport?, now: Date, uptime: TimeInterval) -> RouteGateResult {
        guard isConfigured else { return .unconfigured }
        guard let report, report.canProvideFilterLease(at: now, uptime: uptime) else { return .probeUnavailable }
        // Every observed family must match; an absent family is handled by report validation.
        guard report.observations.allSatisfy({ $0.exitAddress.flatMap(IPAddress.normalize) != nil }) else { return .exitUnknown }
        return report.observations.allSatisfy { expectedExitAddresses.contains(IPAddress.normalize($0.exitAddress!)!) } ? .matched : .exitMismatch
    }
}

enum RouteGateResult: String {
    case unconfigured, probeUnavailable, exitUnknown, exitMismatch, policyUnverified, matched
    var title: String {
        switch self {
        case .policyUnverified: return L10n.text("策略证据未通过", "Policy unverified")
        case .unconfigured: return L10n.text("设置预期代理与出口", "Set expected proxy and exit")
        case .probeUnavailable: return L10n.text("等待有效探测", "Waiting for a valid probe")
        case .exitUnknown: return L10n.text("探针出口未知", "Probe exit unknown")
        case .exitMismatch: return L10n.text("探针出口不匹配", "Probe exit mismatch")
        case .matched: return L10n.text("探针出口匹配", "Probe exit matches")
        }
    }
}

struct TraceResult {
    let country: String
    let address: String
    static func parse(_ data: Data) -> TraceResult? {
        guard data.count <= 8192, let text = String(data: data, encoding: .utf8) else { return nil }
        let lines: [Substring] = text.split(whereSeparator: \.isNewline)
        let pairs: [(String, String)] = lines.compactMap { (line: Substring) -> (String, String)? in
            guard let separator = line.firstIndex(of: "=") else { return nil }
            return (String(line[..<separator]), String(line[line.index(after: separator)...]))
        }
        let country = pairs.filter { $0.0 == "loc" }.map { $0.1 }
        let ip = pairs.filter { $0.0 == "ip" }.map { $0.1 }
        guard country.count == 1, country[0].utf8.count == 2, country[0].utf8.allSatisfy({ (65...90).contains($0) }),
              ip.count == 1, let normalized = IPAddress.normalize(ip[0]) else { return nil }
        return TraceResult(country: country[0], address: normalized)
    }
}

enum ProtectionReason {
    static func title(_ reason: String) -> String {
        switch reason {
        case "requirements-incomplete": return L10n.text("检查条件尚未完整配置", "Requirements incomplete")
        case "cli-signature-unverified": return L10n.text("Surge CLI 签名未通过", "Surge CLI signature not verified")
        case "mode-or-interception-unverified": return L10n.text("模式或拦截开关未通过检查", "Mode/interception checks failed")
        case "temporary-rules-present-or-unknown": return L10n.text("临时规则不为空或不可读取", "Temporary rules present or unreadable")
        case "dedicated-listener-unverified": return L10n.text("专用监听端口或进程签名未验证", "Dedicated listener/identity unverified")
        case "effective-contract-unverified": return L10n.text("活动配置或首条端口规则未通过", "Effective profile/first port rule failed")
        case "runtime-drift-or-read-failure": return L10n.text("审计前后状态变化或读取失败", "Runtime changed or reads failed")
        case "audit-deadline-exceeded": return L10n.text("本地审计超时，未发放许可", "Local audit exceeded its deadline; no lease")
        case "local-policy-verified": return L10n.text("活动策略契约已通过", "Active policy contract passed")
        case "startup", "restart": return L10n.text("启动锁定，尚无许可", "Startup locked; no lease")
        case "network-change", "network": return L10n.text("网络发生变化", "Network changed")
        case "configuration-change": return L10n.text("网络配置发生变化", "Network configuration changed")
        case "control-lost", "disconnect": return L10n.text("控制通道失联", "Control channel lost")
        case "control-connected": return L10n.text("控制连接更新，需重新检查", "New control session; recheck required")
        case "sleep": return L10n.text("系统休眠", "System sleeping")
        case "wake": return L10n.text("系统恢复，等待验证", "System awake; awaiting verification")
        default: return L10n.text("许可失效或等待验证", "Lease invalid or awaiting verification")
        }
    }
}
