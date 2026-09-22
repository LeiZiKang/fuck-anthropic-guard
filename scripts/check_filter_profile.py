#!/usr/bin/env python3
"""Validate local Developer ID profiles without printing certificates/account data."""
import argparse
import datetime
from pathlib import Path
import plistlib
import subprocess


def validate_metadata(profile, bundle_id):
    entitlements = profile.get("Entitlements", {})
    identifier = entitlements.get("com.apple.application-identifier", entitlements.get("application-identifier"))
    if identifier != "Y355LMZA6C." + bundle_id:
        raise ValueError("Profile application identifier does not match the requested component")
    if "Y355LMZA6C" not in profile.get("TeamIdentifier", []):
        raise ValueError("Unexpected profile team")
    if profile.get("ProvisionsAllDevices") is not True or profile.get("ProvisionedDevices"):
        raise ValueError("A Developer ID distribution profile is required; development/device-bound profiles are rejected")
    if entitlements.get("get-task-allow") or entitlements.get("com.apple.security.get-task-allow"):
        raise ValueError("Debuggable profiles are not valid release profiles")
    if "content-filter-provider-systemextension" not in entitlements.get("com.apple.developer.networking.networkextension", []):
        raise ValueError("Profile does not grant content-filter-provider-systemextension")
    groups = entitlements.get("com.apple.security.application-groups")
    if groups is not None and not any(group in groups for group in ["Y355LMZA6C.*", "Y355LMZA6C.com.leizikang.claude-connection-watcher"]):
        raise ValueError("Profile app-group authorization does not cover the Mach service group")
    expires = profile.get("ExpirationDate")
    if not isinstance(expires, datetime.datetime) or expires.replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc):
        raise ValueError("Provisioning profile is expired or lacks an expiration date")
    if bundle_id == "com.leizikang.claude-connection-watcher" and entitlements.get("com.apple.developer.system-extension.install") is not True:
        raise ValueError("Host profile lacks system-extension.install")


def check(path, bundle_id):
    raw = subprocess.check_output(["/usr/bin/security", "cms", "-D", "-i", str(path)], stderr=subprocess.PIPE)
    validate_metadata(plistlib.loads(raw), bundle_id)
    print("Profile metadata validated for", bundle_id)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("profile", type=Path)
    parser.add_argument("bundle_id")
    args = parser.parse_args()
    check(args.profile, args.bundle_id)
