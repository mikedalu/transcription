# Audio Stem Separator

A local command-line tool that turns a song into **separate audio tracks** using
[Demucs](https://github.com/facebookresearch/demucs) on CPU.

No cloud service, no GPU, no sheet music or PDF generation. Input can be a local
audio file or a YouTube link; output is 320 kbps MP3 stems and mixes.

## Features

- **Vocals / drums / bass / other** stems from a full mix
- **Instrumental**, **no-bass**, and **no-drums** mixes
- **Fast two-stem mode** for vocals + accompaniment only
- Local files (`mp3`, `wav`, `flac`, `ogg`, `m4a`) or YouTube URLs
- Resumable runs: completed stems/mixes are skipped
- Optional pitch shift and tempo change via FFmpeg
- Work files are deleted after a successful run unless `--keep-work`
- CPU-only PyTorch; no CUDA download

> This project does **not** generate PDFs, MIDI, MusicXML, lyrics, or MuseScore
> scores. It only processes audio into stems.

## Requirements

- Ubuntu (tested on 24.04)
- Python 3.11 available (uv can download it)
- **ffmpeg** with `amix`, `alimiter`, `atempo`, and `rubberband`
- **yt-dlp** already installed (only needed for YouTube links)
- At least 1.5 GB free disk space
- 16 GB RAM recommended

## Installation

```bash
bash install.sh
```

The installer:

1. Checks disk space, ffmpeg filters, `libsndfile1`, and `yt-dlp`
2. Installs `uv` if missing
3. Creates `~/venvs/demucs` with Python 3.11
4. Installs CPU-only `torch`/`torchaudio` (`+cpu`, `< 2.9`), Demucs, and soundfile
5. Purges package caches and reports the venv size

The demucs venv is roughly 1 GB. No MuseScore, basic-pitch, TensorFlow, Whisper,
or other scoring packages are installed.

## Usage

```bash
bash transcribe.sh <input> <name> [options]
```

| Argument | Description |
|----------|-------------|
| `<input>` | Local audio file (`mp3`, `wav`, `flac`, `ogg`, `m4a`) or YouTube URL |
| `<name>` | Song name used for the output folder and filenames |

### Options

| Flag | Description |
|------|-------------|
| `--fast` | Two-stem separation: vocals + accompaniment only |
| `--keep-work` | Keep intermediate WAV stems and source audio |
| `--key-shift N` | Shift pitch by N semitones (`rubberband`) |
| `--tempo X` | Change tempo by factor X (0.5–2.0, `atempo`) |

### Examples

```bash
# Full separation
bash transcribe.sh ~/Music/song.mp3 "my-song"

# YouTube input
bash transcribe.sh "https://www.youtube.com/watch?v=EXAMPLE" "my-song"

# Fast two-stem mode
bash transcribe.sh ~/Music/song.mp3 "my-song" --fast

# Transpose down 2 semitones and slow to 90%
bash transcribe.sh ~/Music/song.mp3 "my-song" --key-shift -2 --tempo 0.9

# Keep the WAV stems for further processing
bash transcribe.sh ~/Music/song.mp3 "my-song" --keep-work
```

## Outputs

Results are written to `~/transcribe/output/<name>/`.

### Full mode

| File | Description |
|------|-------------|
| `<name>-vocals.mp3` | Isolated vocals |
| `<name>-drums.mp3` | Isolated drums |
| `<name>-bass.mp3` | Isolated bass |
| `<name>-other.mp3` | Remaining instruments |
| `<name>-instrumental.mp3` | Drums + bass + other |
| `<name>-no-bass.mp3` | Drums + other |
| `<name>-no-drums.mp3` | Bass + other |

### Fast mode (`--fast`)

| File | Description |
|------|-------------|
| `<name>-vocals.mp3` | Isolated vocals |
| `<name>-instrumental.mp3` | Everything except vocals |

All outputs are **320 kbps MP3**. Intermediate Demucs stems are lossless WAV
files and are deleted after a successful run unless `--keep-work` is used.

Pitch/tempo changes are applied consistently to every stem and mix.

## Resuming and settings

Progress lives in `~/transcribe/work/<name>/`. If a run is interrupted, rerun
the same command and completed steps are skipped.

A hidden `.transcribe-params` file records the input and audio settings. Using
the same `<name>` with a different input, `--fast`, key, or tempo while outputs
exist stops with a clear message instead of mixing incompatible files. Use a
new `<name>` or delete the output folder to change settings.

## Processing Time

On a CPU Core i7 with 16 GB RAM:

| Track Length | Estimated Time |
|-------------|----------------|
| 30 sec | 1–3 min |
| 3–4 min | 5–15 min |
| 6+ min | 15–30 min |

Tracks longer than 6 minutes automatically use Demucs `--segment 7` to limit
RAM.

## CLI commands at a glance

```bash
bash transcribe.sh song.mp3 "song"                 # full stems + mixes
bash transcribe.sh song.mp3 "song" --fast          # vocals + accompaniment
bash transcribe.sh song.mp3 "song" --keep-work     # keep WAV stems
bash transcribe.sh song.mp3 "song" --key-shift 2   # transpose up
bash transcribe.sh song.mp3 "song" --tempo 0.95    # slow down
```

## Cleanup

```bash
# List output folders with sizes
bash cleanup.sh

# Delete work directories only
bash cleanup.sh --work

# Purge uv/pip caches
bash cleanup.sh --caches

# Delete all files for one song
bash cleanup.sh --delete "my-song"

# Work dirs + caches
bash cleanup.sh --all
```

## Troubleshooting

- **"Only X GB free"** — Run `bash cleanup.sh --all` or free disk space.
- **yt-dlp fails** — The script tries to update it automatically. Manually:
  `uv pip install -U yt-dlp --python ~/venvs/demucs/bin/python`
- **Demucs OOM** — Use `--fast`, or let `--segment 7` activate for tracks > 6 min.
- **"Output folder was created with different settings"** — Use a different
  `<name>`, or delete `~/transcribe/output/<name>` and rerun.
- **"ffmpeg is missing the 'rubberband' filter"** — Install an ffmpeg built with
  librubberband, or skip `--key-shift`.
- **Demucs venv missing** — Run `bash install.sh`.
- **YouTube links need network access** and a current `yt-dlp`.

## Files

| File | Purpose |
|------|---------|
| `install.sh` | One-time setup (CPU PyTorch + Demucs) |
| `transcribe.sh` | Main stem-separation entry point |
| `cleanup.sh` | Disk management utility |
| `CONTRIBUTING.md` | Contribution and PR guide |
| `LICENSE` | MIT license |

## Contributing

Bug fixes, audio-processing improvements, and documentation updates are welcome.
Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a PR. The project is
strictly audio-only: contributions for sheet music, PDF/MIDI generation, lyrics,
MuseScore, basic-pitch, or Whisper are out of scope. PRs are checked with
`bash -n` and ShellCheck in CI.

## License

MIT. See `LICENSE`.
