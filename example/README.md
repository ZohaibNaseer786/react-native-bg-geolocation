# React Native BG Geolocation Example

This app demonstrates foreground, background, headless Android, and iOS
Location Push Service Extension delivery.

## Configure

Edit `src/exampleConfig.ts` and replace the public placeholders with your own:

- backend base URL
- authentication token
- app bundle identifier
- socket and REST endpoint paths

Never commit production credentials to this example.

### iOS Signing

The checked-in project uses public example identifiers and no Apple Team ID.
Configure your own values before running on a physical device:

```sh
cd ios
APPLE_DEVELOPMENT_TEAM=YOUR_TEAM_ID \
BG_GEO_APP_BUNDLE_ID=com.yourcompany.bggeolocation.example \
BG_GEO_APP_GROUP=group.com.yourcompany.bggeolocation.example \
ruby add_location_push_target.rb
```

Set the same App Group in:

- `BgGeolocationExample/BgGeolocationExample.entitlements`
- `LocationPushExtension/LocationPushExtension.entitlements`
- `BGLocationPushAppGroupIdentifier` in both target `Info.plist` files

Location Push also requires Apple approval for the
`com.apple.developer.location.push` entitlement.

## Run

From the repository root:

```sh
yarn install
cd example/ios && bundle exec pod install && cd ../..
yarn example start
```

In another terminal:

```sh
yarn example ios
# or
yarn example android
```
