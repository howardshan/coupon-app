# Firebase on iOS (FCM)

The consumer app (`deal_joy`) calls `Firebase.initializeApp()` in `lib/main.dart`. On **iOS**, Firebase needs `**GoogleService-Info.plist`** in the Xcode Runner target.

## Steps

1. Open [Firebase Console](https://console.firebase.google.com/) → your project.
2. Add an **iOS app** with the **same Bundle ID** as in Xcode (`Runner` → *General* → *Bundle Identifier*, e.g. `com.crunchyplum.crunchyPlum`).
3. Download `**GoogleService-Info.plist`**.
4. Place the file at `**ios/Runner/GoogleService-Info.plist`** (next to `Info.plist`).
5. In Xcode, open `**ios/Runner.xcworkspace`** → select **Runner** → *Build Phases* → *Copy Bundle Resources* → ensure `GoogleService-Info.plist` is listed (Flutter usually picks it up automatically once the file is in `Runner/`).
6. Run `**flutter clean`** then `**flutter run`** on a device or simulator.

If the plist is missing, Firebase init may fail at runtime; the app catches errors and continues without push (`main.dart`).

## Security

Treat `GoogleService-Info.plist` like client configuration: it is often committed to private repos. Do **not** confuse it with server secrets.

The **merchant app** (`dealjoy_merchant`) does not depend on Firebase; no plist is required there unless you add Firebase later.