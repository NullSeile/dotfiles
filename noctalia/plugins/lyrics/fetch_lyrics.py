#!/usr/bin/env python3
"""Fetch lyrics for the Noctalia Lyrics plugin.

Usage: fetch_lyrics.py <request-file>

The request file is one JSON object:
  {
    "track":   {"title": str, "artist": str, "album": str, "duration": int},
    "options": {"providers": [str], "lang": str, "enhanced": bool,
                "allow_plain_text": bool, "fetch_all": bool}
  }

Duration is seconds. The script prints one JSON object on stdout:
  {"type": "lyrics", "source": "<provider>", "synced": bool, "lines": [...]}
  {"type": "all", "results": [{"source": str, "synced": bool, "lines": [...]}, ...]}
  {"type": "none", "error": "..."}

Each line is:
  {"time": int, "duration": int, "text": str,
   "translation": str, "romanization": str, "chars": [int]}

`time` is milliseconds from the start of the track, or -1 for plain text.
`chars[i]` is when character i of `text` becomes active (word-timed lyrics).
"""

from __future__ import annotations

import base64
import html
import http.cookiejar
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

try:
    import yaml

    HAS_YAML = True
except ImportError:
    HAS_YAML = False

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

USER_AGENT = "Noctalia-Lyrics/2.0"
HEADERS = {
    "User-Agent": USER_AGENT,
    "Accept": "application/json, text/plain, */*",
}

PROVIDERS = ("lrclib", "netease", "qqmusic", "kugou", "musixmatch")
ALIASES = {
    "qq": "qqmusic",
    "netease_cloud": "netease",
    "netease_public": "netease",
}

TIME_TAG = re.compile(r"\[(\d{1,3}):(\d{1,2}(?:[.,:]\d{1,3})?)\]")
OFFSET_TAG = re.compile(r"\[offset:\s*([+-]?\d+)\s*\]", re.I)
META_TAG = re.compile(r"^\[(ar|al|ti|by|re|ve|length|offset|tool|encoding)\s*:", re.I)
WORD_TAG = re.compile(r"<(\d{1,2}):(\d{1,2}(?:[.,:]\d{1,3})?)>")
KRC_LINE = re.compile(r"^\[(\d+),(\d+)\](.*)$")
PREFIX_WORD = re.compile(r"(?:<|\()(\d+),(\d+)(?:,\d+)?(?:>|\))([^<(]*)")
SUFFIX_WORD = re.compile(r"(.*?)<(\d+),(\d+)(?:,\d+)?>")
QRC_WORD = re.compile(r"(.*?)\((\d+),(\d+)\)")
CREDIT = re.compile(
    r"^(词|曲|歌词|作詞|作词|作曲|編曲|编曲|制作|製作|制作人|監制|监制"
    r"|lyricist|composer|arranger|producer)\s*[:：]",
    re.I,
)
PAREN = re.compile(r"^\(([^()]*)\)$")

CACHE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cache")
MUSIXMATCH_TOKEN_PATH = os.path.join(CACHE_DIR, "musixmatch_token.json")
MUSIXMATCH_APP_ID = "web-desktop-app-v1.0"
MUSIXMATCH_ROOT = "https://apic.musixmatch.com/ws/1.1/"


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

def clean(value) -> str:
    return html.unescape(str(value or "")).replace("\ufeff", "").strip()


def as_int(value, default: int = 0) -> int:
    try:
        return int(float(value))
    except (TypeError, ValueError, OverflowError):
        return default


def folded(value) -> str:
    return "".join(ch.lower() for ch in clean(value) if ch.isalnum())


def timestamp_ms(minutes, seconds) -> int:
    seconds = str(seconds).replace(":", ".").replace(",", ".")
    return int(round(as_int(minutes) * 60000 + float(seconds) * 1000))


def duration_ms(value) -> int:
    """Accept seconds, milliseconds, or microseconds and return milliseconds."""
    n = as_int(value)
    if n <= 0:
        return 0
    if n < 10_000:
        return n * 1000
    if n > 10_000_000:
        return n // 1000
    return n


