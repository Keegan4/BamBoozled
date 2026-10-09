import 'package:supabase_flutter/supabase_flutter.dart';

/// Email and password sign-in. Accounts are created by the project owner in the Supabase dashboard
/// (Authentication → Users), so the app never signs anyone up and sends no emails.
class AuthService {
  AuthService(this.client);

  final SupabaseClient client;

  User? get currentUser => client.auth.currentUser;

  Stream<User?> userChanges() async* {
    yield client.auth.currentUser;
    yield* client.auth.onAuthStateChange.map((s) => s.session?.user);
  }

  /// Signs in with an account made in the Supabase dashboard. Throws [AuthException] when the email or
  /// password is wrong.
  Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(email: email.trim(), password: password);
  }

  Future<void> signOut() => client.auth.signOut();
}
