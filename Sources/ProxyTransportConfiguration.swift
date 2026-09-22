import Foundation
import Network

/// Per-session routing, never system proxy settings. Fixed mode requires this
/// modern API; unsupported systems fail before attempting a request.
enum ProxyTransportConfiguration {
    static func make(endpoint: ProxyEndpoint) -> URLSessionConfiguration? {
        guard #available(macOS 14.0, *), endpoint.port > 0, let port = NWEndpoint.Port(rawValue: endpoint.port),
              ["http", "socks"].contains(endpoint.kind) else { return nil }
        let target = NWEndpoint.hostPort(host: .init(endpoint.address), port: port)
        var proxy = endpoint.kind == "socks" ? ProxyConfiguration(socksv5Proxy: target) : ProxyConfiguration(httpCONNECTProxy: target)
        proxy.allowFailover = false
        proxy.excludedDomains = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.proxyConfigurations = [proxy]
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        return configuration
    }
}