def make_line(start, text, duration=0, translation="", romanization="", chars=None):
    return {
        "time": as_int(start, -1),
        "duration": max(0, as_int(duration)),
        "text": clean(text),
        "translation": clean(translation),
        "romanization": clean(romanization),
        "chars": [as_int(item) for item in (chars or [])],
    }


def artist_names(value) -> str:
    if isinstance(value, list):
        parts = []
        for item in value:
            if isinstance(item, dict):
                parts.append(clean(item.get("name")))
            else:
                parts.append(clean(item))
        return " ".join(part for part in parts if part)
    return clean(value)


def log(message: str) -> None:
    """Diagnostics go to stderr so stdout stays a single JSON response."""
    print(f"lyrics: {message}", file=sys.stderr, flush=True)


def describe_lines(lines) -> str:
    if not lines:
        return "0 lines"
    timed = sum(1 for item in lines if item["time"] >= 0)
    worded = sum(1 for item in lines if item.get("chars"))
    translated = sum(1 for item in lines if item.get("translation"))
    romanized = sum(1 for item in lines if item.get("romanization"))
    parts = [f"{len(lines)} lines"]
    if timed:
        parts.append(f"{timed} timed")
    else:
        parts.append("plain")
    if worded:
        parts.append(f"{worded} word-timed")
    if translated:
        parts.append(f"{translated} translated")
    if romanized:
        parts.append(f"{romanized} romanized")
    first = lines[0]
    if first["time"] >= 0 and first["text"]:
        preview = first["text"][:48]
        parts.append(f'first="{preview}" @{first["time"]}ms')
    return ", ".join(parts)


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

def word_timings(body: str):
    """Split an enhanced-LRC body into visible text and per-character times."""
    if not WORD_TAG.search(body):
        return body, []

    segments = []
    cursor = 0
    for match in WORD_TAG.finditer(body):
        if match.start() > cursor:
            segments.append((body[cursor:match.start()], -1))
        segments.append(("", timestamp_ms(match.group(1), match.group(2))))
        cursor = match.end()
    if cursor < len(body):
        segments.append((body[cursor:], -1))

    text_parts, chars, active = [], [], -1
    for fragment, start in segments:
        if fragment:
            text_parts.append(fragment)
            chars.extend([max(0, active)] * len(fragment))
        else:
            active = start
    return "".join(text_parts), chars


def _krc_words(body: str):
    absolute = body.startswith("(")
    if re.match(r"^[<(]\d+,", body):
        found = PREFIX_WORD.findall(body)
        return [(word, as_int(off), as_int(dur)) for off, dur, word in found], absolute
    found = SUFFIX_WORD.findall(body)
    if found:
        return [(word, as_int(off), as_int(dur)) for word, off, dur in found], False
    found = QRC_WORD.findall(body)
    if found:
        return [(word, as_int(off), as_int(dur)) for word, off, dur in found], True
    return [], False


