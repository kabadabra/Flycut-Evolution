#!/usr/bin/env python3
"""Verify a decoded macOS Developer ID profile before it is embedded."""
import datetime
import hashlib
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print("Usage: verify-cloud-profile.py profile.provisionprofile [signed-app]", file=sys.stderr)
        return 2
    payload = subprocess.check_output(["security", "cms", "-D", "-i", sys.argv[1]])
    profile = plistlib.loads(payload)
    entitlements = profile.get("Entitlements", {})
    checks = {
        "team": "M2L9SL9WCS" in profile.get("TeamIdentifier", []),
        "bundle ID": entitlements.get("com.apple.application-identifier") == "M2L9SL9WCS.com.edynamics.flycut",
        # Developer ID profiles may authorize every iCloud service with "*".
        # The app signature below still claims only CloudKit.
        "CloudKit": bool({"CloudKit", "*"} & set(entitlements.get("com.apple.developer.icloud-services", []))),
        "iCloud container": "iCloud.com.edynamics.flycut" in entitlements.get("com.apple.developer.icloud-container-identifiers", []),
        "production iCloud": entitlements.get("com.apple.developer.icloud-container-environment") == "Production",
        "production notifications": entitlements.get("com.apple.developer.aps-environment") == "production",
        "all devices": profile.get("ProvisionsAllDevices") is True,
        "not expired": profile.get("ExpirationDate", datetime.datetime.min) > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
    }
    failures = [name for name, passed in checks.items() if not passed]
    if len(sys.argv) == 3:
        with tempfile.TemporaryDirectory(prefix="flycut-signature-") as directory:
            prefix = str(Path(directory) / "signer")
            subprocess.check_call(["codesign", "-d", f"--extract-certificates={prefix}", sys.argv[2]],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            signed_certificate = Path(prefix + "0").read_bytes()
        authorized = {hashlib.sha256(bytes(certificate)).digest()
                      for certificate in profile.get("DeveloperCertificates", [])}
        if hashlib.sha256(signed_certificate).digest() not in authorized:
            failures.append("signing certificate in profile")
    if failures:
        print("Provisioning profile does not authorize: " + ", ".join(failures), file=sys.stderr)
        return 1
    print("Verified Flycut Evolution CloudKit Developer ID profile")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
