import 'package:supabase_flutter/supabase_flutter.dart';

/// Email sign-in with a 6-digit code. Works the same on phone and desktop,
/// and nobody has to remember a password.
class AuthService {
  AuthService(this.client);

  final SupabaseClient client;

  User? get currentUser => client.auth.currentUser;

  Stream<User?> userChanges() async* {
    yield client.auth.currentUser;
    yield* client.auth.onAuthStateChange.map((s) => s.session?.user);
  }

  /// Emails a sign-in code. Creates the account on first use.
  Future<void> sendCode(String email) => client.auth.signInWithOtp(email: email.trim(), shouldCreateUser: true);

  Future<void> verifyCode(String email, String code) async {
    await client.auth.verifyOTP(email: email.trim(), token: code.trim(), type: OtpType.email);
  }

  Future<void> signOut() => client.auth.signOut();
}