def parse_krc_line(start: int, duration: int, body: str, offset: int):
    words, absolute = _krc_words(body)
    if not words:
        text = clean(body)
        return make_line(start + offset, text, duration) if text else None

    text = ""
    chars = []
    for word, word_off, word_dur in words:
        word_start = word_off if absolute else start + word_off
        for index, char in enumerate(word):
            text += char
            chars.append(word_start + (index * word_dur // max(1, len(word))))
    if not clean(text):
        return None
    return make_line(start + offset, text, duration, chars=chars)


def parse_lrc(text: str):
    """Parse LRC, enhanced LRC, or KRC/YRC/QRC lines into plugin lines."""
    text = str(text or "").replace("\r\n", "\n").replace("\r", "\n")
    offset_match = OFFSET_TAG.search(text)
    offset = as_int(offset_match.group(1)) if offset_match else 0

    lines = []
    for raw in text.split("\n"):
        raw = raw.strip()
        if not raw or META_TAG.match(raw):
            continue

        krc = KRC_LINE.match(raw)
        if krc:
            parsed = parse_krc_line(as_int(krc.group(1)), as_int(krc.group(2)), krc.group(3), offset)
            if parsed:
                lines.append(parsed)
            continue

        tags = TIME_TAG.findall(raw)
        body = TIME_TAG.sub("", raw).strip()
        if not tags:
            match = PAREN.match(body)
            if match and lines and lines[-1]["time"] >= 0 and not lines[-1]["translation"]:
                lines[-1]["translation"] = match.group(1)
            continue
        if not body or CREDIT.match(body):
            continue
        content, chars = word_timings(body)
        if not clean(content):
            continue
        for minutes, seconds in tags:
            start = timestamp_ms(minutes, seconds) + offset
            shifted = [t + offset for t in chars] if chars else []
            lines.append(make_line(start, content, chars=shifted))

    lines.sort(key=lambda item: item["time"])
    return lines


def parse_plain(text: str):
    return [
        make_line(-1, value)
        for value in str(text or "").splitlines()
        if clean(value) and not CREDIT.match(value)
    ]


def parse_yrc_json(data):
    if isinstance(data, dict) and "c" in data:
        data = [data]
    if not isinstance(data, list):
        return []
    lines = []
    for item in data:
        if not isinstance(item, dict):
            continue
        start = as_int(item.get("t", item.get("start")))
        words = item.get("c") or item.get("words") or []
        parts, chars = [], []
        if isinstance(words, list):
            for word in words:
                if isinstance(word, dict):
                    token = str(word.get("tx") or word.get("c") or "")
                    word_time = as_int(word.get("t", start))
                else:
                    token, word_time = str(word), start
                if not token:
                    continue
                parts.append(token)
                chars.extend([word_time] * len(token))
        text = "".join(parts) or str(item.get("text") or "")
        if text:
            lines.append(make_line(start, text, chars=chars or None))
    return lines


def parse_text(text: str, allow_plain: bool):
    """Turn a lyric payload into lines. Prefer timed formats."""
    text = str(text or "").strip()
    if not text:
        return []
    lines = parse_lrc(text)
    if lines:
        return lines
    stripped = text.lstrip("\ufeff")
    if stripped[:1] in "[{":
        try:
            lines = parse_yrc_json(json.loads(stripped))
        except ValueError:
            lines = []
        if lines:
            return lines
    if allow_plain:
        return parse_plain(text)
    return []


def parse_lyricsfile(raw: str) -> list:
    """Parse a Lyricsfile YAML document into plugin lines.

    Returns a list of line dicts, or an empty list on failure.
    Word-level timing is converted to per-character activation times.
    """
    if not HAS_YAML or not raw:
        return []
    try:
        doc = yaml.safe_load(raw)
    except yaml.YAMLError:
        return []
    if not isinstance(doc, dict):
        return []
    if doc.get("version") != "1.0":
        return []
    meta = doc.get("metadata")
    if not isinstance(meta, dict):
        return []
    if meta.get("instrumental") is True:
        return []
    raw_lines = doc.get("lines")
    if not isinstance(raw_lines, list):
        return []
    lines = []
    for item in raw_lines:
        if not isinstance(item, dict):
            continue
        text = clean(item.get("text"))
        start = as_int(item.get("start_ms"))
        if not text or start < 0:
            continue
        end = as_int(item.get("end_ms"))
        duration = max(0, end - start) if end >= start else 0
        chars = []
        words = item.get("words")
        if isinstance(words, list) and words:
            for w in words:
                if not isinstance(w, dict):
                    continue
                wtext = str(w.get("text") or "")
                wstart = as_int(w.get("start_ms"))
                if wtext and wstart >= 0:
                    chars.extend([wstart] * len(wtext))
        lines.append(make_line(start, text, duration, chars=chars or None))
    return lines


def maybe_decode(text: str) -> str:
    text = text or ""
    if not text or TIME_TAG.search(text) or KRC_LINE.search(text):
        return text
    try:
        decoded = base64.b64decode(text).decode("utf-8", "replace")
    except (ValueError, TypeError):
        return text
    return decoded or text


def merge_field(primary, secondary, field: str, tolerance: int = 500):
    if not primary or not secondary:
        return primary
    untimed = [item for item in secondary if item["time"] < 0]
    timed = [item for item in secondary if item["time"] >= 0]
    for index, target in enumerate(primary):
        value = ""
        if target["time"] >= 0 and timed:
            candidate = min(timed, key=lambda item: abs(item["time"] - target["time"]))
            if abs(candidate["time"] - target["time"]) <= tolerance:
                value = candidate["text"]
        elif index < len(untimed):
            value = untimed[index]["text"]
        if value and not target.get(field):
            target[field] = value
    return primary


# ---------------------------------------------------------------------------
# Matching
# ---------------------------------------------------------------------------

def title_score(wanted: str, got: str) -> int:
    if not wanted or not got:
        return 0
    if wanted == got:
        return 6
    if wanted in got or got in wanted:
        return 3
    return 0


def artist_score(wanted: str, got: str) -> int:
    if not wanted or not got:
        return 0
    if wanted == got:
        return 4
    if wanted in got or got in wanted:
        return 2
    return 0


def album_score(wanted: str, got: str) -> int:
    if not wanted or not got:
        return 0
    if wanted == got:
        return 2
    if wanted in got or got in wanted:
        return 1
    return 0


def pick_best(items, track, title_of, artist_of, album_of=None):
    """Return the best catalog match, or None if the title does not match."""
    wanted_title = folded(track.get("title"))
    wanted_artist = folded(track.get("artist"))
    wanted_album = folded(track.get("album"))
    best, best_score = None, -1
    for item in items or []:
        title = folded(title_of(item))
        match = title_score(wanted_title, title)
        if match == 0:
            continue
        score = match
        score += artist_score(wanted_artist, folded(artist_of(item)))
        if album_of:
            score += album_score(wanted_album, folded(album_of(item)))
        if score > best_score:
            best, best_score = item, score
    return best if best_score >= 3 else None


def rank_lrclib(items, track):
    """Order LRCLIB hits: identity, then duration, then synced over plain."""
    wanted_title = folded(track.get("title"))
    wanted_artist = folded(track.get("artist"))
    wanted_album = folded(track.get("album"))
    wanted_sec = duration_ms(track.get("duration")) / 1000
    ranked = []
    seen = set()
    for index, item in enumerate(items if isinstance(items, list) else []):
        if not isinstance(item, dict):
            continue
        item_id = clean(item.get("id"))
        if not item_id or item_id in seen:
            continue
        synced = bool(clean(item.get("syncedLyrics")))
        plain = bool(clean(item.get("plainLyrics")))
        if not synced and not plain:
            continue

        identity = title_score(wanted_title, folded(item.get("trackName")))
        if wanted_title and identity == 0:
            continue
        artist = artist_score(wanted_artist, folded(item.get("artistName")))
        if wanted_artist and artist == 0:
            continue
        identity += artist
        identity += album_score(wanted_album, folded(item.get("albumName")))

        duration_bucket = 5
        duration_diff = float("inf")
        candidate_sec = as_int(item.get("duration"))
        if wanted_sec > 0 and candidate_sec > 0:
            duration_diff = abs(wanted_sec - candidate_sec)
            if duration_diff <= 2:
                duration_bucket = 0
            elif duration_diff <= 5:
                duration_bucket = 1
            elif duration_diff <= 10:
                duration_bucket = 2
            elif duration_diff <= 20:
                duration_bucket = 3
            else:
                duration_bucket = 4

        if identity >= 3:
            seen.add(item_id)
            ranked.append((-identity, duration_bucket, -int(synced), duration_diff, index, item))

    ranked.sort(key=lambda row: row[:-1])
    return [row[-1] for row in ranked]


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

_opener = urllib.request.build_opener(
    urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar())
)


def with_query(base: str, params: dict) -> str:
    return base + ("&" if "?" in base else "?") + urllib.parse.urlencode(params)


def request_text(url: str, headers=None, timeout: int = 8) -> str:
    req = urllib.request.Request(url, headers={**HEADERS, **(headers or {})})
    with _opener.open(req, timeout=timeout) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        return response.read().decode(charset, "replace")


def request_json(url: str, headers=None, timeout: int = 8):
    text = request_text(url, headers, timeout).strip()
    if "(" in text[:48] and text.endswith(")"):
        text = text[text.find("(") + 1 : text.rfind(")")]
    return json.loads(text)


# ---------------------------------------------------------------------------
# Providers
# Each function takes (track, options) and returns a result dict or None.
# Search, pick the closest match, fetch lyrics, parse. Nothing else.
# ---------------------------------------------------------------------------

def from_lrclib(track, options):
    params = {"track_name": track.get("title") or "", "artist_name": track.get("artist") or ""}
    if track.get("album"):
        params["album_name"] = track["album"]
    data = request_json(with_query("https://lrclib.net/api/search", params))
    matches = rank_lrclib(data, track)
    if not matches:
        log("lrclib: no match")
        return None
    best = matches[0]
    synced = bool(clean(best.get("syncedLyrics")))
    log(
        f'lrclib: picked "{clean(best.get("trackName"))}" / '
        f'"{clean(best.get("artistName"))}" '
        f'duration={as_int(best.get("duration"))}s '
        f'synced={synced} candidates={len(matches)}'
    )
    if options["enhanced"]:
        lf = clean(best.get("lyricsfile"))
        if lf:
            lines = parse_lyricsfile(lf)
            if lines:
                log(f"lrclib: using lyricsfile ({len(lines)} lines)")
                return accept("lrclib", lines, options)
            log("lrclib: lyricsfile parse failed, falling back to LRC")
    text = best.get("syncedLyrics") or ""
    if not text and options["allow_plain_text"]:
        text = best.get("plainLyrics") or ""
        if text:
            log("lrclib: using plain lyrics")
    return accept("lrclib", parse_text(text, options["allow_plain_text"]), options)


def from_netease(track, options):
    term = " ".join(part for part in (track.get("title"), track.get("artist")) if part)
    headers = {"Referer": "https://music.163.com/"}
    search = request_json(with_query("https://music.163.com/api/search/get", {
        "type": 1, "s": term, "limit": 10,
    }), headers)
    songs = (search.get("result") or {}).get("songs") or []
    best = pick_best(
        songs, track,
        lambda item: item.get("name"),
        lambda item: artist_names(item.get("artists")),
        lambda item: (item.get("album") or {}).get("name"),
    )
    if not best:
        log(f"netease: no match among {len(songs)} search hits")
        return None
    log(
        f'netease: picked "{clean(best.get("name"))}" / '
        f'"{artist_names(best.get("artists"))}" id={best.get("id")}'
    )
    data = request_json(with_query("https://music.163.com/api/song/lyric", {
        "id": best.get("id"), "lv": 1, "kv": 1, "tv": 1, "rv": 1, "yv": 1,
    }), headers)

    fields = ("yrc", "klyric", "lrc") if options["enhanced"] else ("lrc", "yrc", "klyric")
    lines = []
    used_field = ""
    for name in fields:
        blob = data.get(name) or {}
        text = blob.get("lyric", "") if isinstance(blob, dict) else blob
        lines = parse_text(text, False)
        if lines:
            used_field = name
            break
    if not lines and options["allow_plain_text"]:
        blob = data.get("lrc") or {}
        text = blob.get("lyric", "") if isinstance(blob, dict) else blob
        lines = parse_plain(text)
        if lines:
            used_field = "lrc(plain)"
    if used_field:
        log(f"netease: using {used_field}")

    trans = data.get("tlyric") or {}
    roma = data.get("romalrc") or {}
    merge_field(lines, parse_lrc(trans.get("lyric", "") if isinstance(trans, dict) else trans), "translation")
    merge_field(lines, parse_lrc(roma.get("lyric", "") if isinstance(roma, dict) else roma), "romanization")
    return accept("netease", lines, options)


def from_qqmusic(track, options):
    term = " ".join(part for part in (track.get("title"), track.get("artist")) if part)
    headers = {"Referer": "https://y.qq.com/"}
    search = request_json(with_query("https://c.y.qq.com/soso/fcgi-bin/client_search_cp", {
        "format": "json", "p": 1, "n": 10, "w": term,
    }), headers)
    songs = ((search.get("data") or {}).get("song") or {}).get("list") or []
    best = pick_best(
        songs, track,
        lambda item: item.get("songname") or item.get("title"),
        lambda item: artist_names(item.get("singer")),
        lambda item: item.get("albumname"),
    )
    if not best:
        log(f"qqmusic: no match among {len(songs)} search hits")
        return None
    mid = best.get("songmid") or best.get("mid") or ""
    log(
        f'qqmusic: picked "{clean(best.get("songname") or best.get("title"))}" / '
        f'"{artist_names(best.get("singer"))}" mid={mid}'
    )
    data = request_json(with_query("https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg", {
        "songmid": mid, "format": "json", "nobase64": 1, "g_tk": 5381,
    }), {"Referer": "https://y.qq.com/portal/player.html"})

    def field(name):
        return maybe_decode(data.get(name, "") or "")

    lines = parse_text(field("lyric"), options["allow_plain_text"])
    merge_field(lines, parse_lrc(field("trans")), "translation")
    merge_field(lines, parse_lrc(field("roma")), "romanization")
    return accept("qqmusic", lines, options)


def from_kugou(track, options):
    term = " ".join(part for part in (track.get("title"), track.get("artist")) if part)
    search = request_json(with_query("https://mobilecdn.kugou.com/api/v3/search/song", {
        "format": "json", "keyword": term, "page": 1, "pagesize": 10, "showtype": 1,
    }))
    songs = (search.get("data") or {}).get("info") or []
    best = pick_best(
        songs, track,
        lambda item: item.get("songname") or item.get("filename"),
        lambda item: item.get("singername"),
        lambda item: item.get("album_name"),
    )
    if not best:
        log(f"kugou: no match among {len(songs)} search hits")
        return None
    log(
        f'kugou: picked "{clean(best.get("songname") or best.get("filename"))}" / '
        f'"{clean(best.get("singername"))}"'
    )
    candidates = request_json(with_query("https://lyrics.kugou.com/search", {
        "ver": 1, "man": "yes", "client": "pc", "keyword": term,
        "duration": best.get("duration") or duration_ms(track.get("duration")),
        "hash": best.get("hash", ""),
    })).get("candidates") or []
    if not candidates:
        log("kugou: lyrics unavailable")
        return None
    candidate = candidates[0]
    data = request_json(with_query("https://lyrics.kugou.com/download", {
        "ver": 1, "client": "pc", "id": candidate.get("id"),
        "accesskey": candidate.get("accesskey"), "fmt": "lrc", "charset": "utf8",
    }))
    text = maybe_decode(data.get("content", "") or "")
    return accept("kugou", parse_text(text, options["allow_plain_text"]), options)


def _musixmatch_token():
    now = int(time.time())
    try:
        with open(MUSIXMATCH_TOKEN_PATH, encoding="utf-8") as handle:
            cached = json.load(handle)
        token = cached.get("token")
        expires = as_int(cached.get("expiration_time"))
        if token and expires > now:
            return token
    except (OSError, ValueError, TypeError):
        pass

    data = request_json(with_query(MUSIXMATCH_ROOT + "token.get", {
        "app_id": MUSIXMATCH_APP_ID, "user_language": "en",
    }))
    token = ((data.get("message") or {}).get("body") or {}).get("user_token")
    if not token:
        return ""
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(MUSIXMATCH_TOKEN_PATH, "w", encoding="utf-8") as handle:
        json.dump({"token": token, "expiration_time": now + 600}, handle)
    return token


def _musixmatch_get(method: str, params: dict, token: str):
    query = {"app_id": MUSIXMATCH_APP_ID, "usertoken": token, **params}
    data = request_json(
        with_query(MUSIXMATCH_ROOT + method, query),
        {"Origin": "https://www.musixmatch.com", "Referer": "https://www.musixmatch.com/"},
    )
    header = (data.get("message") or {}).get("header") or {}
    if as_int(header.get("status_code")) != 200:
        return {}
    return (data.get("message") or {}).get("body") or {}


def _parse_richsync(raw: str, offset: int = 0):
    try:
        payload = json.loads(raw)
    except ValueError:
        return []
    if not isinstance(payload, list):
        return []
    lines = []
    for item in payload:
        if not isinstance(item, dict):
            continue
        start = int(round(float(item.get("ts") or 0) * 1000)) + offset
        end = int(round(float(item.get("te") or 0) * 1000)) + offset
        parts, chars = [], []
        for word in item.get("l") or []:
            if not isinstance(word, dict):
                continue
            token = str(word.get("c") or "")
            if not token:
                continue
            # Richsync is word-timed: every character in a token shares the word
            # start. The widget spreads plateaus across the run at render time.
            word_start = start + int(round(float(word.get("o") or 0) * 1000))
            parts.append(token)
            chars.extend([word_start] * len(token))
        text = "".join(parts)
        if text:
            lines.append(make_line(start, text, max(0, end - start), chars=chars or None))
    return lines


def from_musixmatch(track, options):
    token = _musixmatch_token()
    if not token:
        log("musixmatch: no guest token")
        return None
    body = _musixmatch_get("track.search", {
        "q": " ".join(part for part in (track.get("title"), track.get("artist")) if part),
        "page_size": 5, "page": 1,
    }, token)
    tracks = [item.get("track") for item in body.get("track_list") or [] if isinstance(item, dict)]
    best = pick_best(
        tracks, track,
        lambda item: (item or {}).get("track_name"),
        lambda item: (item or {}).get("artist_name"),
        lambda item: (item or {}).get("album_name"),
    )
    if not best:
        log(f"musixmatch: no match among {len(tracks)} search hits")
        return None
    track_id = str(best.get("track_id") or "")
    if not track_id:
        log("musixmatch: match missing track_id")
        return None
    log(
        f'musixmatch: picked "{clean(best.get("track_name"))}" / '
        f'"{clean(best.get("artist_name"))}" id={track_id}'
    )

    lines = []
    used = ""
    if options["enhanced"]:
        rich = _musixmatch_get("track.richsync.get", {"track_id": track_id}, token)
        raw = (rich.get("richsync") or {}).get("richsync_body") or ""
        lines = _parse_richsync(raw)
        if lines:
            used = "richsync"
        else:
            log("musixmatch: richsync empty, falling back to subtitle")

    if not lines:
        sub = _musixmatch_get("track.subtitle.get", {
            "track_id": track_id, "subtitle_format": "lrc",
        }, token)
        text = (sub.get("subtitle") or {}).get("subtitle_body") or ""
        lines = parse_text(text, False)
        if lines:
            used = "subtitle"

    if not lines and options["allow_plain_text"]:
        lyrics = _musixmatch_get("track.lyrics.get", {"track_id": track_id}, token)
        text = (lyrics.get("lyrics") or {}).get("lyrics_body") or ""
        lines = parse_plain(text)
        if lines:
            used = "lyrics(plain)"

    if used:
        log(f"musixmatch: using {used}")

    lang = options["lang"]
    if lang and lines:
        trans = _musixmatch_get("crowd.track.translations.get", {
            "track_id": track_id,
            "selected_language": lang,
            "translation_fields_set": "minimal",
        }, token)
        extra = []
        for item in trans.get("translations_list") or []:
            value = item.get("translation", item) if isinstance(item, dict) else item
            if not isinstance(value, dict):
                continue
            extra.append(make_line(
                value.get("matched_time", value.get("time", -1)),
                value.get("description") or value.get("translation") or "",
            ))
        if extra:
            log(f"musixmatch: merged {len(extra)} translations ({lang})")
        else:
            log(f"musixmatch: no translations for {lang}")
        merge_field(lines, extra, "translation")
    return accept("musixmatch", lines, options)


ADAPTERS = {
    "lrclib": from_lrclib,
    "netease": from_netease,
    "qqmusic": from_qqmusic,
    "kugou": from_kugou,
    "musixmatch": from_musixmatch,
}


def accept(source, lines, options):
    if not lines:
        log(f"{source}: empty lyrics after parse")
        return None
    if lines[0]["time"] < 0 and not options["allow_plain_text"]:
        log(f"{source}: plain text rejected (allow_plain_text=false)")
        return None
    log(f"{source}: accepting {describe_lines(lines)}")
    return {
        "type": "lyrics",
        "source": source,
        "synced": lines[0]["time"] >= 0,
        "lines": lines,
    }


# ---------------------------------------------------------------------------
# Orchestrator
# ---------------------------------------------------------------------------

def normalize_options(raw) -> dict:
    names = []
    seen = set()
    for item in (raw.get("providers") or []):
        name = ALIASES.get(clean(item).lower(), clean(item).lower())
        if name in ADAPTERS and name not in seen:
            names.append(name)
            seen.add(name)
    lang = clean(raw.get("lang"))
    if lang.lower() in ("", "none"):
        lang = ""
    return {
        "providers": names or list(PROVIDERS),
        "lang": lang,
        "enhanced": raw.get("enhanced") is True,
        "allow_plain_text": raw.get("allow_plain_text") is not False,
        "fetch_all": raw.get("fetch_all") is True,
    }


def fetch_all(track, options) -> dict:
    title = clean(track.get("title"))
    artist = clean(track.get("artist"))
    if not title:
        return {"type": "none", "error": "no track title"}
    query = normalize_options(options)
    log(
        f'search-all "{title}" / "{artist}" '
        f'providers={",".join(query["providers"])} '
        f'enhanced={query["enhanced"]} plain={query["allow_plain_text"]} '
        f'lang={query["lang"] or "-"}'
    )
    results = []
    last_error = "no lyrics found"
    for name in query["providers"]:
        log(f"try {name}")
        try:
            result = ADAPTERS[name](track, query)
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, ValueError, OSError, KeyError, TypeError) as error:
            last_error = f"{name}: {error}"
            log(f"{name}: error {error}")
            continue
        if result:
            log(f'{name}: ok ({"synced" if result.get("synced") else "plain"})')
            results.append({
                "source": result["source"],
                "synced": result.get("synced", False),
                "lines": result["lines"],
            })
        else:
            log(f"{name}: skip")
    if not results:
        log(f"decided none ({last_error})")
        return {"type": "none", "error": last_error}
    log(f"decided all ({len(results)} providers)")
    return {"type": "all", "results": results}


