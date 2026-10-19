# Contributing

Thanks for helping improve **Audio Stem Separator**. This project turns a song
into audio stems and mixes only. Contributions are welcome for bug fixes,
performance, reliability, documentation, and new audio-processing features.

## Project scope

Please keep the project focused:

- **In scope:** stem separation, audio mixing, YouTube/local input, CPU
  performance, resumable runs, cleanup, key/tempo processing, docs.
- **Out of scope:** sheet music, PDF/MIDI/MusicXML generation, MuseScore,
  basic-pitch, lyrics, Whisper, title/score layout, or scoring dependencies.
- **CPU only:** do not add mandatory CUDA/GPU dependencies.
- **Small footprint:** keep the Demucs venv under the ~4 GB target and avoid
  heavy dependencies unless they are essential.

If a feature is large or changes the CLI/output contract, open an issue first
so it can be discussed before implementation.

## Before you start

1. Search existing issues and pull requests.
2. For a bug, include a minimal reproduction (command + short log).
3. For a large feature, open an issue describing:
   - the use case
   - expected behavior
   - effect on CPU time, RAM, and disk
   - whether output filenames or CLI flags change

Small documentation fixes and obvious one-line bugs can go straight to a PR.

## Development setup

```bash
git clone https://github.com/<owner>/<repo>.git
cd <repo>
bash install.sh
```

Requirements: Ubuntu, `ffmpeg` with `amix`/`alimiter`/`atempo`/`rubberband`,
`yt-dlp`, `uv`, and Python 3.11.

Create a short test file without committing copyrighted audio:

```bash
ffmpeg -f lavfi -i "sine=frequency=440:duration=10" \
  -c:a libmp3lame -b:a 192k /tmp/test-tone.mp3
```

Run against an isolated project root so your real outputs are untouched:

```bash
TRANSCRIBE_ROOT=/tmp/transcriber-dev bash transcribe.sh \
  /tmp/test-tone.mp3 tone --fast --keep-work
```

Inspect the result:

```bash
ls -lh /tmp/transcriber-dev/output/tone/
ffprobe -v error -show_entries format=duration,bit_rate \
  -of csv=p=0 /tmp/transcriber-dev/output/tone/tone-vocals.mp3
```

## Project layout

| File | Purpose |
|------|---------|
| `transcribe.sh` | Main stem-separation pipeline |
| `install.sh` | One-time CPU Demucs setup |
| `cleanup.sh` | Work/output/cache cleanup |
| `README.md` | User documentation |
| `CONTRIBUTING.md` | This guide |

There is no Python application code; the pipeline is Bash + FFmpeg + Demucs.

## Coding guidelines

- Keep `set -euo pipefail` in every shell script.
- Quote variables and use arrays for command arguments.
- Use `local` in functions and return non-zero on failure.
- Do not use `eval` or build shell commands from untrusted input.
- Validate user-supplied names and paths; never delete outside
  `~/transcribe/work` and `~/transcribe/output` (or the configured project
  root).
- Keep output filenames stable:
  - `<name>-vocals.mp3`
  - `<name>-drums.mp3`
  - `<name>-bass.mp3`
  - `<name>-other.mp3`
  - `<name>-instrumental.mp3`
  - `<name>-no-bass.mp3`
  - `<name>-no-drums.mp3`
- Fast mode must keep `<name>-vocals.mp3` and `<name>-instrumental.mp3`.
- Keep the audio at **320 kbps MP3** unless the PR explains why not.
- Respect the settings guard (`.transcribe-params`) and resume behavior.
- Update `README.md` when behavior, options, outputs, or requirements change.
- Add dependencies only when necessary; update `install.sh`, pin CPU-only torch
  packages, and explain the disk/time cost in the PR.

## Testing checklist

Run these before opening a PR.

```bash
bash -n install.sh transcribe.sh cleanup.sh

# if shellcheck is installed
shellcheck install.sh transcribe.sh cleanup.sh
```

Then verify:

- [ ] Full separation creates all seven MP3s.
- [ ] `--fast` creates only vocals + instrumental.
- [ ] Output durations match the source (and tempo factor when `--tempo` is used).
- [ ] MP3s are 320 kbps.
- [ ] `--key-shift` and `--tempo` stay aligned across stems/mixes.
- [ ] A rerun resumes instead of re-running Demucs.
- [ ] Changing input/settings with existing outputs stops with a clear message.
- [ ] `--keep-work` preserves WAV stems; without it the work folder is removed.
- [ ] Song names and paths containing spaces work.
- [ ] `cleanup.sh --delete <name>` does not accept `../`, `.`, or `..` names.
- [ ] No audio, score, PDF, or generated output assets are staged for commit.

## Reporting bugs

Include:

- OS and Python/ffmpeg/Demucs versions
- the exact command
- whether the input was local or YouTube
- the last ~30 lines of output, including the error
- expected vs actual duration/files
- a short, rights-cleared audio sample if the bug depends on the audio
  (do **not** attach copyrighted songs)

## Commit and PR workflow

1. Create a branch:

   ```bash
   git checkout -b fix/resume-settings
   # or: feature/two-stem-mix, docs/readme
   ```

2. Make a focused change; avoid unrelated formatting churn.
3. Run the checklist above.
4. Commit with an imperative, descriptive message:

   ```text
   fix: reject unsafe cleanup delete names
   feat: add --fast two-stem mode
   docs: explain resume behavior
   ```

5. Rebase on the latest `main` if needed.
6. Open a pull request and fill in the PR template:
   - summary of the change
   - why it is needed
   - testing performed
   - breaking changes
   - related issue

Do not commit generated audio, WAV stems, MP3s, PDFs, score files, clips, or
large binary assets. `.gitignore` already excludes these, but check `git status`
before committing.

## Review

Maintainers may ask for changes for correctness, performance, disk usage, or
scope. Keep discussions technical and respectful. Harassment or hostile
behavior is not welcome.

## License

By submitting a contribution you agree that it may be distributed under the
project's [MIT License](LICENSE).
