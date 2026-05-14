import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/backend_bootstrap.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  bool get isBackendEnabled => BackendBootstrap.isEnabled;

  User? get currentUser {
    if (!isBackendEnabled) return null;
    return Supabase.instance.client.auth.currentUser;
  }

  Future<AuthResponse?> signInWithPassword({
    required String email,
    required String password,
  }) async {
    if (!isBackendEnabled) return null;
    return Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<AuthResponse?> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    if (!isBackendEnabled) return null;
    return Supabase.instance.client.auth.signUp(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    if (!isBackendEnabled) return;
    await Supabase.instance.client.auth.signOut();
  }
}
