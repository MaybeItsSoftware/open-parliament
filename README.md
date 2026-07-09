# Open Parliament
Mobile app for easily reading UK Parliamentary Debates taken verbatim from Hansard

## Getting started

```bash
cp .env.example .env   # required: app reads .env as a bundled asset on startup
flutter pub get
flutter run
```

See [AGENTS.md](./AGENTS.md) for architecture, conventions, and testing guidance.

## Running on iOS & Android Emulators

Before running on emulators or simulators, ensure your development environment is set up correctly by running:
```bash
flutter doctor
```

### iOS Simulator (macOS only)

1. Make sure you have **Xcode** installed.
2. Start the Simulator:
   ```bash
   open -a Simulator
   ```
3. Run the app:
   ```bash
   flutter run
   ```
   *(If you have multiple devices connected/running, use `flutter run -d iphonesimulator` to target the simulator).*

### Android Emulator

1. Make sure you have **Android Studio** installed and have created an Android Virtual Device (AVD) using the Device Manager.
2. Start the emulator. You can do this via Android Studio, or via the command line:
   ```bash
   # List available AVDs
   emulator -list-avds

   # Start the emulator (replace <AVD_NAME> with your AVD name)
   emulator -avd <AVD_NAME>
   ```
   *(Note: The `emulator` command is located inside your Android SDK directory, e.g., `~/Library/Android/sdk/emulator` on macOS. You may need to add it to your PATH).*
3. Run the app:
   ```bash
   flutter run
   ```
   *(If you have multiple devices running, use `flutter run -d emulator-5554` or choose the target device from the prompt).*

## Building for Production / Releases

While the production focus of this project is mobile (iOS and Android), Flutter compiles to desktop and web targets for development and testing.

### iOS (Apple devices)

To build a release package (`.ipa`) for iOS:
```bash
# Generates build/ios/archive/Runner.xcarchive and Runner.ipa
flutter build ipa --release
```
*Note: Building for iOS requires a macOS machine with Xcode installed and configured with active developer certificates/provisioning profiles.*

#### Automated Build & Deploy (via Fastlane)
You can automate the build and upload to TestFlight (Internal/External) using:
```bash
# Requires BUILD_NUMBER env var
BUILD_NUMBER=123 bundle exec fastlane ios beta
```

---

### Android (Google Play / Sideloading)

#### 1. Android App Bundle (.aab) - Recommended for Google Play Console
```bash
flutter build appbundle --release
```

#### 2. APK (.apk) - For direct installation and sharing
```bash
# Build a single "fat" APK with all architectures
flutter build apk --release

# Build separate APKs split by target ABI (reduces download size)
flutter build apk --release --split-per-abi
```

#### Automated Build & Deploy (via Fastlane)
To build and upload to Google Play internal and closed (alpha) tracks:
```bash
# Requires BUILD_NUMBER env var
BUILD_NUMBER=123 bundle exec fastlane android beta
```

---

### Web & Desktop (Development/Testing)

To build web or desktop apps for fast iteration or local verification:
```bash
# Web
flutter build web --release

# macOS (requires Xcode)
flutter build macos --release

# Windows (requires Visual Studio with C++ workload)
flutter build windows --release

# Linux (requires build-essential, clang, cmake, ninja-build, libgtk-3-dev)
flutter build linux --release
```
