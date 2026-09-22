import Foundation
func runGuardTests() {
 var count=0
 func check(_ value:Bool,_ name:String) { guard value else { fatalError("TEST FAILED: "+name) };count+=1 }
 let endpoint=ProxyEndpoint.parse(address:"127.0.0.1",port:"6154")!
 check(!endpoint.matches(address:"1.1.1.1",port:"443",tcp:true),"direct remote denied")
 check(!endpoint.matches(address:"127.0.0.1",port:"6152",tcp:true),"shared port denied")
 check(!endpoint.matches(address:"127.0.0.1",port:"6154",tcp:false),"UDP denied")
 check(endpoint.matches(address:"127.0.0.1",port:"6154",tcp:true),"dedicated Surge endpoint")
 check(endpoint.matches(address:"::ffff:127.0.0.1",port:"6154",tcp:true),"mapped loopback")
 for port in ["6152","6153","6162","6163"] {
  var r=RouteRequirements.parse(proxyAddress:"127.0.0.1",proxyPort:port,exits:"203.0.113.10")!;r.expectedProfileDigest=String(repeating:"a",count:64);r.surgePolicy="LOCKED"
  check(!r.localAuditConfigured,"shared and legacy endpoint rejected")
 }
 let source=FilterSourceIdentity(uid:501,bundleID:"com.anthropic.claudefordesktop",official:true,infrastructure:false)
 let surge=FilterSourceIdentity(uid:501,bundleID:"com.nssurge.surge-mac",official:false,infrastructure:true)
 check(FilterScope.classify(owner:501,source:source,hostname:nil,approved:[]) == .protectedFlow,"official process protected without domain")
 check(FilterScope.classify(owner:501,source:surge,hostname:"api.anthropic.com",approved:[]) == .outsideScope,"Surge itself never targeted")
 check(FilterScope.classify(owner:502,source:source,hostname:nil,approved:[]) == .outsideScope,"other user not touched")
 check(FilterScope.classify(owner:501,source:nil,hostname:"api.anthropic.com",approved:[]) == .unknownOwner,"unknown attribution disclosed")
 var p=FilterDecisionState();check(p.blocking(at:100),"startup blocks")
 p.accept(FilterPolicyUpdate(block:false,validUntil:104),at:100)
 check(!p.blocking(at:103),"fresh lease")
 check(p.blocking(at:104),"expiry blocks")
 check(p.blocking(at:99),"clock rollback blocks")
 for expiry in [Double.nan,Double.infinity,99,300] {
  p.accept(FilterPolicyUpdate(block:false,validUntil:expiry),at:100);check(p.blocking(at:100),"invalid deadline")
 }
 var epoch=ProviderLeaseEpoch();let a=UUID();epoch.connect(a);let challenge=epoch.challenge;epoch.invalidate("network")
 check(challenge != epoch.challenge,"network invalidates proof challenge")
 check(!epoch.accepts(session:UUID(),generation:epoch.generation),"foreign controller refused")
 let certificate=String(repeating:"a",count:64)
 let profile="""
 [General]
 http-listen = 127.0.0.1:6152, 127.0.0.1:6154
 [Proxy]
 H2 = hysteria2, <private>, <private>, password=<private>, server-cert-fingerprint-sha256=<private>
 [Proxy Group]
 LOCKED = select, H2
 [Rule]
 IN-PORT,6154,LOCKED
 PROCESS-NAME,/Applications/Xcode.app/,DIRECT
 FINAL,DIRECT
 """
 var r=RouteRequirements(proxy:endpoint,expectedExitAddresses:["203.0.113.10"],expectedProfileDigest:PolicyEvidenceVerifier.digest(Data(profile.utf8)),surgePolicy:"LOCKED")
 check(SurgeContract.validate(profile:profile,requirements:r),"dedicated route through exactly one node")
 for value in [profile.replacingOccurrences(of:"select, H2",with:"select, H2, DIRECT"),profile.replacingOccurrences(of:"IN-PORT,6154,LOCKED",with:"IN-PORT,6154,DIRECT"),profile.replacingOccurrences(of:"H2 = hysteria2",with:"H2 = direct"),profile+"\n[Script]\nx = ignored",profile.replacingOccurrences(of:"password=<private>",with:"password=<private>, skip-cert-verify=true")] {
  r.expectedProfileDigest=PolicyEvidenceVerifier.digest(Data(value.utf8));check(!SurgeContract.validate(profile:value,requirements:r),"unsafe contract rejected")
 }
 r.expectedProfileDigest=certificate
 let identity=ProcessIdentity(pid:123,effectiveUID:501,startSeconds:90,startMicroseconds:0,executablePath:"/Applications/Surge.app/Contents/MacOS/Surge")
 func proof(_ challenge:String="c",_ expiry:Double=105,_ owner:ProcessIdentity?=identity)->LocalPolicyEvidence {
  LocalPolicyEvidence(challenge:challenge,scopeDigest:"scope",activeProfileDigest:certificate,checkedAt:1000,checkedClock:100,expiresClock:expiry,dedicatedPortVerified:true,listenerVerified:true,runtimeStable:true,surgeOwner:owner)
 }
 func valid(_ value:LocalPolicyEvidence?,_ time:Double=101)->Bool { PolicyEvidenceVerifier.valid(value,challenge:"c",scope:"scope",profileDigest:certificate,now:Date(timeIntervalSince1970:1001),uptime:time) }
 check(valid(proof()),"bounded identity proof")
 check(!valid(proof("wrong")),"replay nonce")
 check(!valid(proof("c",105,nil)),"missing listener proof")
 check(!valid(proof(),106),"stale proof")
 check(!valid(proof("c",Double.infinity)),"nonfinite proof")
 var flow=FilterFlowRegistry<Int>();let id=UUID();check(flow.insert(1,id:id),"track flow");check(flow.withdraw().count==1 && flow.entries.isEmpty,"withdraw active flow")
 var nodes=[Int32:AncestryNode]()
 nodes[5]=AncestryNode(pid:5,parent:4,uid:501,startedBefore:10,startedAfter:10,officialSignature:false)
 nodes[4]=AncestryNode(pid:4,parent:1,uid:501,startedBefore:9,startedAfter:9,officialSignature:true)
 check(VerifiedAncestry.containsOfficialParent(of:5,uid:501,read:{nodes[$0]}),"verified child")
 nodes[4]=AncestryNode(pid:4,parent:1,uid:501,startedBefore:9,startedAfter:11,officialSignature:true)
 check(!VerifiedAncestry.containsOfficialParent(of:5,uid:501,read:{nodes[$0]}),"PID reuse refused")
 var sequence=PolicySequenceGate()
 check(sequence.accept(1),"first policy sequence")
 check(!sequence.accept(1),"replayed policy rejected")
 check(!sequence.accept(nil),"missing sequence rejected")
 check(sequence.accept(3),"new blocking sequence")
 check(!sequence.accept(2),"late allowance cannot override block")
 check(!GuardPresentation.isSafe(monitoring:true,routeMatched:false,probeFresh:true,active:true,blocking:false),"local revoke clears old green before provider ack")
 check(!GuardPresentation.isSafe(monitoring:true,routeMatched:true,probeFresh:false,active:true,blocking:false),"stale probe cannot remain green")
 check(GuardPresentation.isSafe(monitoring:true,routeMatched:true,probeFresh:true,active:true,blocking:false),"fresh confirmed path can be green")
 var alerts=SafetyAlertGate()
 check(!alerts.update(monitoring:false,safe:false),"manual hold emits no failure alert")
 check(alerts.update(monitoring:true,safe:false),"unsafe episode alerts")
 check(!alerts.update(monitoring:true,safe:false),"repeated unsafe polling does not flood")
 check(!alerts.update(monitoring:true,safe:true),"safe recovery rearms")
 check(alerts.update(monitoring:true,safe:false),"next unsafe episode alerts")
 print("GUARD_TEST_OK: \(count) offline checks; no real processes signalled or network changed")
}
