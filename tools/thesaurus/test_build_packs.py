"""Meaningful parser/normalization regressions; no network or generated fixtures."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("build_packs", Path(__file__).with_name("build_packs.py"))
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class CompilerTests(unittest.TestCase):
    def test_sql_escapes_are_data_and_never_executable(self):
        self.assertEqual(builder.sql_values(r"(1,'x\'y','back\\slash',NULL,0x01,'a\nb');"),
                         [1, "x'y", "back\\slash", None, 1, "a\nb"])
        self.assertEqual(builder.sql_values("('); DROP TABLE term;--',2),"),
                         ["); DROP TABLE term;--", 2])
        self.assertEqual(builder.sql_values("('a\u2028b',3);"), ["a\u2028b", 3])

    def test_sql_rejects_malformed_or_unknown_values(self):
        for value in ["(1,'unclosed);", "(1,);", "(CURRENT_TIMESTAMP);", "(1); garbage", "(1,0xzz);", "(1"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                builder.sql_values(value)

    def test_german_words_are_not_folded(self):
        self.assertNotEqual(builder.normalize("Maße"), builder.normalize("Masse"))
        self.assertNotEqual(builder.normalize("Häuser"), builder.normalize("Hauser"))
        self.assertEqual(builder.normalize(" ICE\u00a0CREAM\u00ad "), "ice cream")

    def test_utf8_shards_have_stable_cross_runtime_vectors(self):
        self.assertEqual([builder.shard(x) for x in ["bank", "häuser", "maße", "ice cream", "😀"]],
                         ["97", "eb", "30", "1e", "08"])

    def test_literal_terms_reject_document_controls(self):
        self.assertTrue(builder.safe_term("sich freuen (über)"))
        self.assertFalse(builder.safe_term(" bad"))
        self.assertFalse(builder.safe_term("bad\nword"))


if __name__ == "__main__":
    unittest.main()
