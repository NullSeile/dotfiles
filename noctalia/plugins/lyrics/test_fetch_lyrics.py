#!/usr/bin/env python3

import contextlib
import io
import json
import os
import tempfile
import unittest
from unittest import mock

import fetch_lyrics


class ParseLrcTest(unittest.TestCase):
    def test_parses_timestamps_and_sorts(self):
        lines = fetch_lyrics.parse_lrc("[00:02.50]Second\n[00:01]First\n[00:03.25]Third")
        self.assertEqual([item["time"] for item in lines], [1000, 2500, 3250])
        self.assertEqual([item["text"] for item in lines], ["First", "Second", "Third"])
        self.assertEqual(lines[0]["chars"], [])

    def test_multiple_tags_share_a_line(self):
        lines = fetch_lyrics.parse_lrc("[00:01.00][00:05.00]Chorus")
        self.assertEqual([item["time"] for item in lines], [1000, 5000])
        self.assertEqual([item["text"] for item in lines], ["Chorus", "Chorus"])

    def test_offset_shifts_all_lines(self):
        lines = fetch_lyrics.parse_lrc("[offset:+500]\n[00:01.00]Line")
        self.assertEqual(lines[0]["time"], 1500)

    def test_skips_metadata_and_credit_lines(self):
        lines = fetch_lyrics.parse_lrc(
            "[ti:Title]\n[ar:Artist]\n[by:Someone]\n"
            "[00:01.00]作词：Someone\n[00:02.00]Real line"
        )
        self.assertEqual(len(lines), 1)
        self.assertEqual(lines[0]["text"], "Real line")

    def test_enhanced_word_tags_become_char_times(self):
        lines = fetch_lyrics.parse_lrc("[00:01.000]<00:01.000>He<00:01.500>y")
        self.assertEqual(lines[0]["text"], "Hey")
        self.assertEqual(lines[0]["chars"], [1000, 1000, 1500])

    def test_accepts_comma_decimal_timestamps(self):
        lines = fetch_lyrics.parse_lrc("[00:01,25]Line")
        self.assertEqual(lines[0]["time"], 1250)

    def test_enhanced_chars_follow_offset(self):
        lines = fetch_lyrics.parse_lrc("[offset:-200]\n[00:02.000]<00:02.000>Ab")
        self.assertEqual(lines[0]["chars"], [1800, 1800])

    def test_pairs_musixmatch_translation_lines(self):
        lines = fetch_lyrics.parse_lrc("[00:01.00]Original\n(Translated)\n[00:02.00]Next")
        self.assertEqual(len(lines), 2)
        self.assertEqual(lines[0]["translation"], "Translated")
        self.assertEqual(lines[1]["translation"], "")

    def test_krc_prefix_words(self):
        lines = fetch_lyrics.parse_lrc("[1000,800]<0,400>He<400,400>y")
        self.assertEqual(lines[0]["text"], "Hey")
        self.assertEqual(lines[0]["time"], 1000)
        self.assertEqual(lines[0]["duration"], 800)
        self.assertEqual(lines[0]["chars"], [1000, 1200, 1400])

    def test_plain_text_when_nothing_timed(self):
        lines = fetch_lyrics.parse_text("First plain\nSecond plain\nlyricist: X", True)
        self.assertTrue(all(item["time"] == -1 for item in lines))
        self.assertEqual([item["text"] for item in lines], ["First plain", "Second plain"])


class MatchTest(unittest.TestCase):
    def test_pick_best_requires_a_title_match(self):
        items = [
            {"name": "Other Song", "artist": "Artist"},
            {"name": "Song", "artist": "Artist"},
        ]
        best = fetch_lyrics.pick_best(
            items, {"title": "Song", "artist": "Artist"},
            lambda item: item["name"], lambda item: item["artist"],
        )
        self.assertEqual(best["name"], "Song")

    def test_pick_best_rejects_unrelated_titles(self):
        best = fetch_lyrics.pick_best(
            [{"name": "Totally Different", "artist": "Artist"}],
            {"title": "Song", "artist": "Artist"},
            lambda item: item["name"], lambda item: item["artist"],
        )
        self.assertIsNone(best)


