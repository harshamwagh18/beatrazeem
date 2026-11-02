#!/usr/bin/env python3
"""Operator-issued offline approval, after independent guardian verification.

This tool signs the operator's decision. It does not verify identity, age,
parenthood, guardianship or consent. Never distribute its private signing key.
Requires the Python cryptography package.
"""

import argparse
import base64
import json
import os
from pathlib import Path
import re
import stat
import sys
import time

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


def encode(data):
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def initialize(path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    key = Ed25519PrivateKey.generate()
    private = key.private_bytes(serialization.Encoding.PEM,
                                serialization.PrivateFormat.PKCS8,
                                serialization.NoEncryption())
    # Exclusive creation prevents an accidental rotation of deployed trust keys.
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(private)
    public = key.public_key().public_bytes(serialization.Encoding.Raw,
                                          serialization.PublicFormat.Raw)
    return base64.b64encode(public).decode("ascii")


def load_key(path):
    path = Path(path)
    if os.name == "posix" and stat.S_IMODE(path.stat().st_mode) & 0o077:
        raise ValueError("The private key must be accessible only to its owner (chmod 600).")
    key = serialization.load_pem_private_key(path.read_bytes(), password=None)
    if not isinstance(key, Ed25519PrivateKey):
        raise ValueError("An Ed25519 private key is required.")
    return key


def issue(key, request_id, notice_version, days, confirmations, now=None):
    valid_id = re.fullmatch(r"[0-9a-f]{64}|[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}", request_id)
    if not valid_id:
        raise ValueError("Request ID must be the 64-character hexadecimal code or UUID displayed by the app.")
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,80}", notice_version):
        raise ValueError("Notice version must exactly identify the notice verified with the guardian.")
    if not 1 <= days <= 90:
        raise ValueError("Approval must last between 1 and 90 days.")
    if len(confirmations) != 4 or not all(value is True for value in confirmations):
        raise ValueError("Identity, adulthood, authority and affirmative informed consent must all be verified first.")
    issued_at = int(time.time() if now is None else now)
    if issued_at <= 0:
        raise ValueError("A valid current time is required.")
    payload = {"v": 1, "requestId": request_id, "noticeVersion": notice_version,
               "issuedAt": issued_at, "expiresAt": issued_at + days * 86400}
    raw = json.dumps(payload, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
    return encode(raw) + "." + encode(key.sign(raw))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    setup = commands.add_parser("init", help="Create an operator key outside the source repository.")
    setup.add_argument("--private-key", required=True, type=Path)
    approve = commands.add_parser("issue", help="Sign after completing the documented verification procedure.")
    approve.add_argument("--private-key", required=True, type=Path)
    approve.add_argument("--request-id", required=True)
    approve.add_argument("--notice-version", required=True)
    approve.add_argument("--days", type=int, default=30)
    approve.add_argument("--verified-identity", action="store_true")
    approve.add_argument("--verified-adulthood", action="store_true")
    approve.add_argument("--verified-authority", action="store_true")
    approve.add_argument("--recorded-consent", action="store_true")
    args = parser.parse_args()
    try:
        if args.command == "init":
            print(initialize(args.private_key))
        else:
            print(issue(load_key(args.private_key), args.request_id, args.notice_version, args.days,
                        [args.verified_identity, args.verified_adulthood,
                         args.verified_authority, args.recorded_consent]))
    except (OSError, ValueError, TypeError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
