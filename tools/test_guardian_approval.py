import base64
import json
from pathlib import Path
import tempfile
import unittest

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from cryptography.exceptions import InvalidSignature
from guardian_approval import initialize, issue, load_key


def decode(value):
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


class GuardianApprovalTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "operator.pem"
        public = initialize(self.path)
        self.public = Ed25519PublicKey.from_public_bytes(base64.b64decode(public))
        self.key = load_key(self.path)

    def token(self, **changes):
        args = dict(request_id="a" * 64, notice_version="test-notice-v1", days=30,
                    confirmations=[True] * 4, now=1793628000)
        args.update(changes)
        return issue(self.key, **args)

    def test_signature_covers_exact_request_notice_and_expiry(self):
        payload, signature = self.token().split(".")
        raw = decode(payload)
        self.public.verify(decode(signature), raw)
        data = json.loads(raw)
        self.assertEqual(data, {"v": 1, "requestId": "a" * 64,
                               "noticeVersion": "test-notice-v1", "issuedAt": 1793628000,
                               "expiresAt": 1793628000 + 30 * 86400})
        with self.assertRaises(InvalidSignature):
            self.public.verify(decode(signature), raw.replace(b"test-notice-v1", b"test-notice-v2"))

    def test_missing_verification_rejected(self):
        for missing in range(4):
            confirmations = [True] * 4
            confirmations[missing] = False
            with self.assertRaises(ValueError):
                self.token(confirmations=confirmations)

    def test_invalid_request_and_lifetime_rejected(self):
        for request in ["", "123456", "person@example.com", "a" * 63]:
            with self.assertRaises(ValueError):
                self.token(request_id=request)
        for days in [0, -1, 91]:
            with self.assertRaises(ValueError):
                self.token(days=days)

    def test_existing_key_cannot_be_overwritten(self):
        with self.assertRaises(FileExistsError):
            initialize(self.path)
        self.assertEqual(load_key(self.path).public_key(), self.key.public_key())

    def test_publicly_readable_private_key_is_rejected(self):
        self.path.chmod(0o644)
        with self.assertRaises(ValueError):
            load_key(self.path)


if __name__ == "__main__":
    unittest.main()