def fetch(track, options) -> dict:
    query = normalize_options(options)
    if query["fetch_all"]:
        return fetch_all(track, options)
    title = clean(track.get("title"))
    artist = clean(track.get("artist"))
    if not title:
        return {"type": "none", "error": "no track title"}
    log(
        f'search "{title}" / "{artist}" '
        f'providers={",".join(query["providers"])} '
        f'enhanced={query["enhanced"]} plain={query["allow_plain_text"]} '
        f'lang={query["lang"] or "-"}'
    )
    last_error = "no lyrics found"
    for name in query["providers"]:
        log(f"try {name}")
        try:
            result = ADAPTERS[name](track, query)
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, ValueError, OSError, KeyError, TypeError) as error:
            last_error = f"{name}: {error}"
            log(f"{name}: error {error}")
            continue
        if result:
            log(f'decided {result["source"]} ({"synced" if result.get("synced") else "plain"})')
            return result
        log(f"{name}: skip")
    log(f"decided none ({last_error})")
    return {"type": "none", "error": last_error}


def main():
    request_path = sys.argv[1] if len(sys.argv) > 1 else ""
    request = {}
    if request_path:
        try:
            with open(request_path, encoding="utf-8") as handle:
                request = json.load(handle)
        except (OSError, UnicodeError, ValueError) as error:
            print(json.dumps({"type": "none", "error": f"bad request: {error}"}))
            return
        finally:
            try:
                os.remove(request_path)
            except OSError:
                pass

    track = request.get("track") if isinstance(request.get("track"), dict) else {}
    options = request.get("options") if isinstance(request.get("options"), dict) else {}
    try:
        response = fetch(track, options)
    except Exception as error:  # noqa: BLE001 — always answer with valid JSON
        response = {"type": "none", "error": f"unexpected: {error}"}
    print(json.dumps(response, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    main()
