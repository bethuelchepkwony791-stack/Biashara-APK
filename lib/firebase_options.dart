import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    // Fallback – you only use web, so this should never be reached
    throw UnsupportedError('DefaultFirebaseOptions are only supported for web in this project.');
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB0Phfgwniok8E4HxXhJGgmByVOy_GDx1Q',
    appId: '1:53692608249:web:c6d3b11296399c15a4bc28',
    messagingSenderId: '53692608249',
    projectId: 'biasharaos-5be70',
    authDomain: 'biasharaos-5be70.firebaseapp.com',
    storageBucket: 'biasharaos-5be70.firebasestorage.app',
  );
}