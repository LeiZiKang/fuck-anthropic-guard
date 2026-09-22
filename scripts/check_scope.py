#!/usr/bin/env python3
"""Structural release checks, not a live firewall acceptance test."""
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
build=(root/'scripts/build.sh').read_text()
for forbidden in ['build-relay.sh','FixedRelayHostSession','CredentialCleaner','IPv6SettingsBackend','/Relay/']:
 assert forbidden not in build,forbidden
main=(root/'Guard/App/main.swift').read_text()
assert '#if !CCW_PREVIEW' in main and 'PreviewModel()' in main
assert 'SCPreferencesCommitChanges' not in main and 'AuthorizationCreate' not in main
for p in (root/'Guard').rglob('*.swift'):
 s=p.read_text()
 for forbidden in ['privateKeyPath','/usr/bin/ssh','NWListener','socket(AF_','listen(','bind(']:
  assert forbidden not in s,(str(p),forbidden)
assert 'self.sequenceGate.accept(update.sequence)' in (root/'NetworkFilter/Sources/main.swift').read_text()
print('SCOPE_CHECK_OK: no relay/key reader/IPv6 writer in guard build; preview isolated; sequence guard present')
