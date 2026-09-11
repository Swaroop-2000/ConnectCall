import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    // We only have the web configuration for now.
    // If running on Android/iOS without configuring, it will fallback here.
    return web; 
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyASPhYJM_iPfrSad_0g9cx-BgJsb_13RlI',
    appId: '1:674297555728:web:e6ad856920729c9fab5395',
    messagingSenderId: '674297555728',
    projectId: 'eye-disease-prediction-5b87a',
    authDomain: 'eye-disease-prediction-5b87a.firebaseapp.com',
    storageBucket: 'eye-disease-prediction-5b87a.firebasestorage.app',
    measurementId: 'G-FM8WP515BB',
  );
}