class RichsyncParseTest(unittest.TestCase):
    def test_keeps_word_level_char_times(self):
        payload = json.dumps([{
            "ts": 1.0,
            "te": 3.0,
            "l": [
                {"c": "You", "o": 0.0},
                {"c": " ", "o": 0.3},
                {"c": "got", "o": 0.6},
            ],
        }])
        lines = fetch_lyrics._parse_richsync(payload)
        self.assertEqual(len(lines), 1)
        self.assertEqual(lines[0]["text"], "You got")
        self.assertEqual(lines[0]["time"], 1000)
        self.assertEqual(lines[0]["duration"], 2000)
        # Word plateaus are preserved; the widget interpolates them.
        self.assertEqual(lines[0]["chars"], [1000, 1000, 1000, 1300, 1600, 1600, 1600])


class LrclibRankTest(unittest.TestCase):
    def setUp(self):
        self.track = {
            "title": "Can't Stop",
            "artist": "Red Hot Chili Peppers",
            "album": "By the Way",
            "duration": 269,
        }
        self.plain = {
            "id": 10, "trackName": "Can't Stop", "artistName": "Red Hot Chili Peppers",
            "albumName": "By the Way", "duration": 269,
            "plainLyrics": "Plain line", "syncedLyrics": "",
        }
        self.synced = {
            "id": 20, "trackName": "Can't Stop", "artistName": "Red Hot Chili Peppers",
            "albumName": "By the Way", "duration": 269,
            "plainLyrics": "Synced line", "syncedLyrics": "[00:01.00]Synced line",
        }

    def test_prefers_synced_when_duration_matches(self):
        ranked = fetch_lyrics.rank_lrclib([self.plain, self.synced], self.track)
        self.assertEqual([item["id"] for item in ranked], [20, 10])

    def test_rejects_wrong_artist_even_when_synced(self):
        wrong = {
            "id": 30, "trackName": "Can't Stop", "artistName": "Unrelated Artist",
            "duration": 269, "syncedLyrics": "[00:01.00]Wrong",
        }
        ranked = fetch_lyrics.rank_lrclib([wrong, self.plain], self.track)
        self.assertEqual([item["id"] for item in ranked], [10])

    def test_prefers_duration_before_sync_status(self):
        far = dict(self.synced)
        far["id"] = 30
        far["duration"] = 400
        ranked = fetch_lyrics.rank_lrclib([far, self.plain], self.track)
        self.assertEqual([item["id"] for item in ranked], [10, 30])


class FetchTest(unittest.TestCase):
    def test_requires_a_track_title(self):
        result = fetch_lyrics.fetch({"artist": "Artist"}, {})
        self.assertEqual(result["type"], "none")

    @mock.patch("fetch_lyrics.request_json")
    def test_lrclib_returns_parsed_lines(self, request_json):
        request_json.return_value = [{
            "id": 1, "trackName": "Song", "artistName": "Artist",
            "duration": 200, "syncedLyrics": "[00:01.00]Hello",
        }]
        result = fetch_lyrics.fetch(
            {"title": "Song", "artist": "Artist", "duration": 200},
            {"providers": ["lrclib"]},
        )
        self.assertEqual(result["type"], "lyrics")
        self.assertEqual(result["source"], "lrclib")
        self.assertTrue(result["synced"])
        self.assertEqual(result["lines"][0]["text"], "Hello")
        self.assertEqual(result["lines"][0]["time"], 1000)

    def test_falls_through_to_the_next_provider(self):
        netease = {
            "type": "lyrics", "source": "netease", "synced": True,
            "lines": [fetch_lyrics.make_line(0, "Hi")],
        }
        with mock.patch.dict(fetch_lyrics.ADAPTERS, {
            "lrclib": lambda track, options: None,
            "netease": lambda track, options: netease,
        }):
            result = fetch_lyrics.fetch(
                {"title": "Song", "artist": "Artist"},
                {"providers": ["lrclib", "netease"]},
            )
        self.assertEqual(result["source"], "netease")

    def test_fetch_all_returns_every_successful_provider(self):
        lrclib = {
            "type": "lyrics", "source": "lrclib", "synced": True,
            "lines": [fetch_lyrics.make_line(0, "A")],
        }
        netease = {
            "type": "lyrics", "source": "netease", "synced": False,
            "lines": [fetch_lyrics.make_line(-1, "B")],
        }
        with mock.patch.dict(fetch_lyrics.ADAPTERS, {
            "lrclib": lambda track, options: lrclib,
            "netease": lambda track, options: netease,
            "qqmusic": lambda track, options: None,
        }):
            result = fetch_lyrics.fetch(
                {"title": "Song", "artist": "Artist"},
                {"providers": ["lrclib", "netease", "qqmusic"], "fetch_all": True},
            )
        self.assertEqual(result["type"], "all")
        self.assertEqual([item["source"] for item in result["results"]], ["lrclib", "netease"])
        self.assertTrue(result["results"][0]["synced"])
        self.assertFalse(result["results"][1]["synced"])

    @mock.patch("fetch_lyrics.request_json")
    def test_skips_plain_text_when_disabled(self, request_json):
        request_json.return_value = [{
            "id": 1, "trackName": "Song", "artistName": "Artist",
            "duration": 200, "plainLyrics": "Hello", "syncedLyrics": "",
        }]
        result = fetch_lyrics.fetch(
            {"title": "Song", "artist": "Artist", "duration": 200},
            {"providers": ["lrclib"], "allow_plain_text": False},
        )
        self.assertEqual(result["type"], "none")


