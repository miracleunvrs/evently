# Evently for iOS

`Evently/Evently.xcodeproj` is a native SwiftUI app for iPhone and iPad (iOS 17+). It uses the Evently Rails API directly and has no embedded website or WebView. The default API is `https://evently-api-production-1056.up.railway.app`, so the app does not require the Mac to run.

The app includes a searchable event catalogue, event details, sign-in and registration (email or Google), favorites, the waitlist, profile, organizer event list with stats and guests, draft creation, and an admin overview. Tickets are real: the app connects Phantom, mints the non-transferable Token-2022 ticket on Solana Devnet and shows its QR, and organizers check guests in by QR scan or code. Auth tokens and the Phantom session are stored in the iOS Keychain. Event cover images are bundled as native assets.

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

## Phantom and Solana

The app talks to Phantom through its deeplinks (`https://phantom.app/ul/v1/…`) and receives the answers on the `evently://phantom/…` URL scheme. Nothing is embedded: no WebView and no SDK.

- `SolanaKit.swift` — Base58, NaCl box (X25519 + XSalsa20-Poly1305, the encryption Phantom deeplinks use), the Ed25519 curve check for program-derived addresses, transaction serialization, and the two Evently transactions: the ticket mint (same instructions as `lib/web3.ts`) and the check-in memo.
- `PhantomLink.swift` — the deeplink protocol (connect, signMessage, signTransaction) and the Solana JSON-RPC calls. Phantom only signs: the app submits transactions to Devnet itself, because Phantom has deprecated `signAndSendTransaction` for deeplinks.
- `Wallet.swift` — `WalletCoordinator`, which runs each round trip. The step in flight is stored in the Keychain, so an answer is finished correctly even if iOS restarted the app while the user was in Phantom.

What the user needs: the Phantom app and about 0.005 Devnet SOL for the mint. Testnet Mode (Solana Devnet) should be on in Phantom so it previews transactions correctly; if Phantom answers a Devnet connection with its internal error, the app offers to reconnect without the cluster and carries on.

Other notes: a check-in costs the organizer one transaction fee. Connecting takes two visits to Phantom the first time: approve the connection, then sign a free message that proves the wallet is theirs.

### Tests

```sh
sh ios/Tests/run.sh                                           # 500 checks, no network
python3 ios/Tests/simulate-devnet.py <funded devnet address>  # runs the ticket transaction on Devnet without sending it
```

`run.sh` compiles `SolanaKit.swift` and `PhantomLink.swift` for macOS and checks them against `vectors.json`: Base58, curve points and associated token addresses from `@solana/web3.js`, NaCl box from libsodium, and both transactions, which `@solana/web3.js` then parses again. `simulate-devnet.py` asks the cluster to execute the ticket transaction with signature checks off and applies the same checks the Rails API makes (Token-2022, non-transferable, supply of one, authority removed, owner holds it, memo).

Phantom cannot be installed in the Simulator. `fake-phantom.rb` is a stand-in wallet that answers the same deeplink requests over HTTP using libsodium; a Simulator build started with `EVENTLY_TEST_WALLET` uses it instead of opening Phantom (see the header of that file, including the mock-chain mode for when no test SOL is available). These hooks, and sign-in through `EVENTLY_TEST_EMAIL`/`EVENTLY_TEST_PASSWORD`, are compiled into Simulator builds only.

Invitation design, event publishing, and the full organizer workflow remain in the web product. A Development-signed build may require trusting the developer profile under iPhone Settings → General → VPN & Device Management, and the personal provisioning profile expires after seven days.
