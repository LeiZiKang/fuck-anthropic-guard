#!/usr/bin/env python3
"""Prepare version-bound XPC metadata in build outputs, never source plists."""
import argparse
import copy
import plistlib
import re
from pathlib import Path

PREFIX = "Y355LMZA6C.com.leizikang.claude-connection-watcher.filter"
HOST_ID = "com.leizikang.claude-connection-watcher"
PROVIDER_ID = HOST_ID + ".filter"
HOST_KEY = "CCWFilterMachServiceName"


def service_name(version):
    if not isinstance(version, str) or re.fullmatch(r"[1-9][0-9]{0,3}(\.(0|[1-9][0-9]?)){0,2}", version) is None:
        raise ValueError("invalid-or-missing-bundle-version")
    return PREFIX + ".v" + version


def prepare(host, provider=None):
    from check_system_extension_metadata import check, check_host

    if not isinstance(host, dict) or host.get("CFBundleIdentifier") != HOST_ID:
        raise ValueError("incorrect-host-identifier")
    name = service_name(host.get("CFBundleVersion"))
    host = copy.deepcopy(host)
    host[HOST_KEY] = name
    errors = check_host(host)
    if errors:
        raise ValueError(",".join(errors))
    if provider is None:
        return host, None
    # Templates are validated before the version and service name are generated.
    errors = check(provider, template=True)
    if errors:
        raise ValueError(",".join(errors))
    provider = copy.deepcopy(provider)
    provider["CFBundleVersion"] = host["CFBundleVersion"]
    provider["CFBundleShortVersionString"] = host["CFBundleShortVersionString"]
    provider["NetworkExtension"]["NEMachServiceName"] = name
    errors = check(provider, host_metadata=host)
    if errors:
        raise ValueError(",".join(errors))
    return host, provider


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True, type=Path)
    parser.add_argument("--host-output", required=True, type=Path)
    parser.add_argument("--provider-template", type=Path)
    parser.add_argument("--provider-output", type=Path)
    args = parser.parse_args()
    if bool(args.provider_template) != bool(args.provider_output):
        parser.error("provider-template and provider-output must be supplied together")
    try:
        host, provider = prepare(plistlib.loads(args.host.read_bytes()),
                                 plistlib.loads(args.provider_template.read_bytes()) if args.provider_template else None)
        args.host_output.write_bytes(plistlib.dumps(host, sort_keys=False))
        if provider is not None:
            args.provider_output.write_bytes(plistlib.dumps(provider, sort_keys=False))
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise SystemExit("Mach service metadata preparation failed: " + str(error))
    print("Prepared versioned Mach service:", host[HOST_KEY])
