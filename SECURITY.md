# Security Policy

## Supported versions

Only the latest published minor release receives security fixes.

| Version | Supported |
|---|---|
| 0.2.x | ✅ |
| < 0.2 | ❌ |

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security problems.

Report privately through GitHub's
[private vulnerability reporting](https://github.com/ZohaibNaseer786/react-native-bg-geolocation/security/advisories/new)
for this repository, or email **zohaibnaseer2244@gmail.com** with the subject
`[SECURITY] react-native-bg-geolocation`.

Include:

- affected version(s) and platform (iOS / Android),
- a description of the issue and its impact,
- steps or a minimal project to reproduce.

You can expect an acknowledgement within **72 hours** and a fix or mitigation
plan within **14 days** for confirmed issues. Credit is given in the release
notes unless you prefer to stay anonymous.

## Scope notes

This library moves device location to servers you control. Things that are
**in scope**:

- native delivery code (`ios/locationpush/*`, Android HTTP/socket upload) leaking
  data to unintended hosts, failing to apply configured headers/auth, or
  logging secrets;
- App Group / UserDefaults storage exposing tokens to other processes;
- payload-template injection allowing arbitrary keys or values.

**Out of scope**: misconfiguration of your own backend, APNs or FCM credentials,
and the security of third-party services you deliver to.
