import hashlib
import tempfile
import unittest
from pathlib import Path

from release import PACKAGES, verify


class ReleaseGateTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.incoming = self.root / 'incoming'
        self.incoming.mkdir()
        for name in PACKAGES:
            directory = self.incoming / ('tested-' + name)
            directory.mkdir()
            payload = name.encode('ascii')
            (directory / name).write_bytes(payload)
            checksum = hashlib.sha256(payload).hexdigest()
            marker = '*' if name.endswith('.exe') else ' '
            (directory / (name + '.sha256')).write_text(f'{checksum} {marker}{name}\n', 'ascii')

    def test_verified_packages_keep_their_original_bytes(self):
        output = self.root / 'dist'
        verify(self.incoming, output)
        for name in PACKAGES:
            self.assertEqual((output / name).read_bytes(), name.encode('ascii'))
        expected = ''.join(f'{hashlib.sha256(name.encode("ascii")).hexdigest()}  {name}\n' for name in PACKAGES)
        self.assertEqual((output / 'SHA256SUMS').read_bytes(), expected.encode('ascii'))

    def test_tampering_blocks_publication(self):
        name = PACKAGES[0]
        (self.incoming / ('tested-' + name) / name).write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'Checksum mismatch'):
            verify(self.incoming, self.root / 'dist')

    def test_missing_platform_blocks_publication(self):
        (self.incoming / ('tested-' + PACKAGES[0])).rename(self.root / 'absent')
        with self.assertRaisesRegex(ValueError, 'Unexpected set'):
            verify(self.incoming, self.root / 'dist')
