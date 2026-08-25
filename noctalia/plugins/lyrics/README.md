# Noctalia Lyrics 2.1

Synchronized lyrics for the Noctalia bar, fetched directly from public
providers (no extra Python packages), with karaoke highlighting, translations,
marquee scrolling, and flexible layout controls.

## Plugin

| Field | Value |
| --- | --- |
| ID | `nullptr/lyrics` |
| Entries | Bar widget: `lyrics`; service: `service` |

## Architecture

- `lyrics_service.luau` polls MPRIS players through `playerctl`, picks the
  active player (honoring the allow/block lists), and publishes playback state.
- On every track change it writes a small JSON request and runs
  `fetch_lyrics.py`, which tries the configured providers in order and returns
  normalized lyric lines as JSON.
- `lyrics.luau` is a pure presentation widget: it mirrors the published state
  and renders karaoke-highlighted lines.

## Requirements

- `playerctl` — read and control MPRIS players.
- `python3` — standard library only (`urllib`, `json`). No pip packages.

`scripts/setup-deps.sh [--check] [--yes]` installs the system commands.

## Providers

`fetch_lyrics.py` tries these IDs in order and stops at the first usable match:

| ID | Notes |
| --- | --- |
| `lrclib` | Public LRCLIB search. Ranked by title/artist/album, then duration, then synced over plain. |
| `netease` | NetEase Cloud Music. Line LRC, optional YRC/KRC word timing, translations, romanization. |
| `qqmusic` | QQ Music. Line LRC plus translation and romanization tracks. |
| `kugou` | Kugou Music. Line LRC. |
| `musixmatch` | Musixmatch desktop API with a cached guest token. Line LRC, optional richsync, crowd translations. |

The `providers` setting reorders or disables them. `allow_plain_text` permits
unsynced lyrics when nothing timed is found.

`enhanced` asks providers that have word timing to use it (Musixmatch richsync,
NetEase YRC). `translation_language` is sent to Musixmatch; NetEase and QQ
Music attach translations when the catalog has them, without pinning the
search to one provider.

Translations appear on the widget's second line when `double_line`,
`show_translation`, and the provider data align.

## Usage

Enable `nullptr/lyrics`, start its `service` entry, and add the `lyrics` bar
widget. Right-click toggles play/pause on the selected player; scrolling skips
tracks. Hover the widget for a tooltip showing the current source.

## External protocol

Address the singleton service with:

```sh
noctalia msg plugin nullptr/lyrics:service all <event> '<payload>'
```

Supported events:

- `push-lrc`: LRC text (or plain lines); replaces current lyrics.
- `clear`: clears current lyrics.

## Local development

Add the parent directory of this checkout as a local Noctalia source:

```sh
noctalia msg plugins source add lyrics-dev path /path/to/plugin-parent
noctalia msg plugins enable nullptr/lyrics
noctalia msg config-reload
```

Run validation after every change:

```sh
sh lyrics/scripts/setup-deps.sh --check
cd lyrics
python3 -m py_compile fetch_lyrics.py
python3 test_fetch_lyrics.py
```

## Lyric model

Lines always carry the same shape; times are milliseconds and `chars[i]` is
the activation time of character i (filled only for word-timed lyrics):

```json
{
  "time": 1200,
  "duration": 0,
  "text": "Original lyric",
  "translation": "Translated lyric",
  "romanization": "",
  "chars": []
}
```

MPRIS track duration and position are microseconds; everything inside a line
is milliseconds.
