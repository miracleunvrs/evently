# Evently for iOS

`Evently/Evently.xcodeproj` is a native SwiftUI app for iPhone and iPad (iOS 17+). It uses the Evently Rails API directly and has no embedded website or WebView. The default API is `https://evently-api-production-1056.up.railway.app`, so the app does not require the Mac to run.

The app currently includes a searchable event catalogue, event details, sign-in and registration (email or Google), favorites, existing ticket display with native QR generation, waitlist, profile, organizer event list and stats, draft creation, and an admin overview. Auth tokens are stored in the iOS Keychain. Event cover images are bundled as native assets.

Open the Xcode project, select your Apple Development team and device, then press Run. The local `ios/Local.xcconfig` file can hold a personal `DEVELOPMENT_TEAM` and optional `EVENTLY_API_URL` override; it is ignored by Git. The API URL can also be changed in Profile → API address. Only HTTPS or private-network HTTP addresses are accepted.

## Google sign-in

The app signs in with Google through the system browser sheet (`ASWebAuthenticationSession`, OAuth code flow with PKCE, no SDK) and exchanges the Google ID token at `POST /auth/google`. It needs one OAuth client:

1. Google Cloud Console → APIs & Services → Credentials → Create credentials → OAuth client ID → Application type **iOS**, bundle ID `com.miracleunvrs.evently`.
2. Put the client ID into `GOOGLE_IOS_CLIENT_ID` in `ios/Local.xcconfig` (or `Evently/Config.xcconfig`) and rebuild.
3. The API accepts the app's client ID by default (`Auth::GoogleIdToken::IOS_CLIENT_ID`); set `GOOGLE_CLIENT_IDS` (comma-separated) to allow a different list.

Without the client ID the button reports that Google sign-in is not configured; with an empty `GOOGLE_CLIENT_IDS` the API answers `503 google_not_configured`.

```sh
xcodebuild -project ios/Evently/Evently.xcodeproj -scheme Evently \
  -configuration Debug -destination 'id=DEVICE_UDID' -derivedDataPath ios/build \
  DEVELOPMENT_TEAM=YOUR_TEAM -allowProvisioningUpdates build
xcrun devicectl device install app --device DEVICE_UDID ios/build/Build/Products/Debug-iphoneos/Evently.app
xcrun devicectl device process launch --device DEVICE_UDID com.miracleunvrs.evently
```

New Web3 ticket registration and blockchain check-in require native Phantom signing. They are not enabled in this build. The app only shows a QR for a ticket whose `blockchain_status` is `confirmed`; it does not generate unverified passes. Invitation design, event publishing, and the full organizer workflow remain in the web product while the native client is developed. A Development-signed build may require trusting the developer profile under iPhone Settings → General → VPN & Device Management, and the personal provisioning profile expires after seven days.
