import Foundation
func runGuardTests() {
 var count=0
 func check(_ value:Bool,_ name:String) { guard value else { fatalError("TEST FAILED: "+name) };count+=1 }
 var journal = GuardConnectionJournal()
 for i in 1...100 { journal.append(pid: 12, client: "Claude", destination: "127.0.0.1:6154", transport: "TCP", allowed: i % 2 == 0, reason: i % 2 == 0 ? "verified-route" : "permission-unavailable", at: 1000) }
 check(journal.events.count == 80 && journal.events.first?.id == 21, "bounded journal evicts oldest")
 check(journal.allowed == 50 && journal.denied == 50, "decision totals survive ring eviction")
 check(journal.events.last?.decision == "allow", "latest decision retained")
 journal.append(pid: 12, client: String(repeating: "x", count: 200) + "\n", destination: "a\nb", transport: "invalid", allowed: false, reason: "wrong-endpoint", at: 1001)
 check(journal.events.last!.client.count == 160 && journal.events.last!.destination == "ab", "metadata bounded and controls stripped")
 check(journal.events.last!.valid && journal.events.last!.transport == "Other", "journal wire format validates")
 let before = journal.events.count; journal.append(pid: 1, client: "x", destination: "x", transport: "TCP", allowed: true, reason: "invalid", at: 1002)
 check(journal.events.count == before && journal.allowed == 50, "invalid reason cannot invent an allowed event")
 let encodedJournal = try! JSONEncoder().encode(journal.events)
 check((try! JSONDecoder().decode([GuardConnectionEvent].self, from: encodedJournal)) == journal.events, "event IPC round trip")
 check(encodedJournal.count < 120000, "bounded journal fits status IPC budget")
 check(GuardConnectionJournal.blockCause(shouldBlock: false, validUntil: 10, now: 11, last: "network-change") == "lease-expired", "expired lease cause is distinct from previous revoke")
 check(GuardConnectionJournal.blockCause(shouldBlock: true, validUntil: nil, now: 11, last: "manual-block") == "manual-block", "manual block cause preserved")
 check(GuardConnectionJournal.blockCause(shouldBlock: true, validUntil: nil, now: 11, last: "untrusted payload") == "host-blocked", "diagnostic cause cannot carry arbitrary payload")
 var sample = GuardConnectionJournal()
 sample.append(pid: 7, client: "com.apple.python3", destination: "127.0.0.1:6154", transport: "TCP", allowed: true, reason: "verified-route", at: 100)
 sample.append(pid: 8, client: "com.anthropic.claude-code", destination: "127.0.0.1:8770", transport: "TCP", allowed: false, reason: "permission-withdrawn", cause: "manual-block", at: 101)
 check(GuardEventQuery.apply(sample.events, filter: 1, query: "", key: "time", ascending: false).map(\.pid) == [7], "allow filter excludes denied")
 check(GuardEventQuery.apply(sample.events, filter: 0, query: "PYTHON", key: "time", ascending: false).map(\.pid) == [7], "case-insensitive identity search")
 check(GuardEventQuery.apply(sample.events, filter: 0, query: "8770", key: "time", ascending: false).map(\.pid) == [8], "endpoint search")
 check(GuardEventQuery.apply(sample.events, filter: 0, query: "", key: "time", ascending: true).map(\.pid) == [7,8], "time sort ascending")
 check(GuardEventQuery.apply(sample.events, filter: 0, query: "", key: "time", ascending: false).map(\.pid) == [8,7], "time sort descending")
 check(GuardEventQuery.apply(sample.events, filter: 2, query: "python", key: "time", ascending: false).isEmpty, "search and decision filter compose")
 let disabledUI = GuardUISnapshot(state: .disabled, configured: false)
 let readyUI = GuardUISnapshot(state: .verified, configured: true)
 let unknownUI = GuardUISnapshot(state: .checking, configured: nil)
 check(disabledUI.canEdit && disabledUI.canEnable, "disabled known configuration offers setup")
 check(!readyUI.canEdit && !readyUI.canEnable, "ready configuration is read-only without redundant enable")
 check(!unknownUI.canEdit && !unknownUI.canEnable, "unknown configuration cannot be edited or activated blindly")
 check(!GuardUISnapshot(state: .disabled, configured: false, pending: true).canEdit, "pending operation disables edits")
 let caused = try! JSONDecoder().decode([GuardConnectionEvent].self, from: JSONEncoder().encode(sample.events))
 check(caused.last?.cause == "manual-block", "event cause roundtrips")
 var diagnosticPolicy = FilterDecisionState()
 diagnosticPolicy.accept(FilterPolicyUpdate(block: true, blockReason: "untrusted string"), at: 100)
 check(diagnosticPolicy.blocking(at: 100), "diagnostic strings do not authorize a connection")
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
 check(GuardUIState.resolved(configured:false,active:true,blocking:false,safe:true) == .disabled,"disabled config cannot display verified")
 check(GuardUIState.resolved(configured:true,active:false,blocking:false,safe:true) == .checking,"unconfirmed enforcement cannot display verified")
 check(GuardUIState.resolved(configured:true,active:true,blocking:true,safe:true) == .blocked,"blocking state wins over stale safe flag")
 check(GuardUIState.resolved(configured:true,active:true,blocking:false,safe:false) == .checking,"unverified route cannot display ready")
 check(GuardUIState.resolved(configured:true,active:true,blocking:false,safe:true) == .verified,"confirmed fresh route displays ready")
 check(GuardUIState.resolved(configured:nil,active:false,blocking:false,safe:false) == .checking,"startup unknown remains unconfirmed")
 let originalLanguage=L10n.language
 check(AppLanguage.resolve(saved:nil,preferred:["zh-Hant"]) == .chinese,"Chinese system preference")
 check(AppLanguage.resolve(saved:nil,preferred:["fr"]) == .english,"unsupported language falls back to English")
 check(AppLanguage.resolve(saved:"en",preferred:["zh-Hans"]) == .english,"saved choice wins")
 for item in GuardString.allCases {
  check(!item.message.chinese.isEmpty && !item.message.english.isEmpty,"both variants exist")
  check(!item.message.english.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) },"English copy contains no untranslated Chinese")
 }
 L10n.language = .chinese
 let preview=PreviewModel();preview.lock();let terminate=preview.prepareTermination()
 L10n.language = .english;preview.languageDidChange()
 check(preview.state == GuardString.sampleBlocked.message.english,"language switch retains blocked preview state")
 check(preview.rows.allSatisfy { $0.name.contains("sample") },"sample process labels switch")
 terminate();L10n.language = .chinese;preview.languageDidChange()
 check(preview.rows.isEmpty,"language switch does not restore exited sample processes")
 check(preview.state == GuardString.sampleBlocked.message.chinese,"switch back translates retained state")
 L10n.language = originalLanguage
 #if !CCW_PREVIEW
 for app in ["fuck-anthropic guard.app", "fuck-anthropic guard Preview.app"] {
  let guardIdentity=ProcessIdentity(pid:999999,effectiveUID:501,startSeconds:1,startMicroseconds:0,executablePath:"/Applications/"+app+"/Contents/MacOS/example")
  check(ProcessInventory.isProtected(guardIdentity),"renamed guard instances never become quit targets")
 }
 #endif
 print("GUARD_TEST_OK: \(count) offline checks; no real processes signalled or network changed")
}
