#!/usr/bin/env python3
"""Check that review exports reject stale/corrupt source observations."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

from export_review_packet import DEFAULT_OUTPUT, ROOT, make_packet, render, safe_text

REPORT = ROOT / "docs/validation/thesaurus-20261118/resume/native/native-pack-report.json"


class ReviewPacketTest(unittest.TestCase):
    def altered_report(self, mutate):
        data = json.loads(REPORT.read_text())
        mutate(data)
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "report.json"
            path.write_text(json.dumps(data))
            return make_packet(path, DEFAULT_OUTPUT)

    def test_current_source_records_remain_unreviewed(self):
        packet = make_packet(REPORT, DEFAULT_OUTPUT)
        self.assertEqual(len(packet["queries"]), 15)
        self.assertEqual(packet["review_status"], "not_reviewed")
        self.assertTrue(all(d["decision"] is None for d in packet["decisions"]))
        self.assertIsNone(packet["reviewer"])
        self.assertIn("he cashed a check at the bank", render(packet))
        self.assertIn("ot-10147", packet["source_records"])

    def test_source_text_cannot_create_markdown_blocks(self):
        self.assertEqual(safe_text("# headline\r\n---\r- item\n1. item <script>"),
                         "\\# headline / \\-\\-\\- / \\- item / 1\\. item &lt;script&gt;")

    def test_modified_term_is_rejected(self):
        def alter(data):
            data["queries"][0]["senses"][0]["terms"][0]["text"] = "invented term"
        with self.assertRaisesRegex(ValueError, "differs from current source"):
            self.altered_report(alter)

    def test_stale_pack_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "pack identity"):
            self.altered_report(lambda d: d["queries"][0].update(pack="old-pack:0000"))

    def test_failed_native_run_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "successful native"):
            self.altered_report(lambda d: d.update(status="failed"))

    def test_missing_or_repeated_query_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "complete ordered"):
            self.altered_report(lambda d: d["queries"].pop())
        with self.assertRaisesRegex(ValueError, "complete ordered"):
            self.altered_report(lambda d: d["queries"].append(copy.deepcopy(d["queries"][0])))


if __name__ == "__main__":
    unittest.main()
