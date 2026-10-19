## Summary

<!-- What does this PR change and why? -->

## Related issue

<!-- Link the issue or discussion, if any. -->

## Type of change

- [ ] Bug fix
- [ ] New audio-processing feature
- [ ] Performance / reliability
- [ ] Documentation
- [ ] Refactor (no behavior change)

## Changes

<!-- Bullet the important implementation details. -->

## Testing

<!-- Include commands and results. -->

- [ ] `bash -n install.sh transcribe.sh cleanup.sh`
- [ ] `shellcheck install.sh transcribe.sh cleanup.sh`
- [ ] Full separation produces all expected MP3s
- [ ] `--fast` produces vocals + instrumental
- [ ] `--key-shift` / `--tempo` outputs stay aligned
- [ ] Resume and changed-settings behavior checked
- [ ] `cleanup.sh` safe-delete behavior checked
- [ ] 320 kbps and duration verified with `ffprobe`

## Scope checklist

- [ ] This PR stays audio-only (no sheet music, PDF, MIDI, MuseScore, lyrics,
      basic-pitch, or Whisper)
- [ ] No copyrighted audio, stems, PDFs, or other binary assets are committed
- [ ] README/help updated for user-facing changes
- [ ] Output filenames and existing CLI behavior remain compatible, or the
      breaking change is described below
- [ ] CPU-only and the ~4 GB install budget are respected

## Breaking changes

<!-- None, or describe what users must change. -->
