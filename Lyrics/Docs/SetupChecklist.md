# Setup Checklist

## 1) Spotify Developer Dashboard

1. Create an app in Spotify for Developers.
2. Copy the `Client ID`.
3. Add callback URI: `lyricscar://spotify-auth-callback`.
4. Paste `Client ID` in `Resources/Info.plist` under `SPOTIFY_CLIENT_ID`.
5. Request scopes:
   - `user-read-currently-playing`
   - `user-read-playback-state`
   - `user-modify-playback-state`
6. Keep the app in test mode with approved test users until release.

## 2) Apple Developer + Entitlements

1. Enable CarPlay Audio capability for the App ID (requires Apple approval).
2. Ensure provisioning profile includes `com.apple.developer.carplay-audio`.
3. In Xcode, verify `Signing & Capabilities` includes:
   - CarPlay Audio App
   - Background Modes -> Audio

## 3) Dependencies (SPM)

Add these packages from Xcode (`File > Add Packages...`):

- `https://github.com/p2/OAuth2.git`
- `https://github.com/kishikawakatsumi/KeychainAccess.git`
- `https://github.com/onevcat/Kingfisher.git` (optional for artwork caching)

## 4) CarPlay Template Strategy

- Use `CPNowPlayingTemplate` for playback controls and system now playing.
- Use `CPListTemplate` for lightweight lyrics-related navigation/status.
- Avoid `CPInformationTemplate` in audio entitlement apps.
