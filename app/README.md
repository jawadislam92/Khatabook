# Duebook app

Flutter app for Android (iOS later). See the repository root for the plan.

## Run it

Preview mode, no server, in memory data (what the screenshots use):

```
flutter run
```

Against a Supabase project:

```
flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ...
```

## Check it

```
flutter gen-l10n
dart format lib test
flutter analyze --fatal-infos
flutter test
```

## Layout

```
lib/
  app.dart                 MaterialApp, theme, locale, simple mode text scaling
  main.dart                bootstrap
  core/
    config/                build time config from --dart-define
    theme/                 design tokens and theme builder
    settings/              persisted preferences (language, simple mode, lock)
    security/              PIN hashing, secure storage, app lock lifecycle
    router/                go_router with onboarding, auth, PIN and lock gates
    utils/                 money formatting, number to words
    widgets/               shared widgets (big button, choice card, number pad)
  features/
    onboarding/  auth/  lock/  spaces/  settings/
  l10n/                    app_en.arb, app_ur.arb (generated Dart is not committed)
test/                      unit and widget tests
```

## Android notes

- Package name `com.sparkingasia.duebook`. Change it in `android/app/build.gradle.kts`, the manifest intent filter, `AppConfig.authRedirect` and the Supabase redirect list together.
- Release signing reads `android/key.properties`, which CI creates from secrets. It is never committed.
- Release builds are minified and obfuscated. Cloud backup of app data is turned off.

## Building the APK on the cloud machine

Android SDK command line tools install under the session scratchpad and Flutter is pointed at them with `flutter config --android-sdk`. Maven Central rate limits that network, so `~/.gradle/init.d/maven-mirror.gradle` redirects it to Google's mirror (`maven-central.storage-download.googleapis.com`). GitHub Actions does not need the mirror.

Two useful builds:

```
# preview, no server, sample data
flutter build apk --debug

# connected to the dev project, push enabled (needs android/app/google-services.json)
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://jepcsftdjejjzhfjnavy.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=sb_publishable_oTLjMBC0q95QkO2UrJEaSg_-IkMyi0C \
  --dart-define=FIREBASE_ENABLED=true
```

Without `android/key.properties` the release build is signed with the debug key, which is fine for testing and wrong for the Play Store.
