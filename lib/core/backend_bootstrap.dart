import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'backend_config.dart';

class BackendBootstrap {
  BackendBootstrap._();

  static bool _enabled = false;

  static bool get isEnabled => _enabled;

  static Future<void> initialize() async {
    if (!BackendConfig.isConfigured) {
      debugPrint(
        'BackendBootstrap: running in local mode (SUPABASE_URL / SUPABASE_ANON_KEY missing)',
      );
      _enabled = false;
      return;
    }

    try {
      await Supabase.initialize(
        url: BackendConfig.supabaseUrl,
        anonKey: BackendConfig.supabaseAnonKey,
      );
      _enabled = true;
    } catch (e, st) {
      debugPrint('BackendBootstrap: Supabase.initialize failed — $e');
      debugPrint('$st');
      _enabled = false;
    }
  }
}
