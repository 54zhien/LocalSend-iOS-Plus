# LocalSend+

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
open LocalSendPlus.xcodeproj
```

- Xcode 26 SDK required for `UIGlassEffect` / `glassEffect`. On an older SDK, delete the
  `#available(iOS 26.0, *)` branch in `Sources/UI/Glass.swift` and the material fallback takes over.
- Deployment target: iOS 18. Runs on iPhone (portrait).
- App Group `group.com.imzhien.localsendplus` is shared by the app and the share extension.

## What it does

| Area | State |
| --- | --- |
| Receive over HTTP/HTTPS (v2) | ✅ `GET /info`, `POST /register`, `POST /prepare-upload`, `POST /upload`, `POST /cancel` |
| Encryption | ✅ RSA-2048 self-signed certificate, mTLS in both directions, fingerprint = SHA-256 of the DER |
| PIN | ✅ `pin` query parameter, 401 / 429 semantics, prompt on the sending side |
| Approval | ✅ sheet with per-file checkboxes, decline returns 204, 409 while another session is live |
| Received files | ✅ `Documents/LocalSend`, share sheet, optional save to Photos |
| Discovery | ✅ `/24` probe against `GET /info` (https first, then http) **plus a unicast UDP announce** every 30 s, so peers list this device without waiting |
| Favourites | ✅ manual `alias + host` entries, persisted |
| History | ✅ sent/received, persisted, swipe to delete |
| Web download page | ✅ `GET /` plus `POST /prepare-download` + `GET /download` (PIN gated) |
| Share extension | ✅ Files/Photos → app inbox → select and send |
| QR pairing | ✅ show a pairing code on Receive, scan one on Send |
| Localisation | ✅ 32 UI strings × 58 languages, generated from the upstream i18n JSON |
| Quick save modes | ✅ off / always / favourites only, plus auto finish |
| Device details | ✅ long-press a device for details, favourite toggle, send |
| Liquid Glass | ✅ every surface, `glassEffect` on iOS 26 |

## Not there yet

These are tracked, not hidden:

- **Multicast announce to `224.0.0.167`.** Sending to that group needs Apple's
  `com.apple.developer.networking.multicast` entitlement (a request form, not a build setting).
  The same JSON is therefore sent to every host in the subnet as a *unicast* datagram, which needs
  no entitlement and produces the same effect on the receiving side. What still differs: we cannot
  *join* the group, so peers' multicast announcements reach us only through the /24 probe.
- **Multicast announce, continued.** Peers find us through the probe and through manual add / QR,
  but we never send an announcement of our own.
- **WebRTC transport.** Upstream keeps an experimental WebRTC path behind a Cargo feature and a
  `sqlite`/signaling provider. Only the HTTP/TLS transport is implemented here; transfers between
  this app and the Flutter app use HTTP, which is what upstream falls back to as well.
- **Receive destination.** Choose any folder (stored as a security-scoped bookmark); the default is
  `Documents/LocalSend`.
- **Only the strings that exist in the UI are translated.** New UI text needs an entry in
  `tools/strings.json`; CI fails when `Resources/Localizable.xcstrings` is stale.

## Three things that will bite you

Each of these shipped as a bug, and each one looked like a network problem while it was
happening. They are written down so the next reader does not re-derive them.

- **A listener cannot be restarted on the same tick.** `NWListener.cancel()` releases the socket
  asynchronously, so `stop()` immediately followed by `start()` fails with `EADDRINUSE (48)`, and a
  retry loop burns every attempt the same way. `AppModel.rebindServer()` waits 350 ms between the
  two calls, and any path that only wants fresh interfaces (foreground resume, pull to refresh)
  reuses the running listener instead of rebinding it.
- **iOS takes the listening socket away in the background.** The app keeps a short
  `beginBackgroundTask` grace period, and on `scenePhase == .active` it rebinds if the listener
  died, then restarts discovery and announcing. Without that the app returns to the foreground
  looking healthy while no peer can reach it.
- **A connection has to be retained, not just started.** `HTTPConnection.receive()` captures `self`
  weakly, so a handler that only does `HTTPConnection(...).start()` frees the object immediately:
  the TLS handshake completes at the Networking layer, the request is never read, and the peer
  waits until it times out. `LocalHTTPServer` keeps live connections in `connections` and drops
  them from `HTTPConnection.onClose`.

## Localisation

`Resources/i18n/*.json` are copied verbatim from upstream. `tools/strings.json` maps each English
literal in the views to its upstream key, and `node tools/gen_strings.mjs` regenerates
`Resources/Localizable.xcstrings` (SwiftUI treats a plain literal as a `LocalizedStringKey`, so no
view code needs to change). The CI workflow re-runs the generator and fails on drift.

## Layout

```
Sources/
  Core/      protocol: HTTP server, TLS, identity, discovery, sender, stores
  Resources/ i18n JSON + generated Localizable.xcstrings
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
