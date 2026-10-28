# Cred Vault for iOS

A native SwiftUI client for the VPS credential vault (`~/cred-vault` on the server).

Not a webview. Every screen is native, and the app talks to the vault's JSON API
directly over the WireGuard tunnel.

## What it does

- **Unlock** with the vault passcode. The passcode is sent to the server, which derives
  the AES-256-GCM key. The app never stores it and never keeps a derived key.
- **Browse** credentials with search across service, username, URL, notes and tags, plus a
  VPS / External category filter.
- **Reveal** a password on demand, or copy it to the clipboard with a 60-second expiry.
- **Add / edit / delete** entries. Editing fetches the stored secret first, because the
  server's `upsert` always writes the password field — saving blind would erase it.
- **Generate** strong passwords server-side (`POST /api/password/generate`), so the
  generator rules stay in one place.
- **Change passcode**, which re-encrypts the vault in place with a fresh salt.
- **Lock now**, which logs out server-side and drops the session cookie.

## Security model

| Concern | Handling |
|---|---|
| Passcode at rest | Never stored on the device. Sent once per unlock. |
| Session | HttpOnly `cv_session` cookie in URLSession's shared cookie storage. |
| CSRF | Every mutating POST sends `X-CSRF-Token` from `GET /api/state`. |
| Lockout | Server-side, global, file-backed. The UI shows the countdown and disables unlock. |
| Clipboard | 60-second pasteboard expiry via `UIPasteboard.setItems(options:)`. |
| Transport | ATS allows HTTP because the vault binds a WireGuard address (`10.200.200.1:8791`). |

The app trusts the configured host only in the sense that ATS is open; it does not
pin certificates. Treat the WireGuard tunnel as the transport security boundary.

## API surface used

| Method | Path | Notes |
|---|---|---|
| GET | `/api/state` | `csrf`, `authed`, `locked_until`, `attempts_left`, `count` |
| GET | `/api/entries` | session required; never includes passwords |
| POST | `/api/auth/login` | `{passcode}` → sets `cv_session` cookie |
| POST | `/api/auth/logout` | clears the session |
| POST | `/api/entries/reveal` | `{id}` → `{password}` |
| POST | `/api/entries/save` | `{id?, service, username, password, url, notes, category?, tags?}` |
| POST | `/api/entries/delete` | `{id}` |
| POST | `/api/password/generate` | `{length}` |
| POST | `/api/passcode` | `{current, new, confirm}` |

All POSTs except login/logout require the CSRF token.

## Build

Built as an unsigned IPA by [Jeho974/ipa-build-template](https://github.com/Jeho974/ipa-build-template)
on GitHub Actions macOS runners. Push to `main` or run the "Build IPA" workflow.

Install the resulting `.ipa` through BuildBox (Sign tab) or SideStore.

## Limits

- The server must already be initialised. First-run vault setup is not implemented in the
  app; do that on the server.
- The vault binds `10.200.200.1` only, so the phone must be on the WireGuard tunnel (or you
  point the app at a reverse proxy).
- Unsigned IPAs cannot use push notifications, app groups or associated domains; none are
  needed here.