class MainTest(unittest.TestCase):
    def test_reads_request_file_and_prints_json(self):
        payload = {
            "type": "lyrics", "source": "lrclib", "synced": True,
            "lines": [fetch_lyrics.make_line(1000, "Line")],
        }
        with mock.patch.dict(fetch_lyrics.ADAPTERS, {
            "lrclib": lambda track, options: payload,
        }):
            handle = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
            json.dump({
                "track": {"title": "Song", "artist": "Artist"},
                "options": {"providers": ["lrclib"]},
            }, handle)
            handle.close()
            buffer = io.StringIO()
            with mock.patch("sys.argv", ["fetch_lyrics.py", handle.name]):
                with contextlib.redirect_stdout(buffer):
                    fetch_lyrics.main()
        payload = json.loads(buffer.getvalue())
        self.assertEqual(payload["type"], "lyrics")
        self.assertEqual(payload["lines"][0]["text"], "Line")
        self.assertFalse(os.path.exists(handle.name))

    def test_handles_unreadable_request_file(self):
        with mock.patch("sys.argv", ["fetch_lyrics.py", "/nonexistent/path.json"]):
            buffer = io.StringIO()
            with contextlib.redirect_stdout(buffer):
                fetch_lyrics.main()
        payload = json.loads(buffer.getvalue())
        self.assertEqual(payload["type"], "none")


class ParseLyricsfileTest(unittest.TestCase):
    def _doc(self, **kw):
        base = {
            "version": "1.0",
            "metadata": {"title": "T", "artist": "A"},
            "lines": [],
        }
        base.update(kw)
        import yaml
        return yaml.dump(base)

    def test_word_synced_lines(self):
        doc = self._doc(lines=[{
            "text": "Hello world",
            "start_ms": 1000,
            "end_ms": 3000,
            "words": [
                {"text": "Hello ", "start_ms": 1000},
                {"text": "world", "start_ms": 2000},
            ],
        }])
        lines = fetch_lyrics.parse_lyricsfile(doc)
        self.assertEqual(len(lines), 1)
        self.assertEqual(lines[0]["text"], "Hello world")
        self.assertEqual(lines[0]["time"], 1000)
        self.assertEqual(lines[0]["duration"], 2000)
        self.assertEqual(lines[0]["chars"], [1000] * 6 + [2000] * 5)

    def test_line_synced_only(self):
        doc = self._doc(lines=[{
            "text": "No words here",
            "start_ms": 500,
            "end_ms": 2500,
        }])
        lines = fetch_lyrics.parse_lyricsfile(doc)
        self.assertEqual(len(lines), 1)
        self.assertEqual(lines[0]["text"], "No words here")
        self.assertEqual(lines[0]["time"], 500)
        self.assertEqual(lines[0]["duration"], 2000)
        self.assertEqual(lines[0]["chars"], [])

    def test_overlapping_lines(self):
        doc = self._doc(lines=[
            {"text": "Line A", "start_ms": 0, "end_ms": 3000},
            {"text": "Line B", "start_ms": 1500, "end_ms": 4000},
        ])
        lines = fetch_lyrics.parse_lyricsfile(doc)
        self.assertEqual(len(lines), 2)
        self.assertEqual(lines[0]["time"], 0)
        self.assertEqual(lines[1]["time"], 1500)

    def test_instrumental_returns_empty(self):
        doc = self._doc(metadata={"title": "T", "artist": "A", "instrumental": True})
        self.assertEqual(fetch_lyrics.parse_lyricsfile(doc), [])

    def test_wrong_version_returns_empty(self):
        doc = self._doc(version="2.0", lines=[{"text": "X", "start_ms": 0}])
        self.assertEqual(fetch_lyrics.parse_lyricsfile(doc), [])

    def test_malformed_yaml_returns_empty(self):
        self.assertEqual(fetch_lyrics.parse_lyricsfile("{not valid yaml {{{"), [])

    def test_empty_string_returns_empty(self):
        self.assertEqual(fetch_lyrics.parse_lyricsfile(""), [])

    def test_no_lines_key_returns_empty(self):
        doc = 'version: "1.0"\nmetadata:\n  title: T\n  artist: A\n'
        self.assertEqual(fetch_lyrics.parse_lyricsfile(doc), [])

    def test_skips_empty_text(self):
        doc = self._doc(lines=[
            {"text": "", "start_ms": 0, "end_ms": 1000},
            {"text": "Real", "start_ms": 1000, "end_ms": 2000},
        ])
        lines = fetch_lyrics.parse_lyricsfile(doc)
        self.assertEqual(len(lines), 1)
        self.assertEqual(lines[0]["text"], "Real")


