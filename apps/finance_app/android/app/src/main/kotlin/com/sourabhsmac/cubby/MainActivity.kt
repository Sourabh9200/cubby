package com.sourabhsmac.cubby

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity rather than FlutterActivity: local_auth raises the
// system biometric / device-credential prompt through androidx.biometric, which
// needs a FragmentActivity host. The app-lock screen is a UI-level gate; the
// database is encrypted independently of it.
class MainActivity : FlutterFragmentActivity()
