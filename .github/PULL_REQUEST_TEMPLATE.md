<!-- Thanks for contributing! Please fill in the sections below. -->

## Summary

<!-- What does this PR change and why? Link related issues: Fixes #123 -->

## Platform

- [ ] iOS
- [ ] Android
- [ ] JavaScript / TypeScript
- [ ] Docs / CI only

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change (describe migration below)
- [ ] Refactor / chore

## How was this tested?

<!--
e.g. "Ran example app on iPhone 15 / iOS 18.1, backgrounded for 10 min, confirmed
GPS powered down after stopTimeout" or "yarn typecheck && yarn lint".
For Location Push changes, mention whether you tested app-alive and force-quit paths.
-->

## Checklist

- [ ] `yarn typecheck` and `yarn lint` pass
- [ ] New config keys / methods are added to `src/types.ts`, `src/NativeBgGeolocation.ts`, **and** have an Android override in `BgGeolocationModule.kt`
- [ ] README updated if behaviour or API changed
- [ ] `CHANGELOG.md` `[Unreleased]` section updated
