import os
import subprocess
import sys
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "drivers" / "python"))

from rochedb import RocheClient, RocheId  # noqa: E402


class RochePythonDriverTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.peers = os.environ.get(
            "ROCHE_TEST_PEERS", "127.0.0.1:17831,127.0.0.1:17832"
        )
        cls.processes = []
        roched = ROOT / "src" / "roched"
        for i in range(2):
            cls.processes.append(
                subprocess.Popen(
                    [
                        str(roched),
                        f"--id={i}",
                        f"--peers={cls.peers}",
                        "--slow-tick=1000",
                    ],
                    cwd=str(ROOT),
                )
            )

        cls.client = RocheClient.connect(cls.peers, timeout=1.0)
        deadline = time.time() + 5.0
        while time.time() < deadline:
            try:
                cls.client.health(0)
                cls.client.health(1)
                return
            except Exception:
                time.sleep(0.1)
        raise RuntimeError("roched test cluster did not start")

    @classmethod
    def tearDownClass(cls):
        cls.client.close()
        for proc in cls.processes:
            proc.terminate()
        for proc in cls.processes:
            try:
                proc.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2.0)

    def test_put_get_query_roundtrip(self):
        doc_id = self.client.put(
            "japan/tokyo",
            b'{"title":"Shinjuku","country":"JP"}',
            vector=[1.0, 0.0],
        )
        self.assertIsInstance(doc_id, RocheId)
        self.assertEqual(
            self.client.get(doc_id), b'{"title":"Shinjuku","country":"JP"}'
        )
        self.assertEqual(self.client.query(doc_id, "{ title }"), b'{"title":"Shinjuku"}')

    def test_id_string_roundtrip(self):
        doc_id = self.client.put("tenant/acme/orders", "order-1")
        self.assertEqual(RocheId.parse(str(doc_id)), doc_id)
        self.assertEqual(self.client.get(doc_id), b"order-1")


if __name__ == "__main__":
    unittest.main()
