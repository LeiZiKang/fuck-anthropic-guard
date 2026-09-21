#!/usr/bin/env python3
"""Check metadata required before macOS can load the content filter."""
import json
import plistlib
import argparse
from pathlib import Path
from mach_service_metadata import HOST_ID, PROVIDER_ID, HOST_KEY, service_name


def check_host(metadata):
    if not isinstance(metadata, dict):
        return ["invalid-host-metadata"]
    errors = []
    if metadata.get("CFBundleIdentifier") != HOST_ID:
        errors.append("incorrect-host-identifier")
    try:
        expected = service_name(metadata.get("CFBundleVersion"))
    except ValueError:
        errors.append("invalid-or-missing-host-bundle-version")
    else:
        if metadata.get(HOST_KEY) != expected:
            errors.append("missing-or-mismatched-host-mach-service")
    return errors


def check(metadata, host_metadata=None, template=False):
    if not isinstance(metadata, dict):
        return ["invalid-provider-metadata"]
    errors = []
    description = metadata.get("NSSystemExtensionUsageDescription")
    if not isinstance(description, str) or not description.strip():
        errors.append("missing-system-extension-usage-description")
    if metadata.get("CFBundlePackageType") != "SYSX":
        errors.append("not-system-extension-package")
    network = metadata.get("NetworkExtension")
    classes = network.get("NEProviderClasses") if isinstance(network, dict) else None
    provider = classes.get("com.apple.networkextension.filter-data") if isinstance(classes, dict) else None
    if not isinstance(provider, str) or not provider.strip():
        errors.append("missing-content-filter-provider-class")
    if metadata.get("CFBundleIdentifier") != PROVIDER_ID:
        errors.append("incorrect-provider-identifier")
    try:
        expected = service_name(metadata.get("CFBundleVersion"))
    except ValueError:
        errors.append("invalid-or-missing-provider-bundle-version")
    else:
        if not template and (not isinstance(network, dict) or network.get("NEMachServiceName") != expected):
            errors.append("missing-or-mismatched-provider-mach-service")
    if host_metadata is not None:
        errors.extend(check_host(host_metadata))
        if not isinstance(host_metadata, dict) or metadata.get("CFBundleVersion") != host_metadata.get("CFBundleVersion"):
            errors.append("host-provider-version-mismatch")
        if not isinstance(network, dict) or not isinstance(host_metadata, dict) or network.get("NEMachServiceName") != host_metadata.get(HOST_KEY):
            errors.append("host-provider-mach-service-mismatch")
    return errors


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("metadata", type=Path)
    parser.add_argument("--host", type=Path)
    parser.add_argument("--host-only", action="store_true")
    parser.add_argument("--template", action="store_true")
    args = parser.parse_args()
    if args.host_only and (args.host or args.template):
        parser.error("host-only cannot be combined with host or template")
    try:
        metadata = plistlib.loads(args.metadata.read_bytes())
        errors = check_host(metadata) if args.host_only else check(metadata,
            host_metadata=plistlib.loads(args.host.read_bytes()) if args.host else None, template=args.template)
    except (OSError, ValueError, IndexError, AttributeError):
        errors = ["invalid-or-unreadable-metadata"]
    print(json.dumps({"metadata_valid": not errors, "errors": errors}))
    raise SystemExit(2 if errors else 0)