class LrclibEnhancedTest(unittest.TestCase):
    @mock.patch("fetch_lyrics.request_json")
    def test_uses_lyricsfile_when_enhanced(self, request_json):
        import yaml
        lf = yaml.dump({
            "version": "1.0",
            "metadata": {"title": "Song", "artist": "Artist"},
            "lines": [{
                "text": "Word-synced",
                "start_ms": 1000,
                "end_ms": 3000,
                "words": [
                    {"text": "Word-", "start_ms": 1000},
                    {"text": "synced", "start_ms": 2000},
                ],
            }],
        })
        request_json.return_value = [{
            "id": 1, "trackName": "Song", "artistName": "Artist",
            "duration": 200, "syncedLyrics": "[00:01.00]Fallback",
            "lyricsfile": lf,
        }]
        result = fetch_lyrics.fetch(
            {"title": "Song", "artist": "Artist", "duration": 200},
            {"providers": ["lrclib"], "enhanced": True},
        )
        self.assertEqual(result["type"], "lyrics")
        self.assertEqual(result["lines"][0]["text"], "Word-synced")
        self.assertEqual(result["lines"][0]["chars"], [1000] * 5 + [2000] * 6)

    @mock.patch("fetch_lyrics.request_json")
    def test_falls_back_to_lrc_when_lyricsfile_empty(self, request_json):
        request_json.return_value = [{
            "id": 1, "trackName": "Song", "artistName": "Artist",
            "duration": 200, "syncedLyrics": "[00:01.00]LRC line",
            "lyricsfile": "",
        }]
        result = fetch_lyrics.fetch(
            {"title": "Song", "artist": "Artist", "duration": 200},
            {"providers": ["lrclib"], "enhanced": True},
        )
        self.assertEqual(result["type"], "lyrics")
        self.assertEqual(result["lines"][0]["text"], "LRC line")

    @mock.patch("fetch_lyrics.request_json")
    def test_skips_lyricsfile_when_not_enhanced(self, request_json):
        import yaml
        lf = yaml.dump({
            "version": "1.0",
            "metadata": {"title": "Song", "artist": "Artist"},
            "lines": [{"text": "Word", "start_ms": 0, "end_ms": 1000}],
        })
        request_json.return_value = [{
            "id": 1, "trackName": "Song", "artistName": "Artist",
            "duration": 200, "syncedLyrics": "[00:01.00]LRC line",
            "lyricsfile": lf,
        }]
        result = fetch_lyrics.fetch(
            {"title": "Song", "artist": "Artist", "duration": 200},
            {"providers": ["lrclib"], "enhanced": False},
        )
        self.assertEqual(result["type"], "lyrics")
        self.assertEqual(result["lines"][0]["text"], "LRC line")


if __name__ == "__main__":
    unittest.main()
