import Foundation
import Network

private final class ProbeDelegate: NSObject, URLSessionTaskDelegate {
    var metrics: URLSessionTaskMetrics?
    let ready = DispatchSemaphore(value:0)
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) { self.metrics = metrics; ready.signal() }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?)->Void) { completionHandler(nil) }
}
private final class ProbeBox: @unchecked Sendable {
    let lock = NSLock(); var ip: String?
    func put(_ ip: String?) { lock.lock(); self.ip=ip; lock.unlock() }
    func get()->String? { lock.lock(); defer { lock.unlock() }; return ip }
}
enum GuardProbe {
    static func collect(endpoint: ProxyEndpoint, owner: ProcessIdentity) -> RegionReport? {
        guard let config = ProxyTransportConfiguration.make(endpoint:endpoint), KernelIdentity.verifiedSurge(owner) else { return nil }
        config.timeoutIntervalForRequest=3; config.timeoutIntervalForResource=3
        let delegate=ProbeDelegate(); let session=URLSession(configuration:config,delegate:delegate,delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        let box=ProbeBox(); let done=DispatchSemaphore(value:0)
        let task=session.dataTask(with:URL(string:"https://api.ipify.org/")!) { data,response,error in
            if error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data, data.count <= 128, let value=String(data:data,encoding:.utf8) { box.put(IPAddress.normalize(value.trimmingCharacters(in:.whitespacesAndNewlines))) }
            done.signal()
        }
        task.resume()
        guard done.wait(timeout:.now()+4) == .success, delegate.ready.wait(timeout:.now()+1) == .success,
              let ip=box.get(), let metrics=delegate.metrics, !metrics.transactionMetrics.isEmpty,
              KernelIdentity.capture(owner.pid)==owner else { task.cancel(); return nil }
        guard metrics.transactionMetrics.allSatisfy({ metric in
            guard metric.isProxyConnection, metric.resourceFetchType == .networkLoad,
                  IPAddress.normalize(metric.remoteAddress ?? "") == endpoint.address, metric.remotePort == Int(endpoint.port),
                  let number=metric.localPort, let local=UInt16(exactly:number) else { return false }
            return ccw_owns_loopback_socket(owner.pid, endpoint.port, local, 0)==1
        }) else { return nil }
        return RegionReport(checkedAt:Date(),ipv6Available:nil,observations:[RegionObservation(path:.system,country:nil,failure:nil,exitAddress:ip)],proxyOwner:owner)
    }
}
