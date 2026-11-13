# LocalSend iOS Plus

A native SwiftUI iOS client for [LocalSend](https://github.com/localsend/localsend), built around the
iOS 26 Liquid Glass material (`glassEffect`, with an `ultraThinMaterial` fallback for older SDKs).

The point of this project is the UI: everything is rendered by SwiftUI/UIKit, so cards, sheets, buttons
and the tab bar are real system surfaces that the compositor can blur and refract — something a Flutter
app cannot do, because Flutter draws all of its widgets into a single texture.

The protocol side is a from-scratch implementation of the LocalSend **v2** HTTP/TLS API, so the app
talks to the official Flutter app, to LocalSend desktop and to other LocalSend clients on the same LAN.

## Build

```bash
brew install xcodegen     # once
cd LocalSend-iOS-Plus
xcodegen generate
open LocalSendNative.xcodeproj
```

- Xcode 26 SDK required for `UIGlassEffect` / `glassEffect`. On an older SDK, delete the
  `#available(iOS 26.0, *)` branch in `Sources/UI/Glass.swift` and the material fallback takes over.
- Deployment target: iOS 18. Runs on iPhone (portrait).
- App Group `group.org.localsend.native` is shared by the app and the share extension.

## What it does

| Area | State |
| --- | --- |
| Receive over HTTP/HTTPS (v2) | ✅ `GET /info`, `POST /register`, `POST /prepare-upload`, `POST /upload`, `POST /cancel` |
| Encryption | ✅ RSA-2048 self-signed certificate, mTLS in both directions, fingerprint = SHA-256 of the DER |
| PIN | ✅ `pin` query parameter, 401 / 429 semantics, prompt on the sending side |
| Approval | ✅ sheet with per-file checkboxes, decline returns 204, 409 while another session is live |
| Received files | ✅ `Documents/LocalSend`, share sheet, optional save to Photos |
| Discovery | ✅ `/24` probe against `GET /info` on port 53317 (https first, then http) |
| Favourites | ✅ manual `alias + host` entries, persisted |
| History | ✅ sent/received, persisted, swipe to delete |
| Web download page | ✅ `GET /` plus `POST /prepare-download` + `GET /download` (PIN gated) |
| Share extension | ✅ Files/Photos → app inbox → select and send |
| QR pairing | ✅ show a pairing code on Receive, scan one on Send |
| Liquid Glass | ✅ every surface, `glassEffect` on iOS 26 |

## Not there yet

These are tracked, not hidden:

- **Multicast announce** (`224.0.0.167:53317`). iOS refuses UDP multicast without the
  `com.apple.developer.networking.multicast` entitlement, so discovery uses a subnet probe instead.
  The probe finds multicast peers too, but it does not answer *their* announcements.
- **Localisation.** Strings are English only; the Flutter app ships ~40 languages from
  `app/assets/i18n`. Porting them means generating an `.xcstrings` catalog.
- **Receive options / device details screens.** Defaults are applied directly (auto-accept when
  Quick Save is on) instead of the Flutter app's options sheet, and device details are not shown.
- **Legacy WebRTC path.** LocalSend v1 could fall back to WebRTC; this client speaks HTTP/TLS only,
  like the current Flutter app.

## Layout

```
Sources/
  Core/      protocol: HTTP server, TLS, identity, discovery, sender, stores
  App/       AppModel, entry point
  UI/        SwiftUI screens and the glass primitives
  Resources/ Info.plist, entitlements
ShareExtension/
project.yml  XcodeGen spec
```

## Glass

```swift
extension View {
  @ViewBuilder
  func glassPanel(cornerRadius: CGFloat = 26, interactive: Bool = false) -> some View {
    if #available(iOS 26.0, *) {
      self.glassEffect(interactive ? .regular.interactive() : .regular,
                       in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    } else {
      self.background(.ultraThinMaterial,
                      in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
  }
}
```

## Compatibility

- Peers must accept plain HTTP on 53317 when encryption is off, and HTTPS with a self-signed
  certificate when it is on. Both are LocalSend defaults.
- iOS asks for Local Network permission on first launch — without it discovery and transfers fail.

## Licence

Apache-2.0, same as LocalSend. This is an independent client; the protocol design and the
LocalSend name belong to the LocalSend project.
