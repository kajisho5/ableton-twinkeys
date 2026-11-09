import json
import unittest

from TwinKeysBridge.protocol import (format_beat, color_hex, pack_items,
                                     contiguous_runs, clean_name, encode)
from TwinKeysBridge.constants import MAX_DATAGRAM_BYTES, MAX_NAME_LENGTH


class BeatFormatTest(unittest.TestCase):

    def test_start_is_1_1_1(self):
        self.assertEqual(format_beat(0.0, 4, 4), "1.1.1")

    def test_four_four(self):
        # bar 17 starts at beat 64; +2 quarters +1 sixteenth
        self.assertEqual(format_beat(64 + 2 + 0.25, 4, 4), "17.3.2")
        self.assertEqual(format_beat(3.99, 4, 4), "1.4.4")
        self.assertEqual(format_beat(4.0, 4, 4), "2.1.1")

    def test_three_four(self):
        self.assertEqual(format_beat(3.0, 3, 4), "2.1.1")
        self.assertEqual(format_beat(5.5, 3, 4), "2.3.3")

    def test_six_eight(self):
        # 6/8: beat = eighth note (0.5 quarter), bar = 3 quarters
        self.assertEqual(format_beat(3.0, 6, 8), "2.1.1")
        self.assertEqual(format_beat(3.75, 6, 8), "2.2.2")

    def test_bad_input_is_safe(self):
        self.assertEqual(format_beat(float("nan"), 4, 4), "1.1.1")
        self.assertEqual(format_beat(-5, 4, 4), "1.1.1")
        self.assertEqual(format_beat(4.0, 0, 0), "2.1.1")
        self.assertEqual(format_beat("x", None, None), "1.1.1")


class HelpersTest(unittest.TestCase):

    def test_color_hex(self):
        self.assertEqual(color_hex(0xFF8000), "#FF8000")
        self.assertEqual(color_hex(0), "#000000")
        self.assertIsNone(color_hex(None))
        self.assertIsNone(color_hex(-1))

    def test_runs(self):
        self.assertEqual(contiguous_runs([8, 1, 2, 3, 7]), [[1, 2, 3], [7, 8]])
        self.assertEqual(contiguous_runs([]), [])

    def test_clean_name(self):
        self.assertEqual(clean_name(None), "")
        self.assertEqual(len(clean_name("x" * 1000)), MAX_NAME_LENGTH)

    def test_nan_rejected_by_encoder(self):
        with self.assertRaises(ValueError):
            encode({"x": float("nan")})


class PackTest(unittest.TestCase):

    def test_empty_gives_one_chunk_with_extra(self):
        chunks = pack_items({"type": "tracks"}, [], start_of=lambda i: i,
                            first_extra={"master": {"volume": 1}})
        self.assertEqual(len(chunks), 1)
        msg = json.loads(chunks[0])
        self.assertEqual(msg, {"type": "tracks", "start": 0,
                               "master": {"volume": 1}, "items": []})

    def test_split_under_limit_and_lossless(self):
        items = [{"index": i, "name": "n" * 50} for i in range(500)]
        chunks = pack_items({"type": "scenes"}, items,
                            start_of=lambda it: it["index"],
                            first_extra={"x": 1}, limit=2000)
        self.assertGreater(len(chunks), 1)
        got = []
        for k, c in enumerate(chunks):
            self.assertLess(len(c), 2000)
            m = json.loads(c.decode("utf-8"))
            self.assertEqual(m["start"], m["items"][0]["index"])
            self.assertEqual("x" in m, k == 0)
            got.extend(m["items"])
        self.assertEqual(got, items)

    def test_unicode_counted_in_bytes(self):
        items = [{"name": "音" * 100} for _ in range(100)]  # 3 bytes each
        for c in pack_items({"type": "t"}, items, limit=5000):
            self.assertLess(len(c), 5000)
            json.loads(c.decode("utf-8"))

    def test_default_limit(self):
        items = [{"name": "x" * 150} for _ in range(2000)]
        for c in pack_items({"type": "t"}, items):
            self.assertLess(len(c), MAX_DATAGRAM_BYTES)


if __name__ == "__main__":
    unittest.main()
