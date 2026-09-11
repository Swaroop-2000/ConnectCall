# ConnectCall 📞

A cross-platform audio and video calling application built with Flutter, powered by Firebase and WebRTC. ConnectCall supports real-time presence, push notifications, and seamless peer-to-peer video streaming on both Mobile and Web platforms.

## ✨ Features
* **User Authentication**: Secure Login, Registration, and Password Reset using Firebase Auth.
* **Real-time Presence System**: Live "Online/Offline" indicators that accurately track user presence based on app lifecycle states.
* **WebRTC Calling**: High-quality, low-latency audio and video calls.
* **Global Contacts & Recent History**: Searchable global contacts list and a scrubbed recent callers carousel.
* **Incoming Call UI**: Dedicated incoming call screen with Accept/Decline flows and background audio ringing logic.
* **Push Notifications**: Missed call and incoming call notifications delivered natively via Firebase Cloud Messaging (FCM).
* **Profile Management**: Profile customization with avatar generation and photo uploads.
* **Cloud Build**: Integrated GitHub Actions CI/CD for automated Android APK compilation.

## 🛠️ Tech Stack & Architecture

### Core
* **Flutter Version**: `3.47.2` (Stable)
* **Architecture**: Riverpod-based State Management separating concerns into `Models`, `Services`, and `Screens`.

### Backend
* **Database & Auth**: Firebase Cloud Firestore, Firebase Authentication, Firebase Storage
* **Push Notifications**: Firebase Cloud Messaging (FCM)

### Calling SDK
* **WebRTC SDK**: `flutter_webrtc` (^0.12.7) utilizing Google's public STUN servers for peer-to-peer connection negotiation.

### Key Packages Used
* `flutter_riverpod` (State Management & Dependency Injection)
* `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage` (Backend integrations)
* `flutter_webrtc` (Audio/Video peer-to-peer streaming)
* `firebase_messaging` (Background & Foreground push notifications)
* `image_picker` (Profile avatar selection)

## 🚀 Setup Instructions

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Swaroop-2000/ConnectCall.git
   cd ConnectCall
   ```

2. **Install Dependencies:**
   ```bash
   flutter pub get
   ```

3. **Configure Firebase (Environment Setup):**
   * **For Android:** Download your `google-services.json` from the Firebase Console and place it in the `android/app/` directory.
   * **For Web:** Ensure your Firebase configuration keys are placed in `web/firebase-messaging-sw.js` and `lib/firebase_options.dart`.

4. **Run the App:**
   ```bash
   flutter run
   ```
   *To run explicitly on web:* `flutter run -d chrome`

## ⚙️ Environment Variables / Configuration
* **Firebase Config:** The app relies on the `google-services.json` (Android) to wire up Firestore and FCM. This file is excluded from version control (`.gitignore`) for security.
* **WebRTC Configuration:** Currently utilizes public Google STUN servers (`stun.l.google.com:19302`) configured inside `calling_service.dart`.

## ⚠️ Known Limitations
* **Web Backgrounding / Tab Sleeping:** Some modern browsers (like Chrome's Memory Saver) may aggressively suspend tabs, which can immediately toggle the Firebase presence system to "Offline" if the tab is backgrounded.
* **Strict NAT Networks:** The application currently relies purely on STUN servers. If users are behind symmetric/strict NAT firewalls, WebRTC connections might fail because a TURN server is not currently implemented.
* **Android Push Notifications:** Requires a physical device or Google Play emulator to fully test Firebase Cloud Messaging.

## 🤖 AI Tools Used
* Code generation, architecture scaffolding, WebRTC implementation, and CI/CD GitHub Action setups were assisted and accelerated by the **Antigravity AI Agent (Gemini/Claude)**.
