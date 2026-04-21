# CarPlay Strategy

## Why this structure

- `CPNowPlayingTemplate` is the Apple-compliant template for playback controls in audio apps.
- `CPListTemplate` is used for lightweight context ("lyrics status", shortcuts, explanatory info).
- `CPInformationTemplate` is intentionally not used because it is restricted for audio-entitled apps.

## UX rule for lyrics

CarPlay should display brief and low-distraction text. Full karaoke-style scrolling must remain on iPhone.
