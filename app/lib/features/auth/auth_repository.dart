import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/config/app_config.dart';

/// The signed in person, independent of the backend.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    this.displayName,
    this.isGuest = false,
  });
  final String id;
  final String email;
  final String? displayName;

  /// Joined from an invite with only a name. The login lives on this phone
  /// until Google is connected to it.
  final bool isGuest;
}

/// Thrown by repository methods with a message key the UI can translate.
class AuthFailure implements Exception {
  const AuthFailure(this.kind, [this.detail]);
  final AuthFailureKind kind;
  final String? detail;

  @override
  String toString() => 'AuthFailure($kind, $detail)';
}

enum AuthFailureKind {
  invalidCredentials,
  network,
  weakPassword,
  emailTaken,

  /// The person closed the Google account picker. Not an error to show.
  cancelled,

  /// This Google account already belongs to another Duebook login.
  googleInUse,
  unknown,
}

/// Outcome of sign up: either signed in right away or waiting on email confirmation.
enum SignUpOutcome { signedIn, confirmEmail }

abstract class AuthRepository {
  AuthUser? get currentUser;
  Stream<AuthUser?> get changes;

  Future<void> signIn({required String email, required String password});
  Future<SignUpOutcome> signUp({
    required String name,
    required String email,
    required String password,
    required String languageCode,
  });
  Future<void> signInWithGoogle();

  /// Signs in with only a name, for someone who was sent an invite link.
  Future<void> joinWithName(String name, {required String languageCode});

  /// Connects Google to a name-only login so it survives a new phone.
  Future<void> connectGoogle();
  Future<void> sendPasswordReset(String email);
  Future<void> signOut();

  /// Whether this repository talks to a real server.
  bool get isLive;
}

/// Real backend.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);
  final sb.SupabaseClient _client;

  @override
  bool get isLive => true;

  AuthUser? _map(sb.User? u) => u == null
      ? null
      : AuthUser(
          id: u.id,
          email: u.email ?? '',
          displayName:
              u.userMetadata?['display_name'] as String? ??
              u.userMetadata?['full_name'] as String?,
          isGuest: u.isAnonymous,
        );

  @override
  AuthUser? get currentUser => _map(_client.auth.currentUser);

  @override
  Stream<AuthUser?> get changes =>
      _client.auth.onAuthStateChange.map((e) => _map(e.session?.user));

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on sb.AuthException catch (e) {
      throw AuthFailure(
        e.statusCode == '400' || e.statusCode == '401'
            ? AuthFailureKind.invalidCredentials
            : AuthFailureKind.unknown,
        e.message,
      );
    } catch (e) {
      throw AuthFailure(AuthFailureKind.network, '$e');
    }
  }

  @override
  Future<SignUpOutcome> signUp({
    required String name,
    required String email,
    required String password,
    required String languageCode,
  }) async {
    try {
      final res = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'display_name': name.trim(), 'language': languageCode},
      );
      return res.session == null
          ? SignUpOutcome.confirmEmail
          : SignUpOutcome.signedIn;
    } on sb.AuthWeakPasswordException catch (e) {
      throw AuthFailure(AuthFailureKind.weakPassword, e.message);
    } on sb.AuthException catch (e) {
      final msg = e.message.toLowerCase();
      throw AuthFailure(
        msg.contains('already')
            ? AuthFailureKind.emailTaken
            : AuthFailureKind.unknown,
        e.message,
      );
    } catch (e) {
      throw AuthFailure(AuthFailureKind.network, '$e');
    }
  }

  /// The phone's own Google account picker (Android, and iPhone once its
  /// client ID is set). Returns the Google ID token, or null when this build
  /// has no Google client ID and must use the browser page instead.
  Future<String?> _googleIdToken() async {
    if (kIsWeb || AppConfig.googleWebClientId.isEmpty) return null;
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    if (ios && AppConfig.googleIosClientId.isEmpty) return null;
    final google = GoogleSignIn.instance;
    _googleReady ??= google.initialize(
      serverClientId: AppConfig.googleWebClientId,
      clientId: ios ? AppConfig.googleIosClientId : null,
    );
    try {
      await _googleReady;
      final account = await google.authenticate();
      final token = account.authentication.idToken;
      if (token == null) throw const AuthFailure(AuthFailureKind.unknown);
      return token;
    } on GoogleSignInException catch (e) {
      throw AuthFailure(
        e.code == GoogleSignInExceptionCode.canceled
            ? AuthFailureKind.cancelled
            : AuthFailureKind.unknown,
        '${e.code} ${e.description}',
      );
    }
  }

  static Future<void>? _googleReady;

  @override
  Future<void> signInWithGoogle() async {
    try {
      final token = await _googleIdToken();
      if (token != null) {
        await _client.auth.signInWithIdToken(
          provider: sb.OAuthProvider.google,
          idToken: token,
        );
        return;
      }
      await _client.auth.signInWithOAuth(
        sb.OAuthProvider.google,
        redirectTo: AppConfig.authRedirect,
        authScreenLaunchMode: sb.LaunchMode.externalApplication,
      );
    } on AuthFailure {
      rethrow;
    } on sb.AuthException catch (e) {
      throw AuthFailure(AuthFailureKind.unknown, e.message);
    } catch (e) {
      throw AuthFailure(AuthFailureKind.network, '$e');
    }
  }

  @override
  Future<void> joinWithName(String name, {required String languageCode}) async {
    try {
      await _client.auth.signInAnonymously(
        data: {'display_name': name.trim(), 'language': languageCode},
      );
    } on sb.AuthException catch (e) {
      throw AuthFailure(AuthFailureKind.unknown, e.message);
    } catch (e) {
      throw AuthFailure(AuthFailureKind.network, '$e');
    }
  }

  @override
  Future<void> connectGoogle() async {
    try {
      final token = await _googleIdToken();
      if (token == null) {
        await _client.auth.linkIdentity(
          sb.OAuthProvider.google,
          redirectTo: AppConfig.authRedirect,
          authScreenLaunchMode: sb.LaunchMode.externalApplication,
        );
        return;
      }
      await _client.auth.linkIdentityWithIdToken(
        provider: sb.OAuthProvider.google,
        idToken: token,
      );
    } on AuthFailure {
      rethrow;
    } on sb.AuthException catch (e) {
      final msg = e.message.toLowerCase();
      throw AuthFailure(
        msg.contains('already')
            ? AuthFailureKind.googleInUse
            : AuthFailureKind.unknown,
        e.message,
      );
    } catch (e) {
      throw AuthFailure(AuthFailureKind.network, '$e');
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: AppConfig.authRedirect,
      );
    } catch (e) {
      throw AuthFailure(AuthFailureKind.network, '$e');
    }
  }

  @override
  Future<void> signOut() async {
    // So the account picker shows again next time.
    if (_googleReady != null) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await _client.auth.signOut();
  }
}

/// Preview mode: no server. Any email and password work. Used for the web
/// preview and for UI tests. Shows a banner so nobody mistakes it for real.
class PreviewAuthRepository implements AuthRepository {
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _user;

  @override
  bool get isLive => false;

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> get changes => _controller.stream;

  void _set(AuthUser? u) {
    _user = u;
    _controller.add(u);
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!email.contains('@') || password.isEmpty) {
      throw const AuthFailure(AuthFailureKind.invalidCredentials);
    }
    _set(
      AuthUser(
        id: 'preview',
        email: email.trim(),
        displayName: email.split('@').first,
      ),
    );
  }

  @override
  Future<SignUpOutcome> signUp({
    required String name,
    required String email,
    required String password,
    required String languageCode,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _set(
      AuthUser(id: 'preview', email: email.trim(), displayName: name.trim()),
    );
    return SignUpOutcome.signedIn;
  }

  @override
  Future<void> signInWithGoogle() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _set(
      const AuthUser(
        id: 'preview',
        email: 'preview@example.com',
        displayName: 'Preview',
      ),
    );
  }

  @override
  Future<void> joinWithName(String name, {required String languageCode}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _set(
      AuthUser(
        id: 'preview',
        email: '',
        displayName: name.trim(),
        isGuest: true,
      ),
    );
  }

  @override
  Future<void> connectGoogle() async {
    final u = _user;
    if (u == null) return;
    _set(
      AuthUser(
        id: u.id,
        email: 'preview@example.com',
        displayName: u.displayName,
      ),
    );
  }

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signOut() async => _set(null);
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (AppConfig.isConfigured) {
    return SupabaseAuthRepository(sb.Supabase.instance.client);
  }
  return PreviewAuthRepository();
});

/// Current user, kept up to date from the repository stream.
final currentUserProvider = StreamProvider<AuthUser?>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  final controller = StreamController<AuthUser?>();
  controller.add(repo.currentUser);
  final sub = repo.changes.listen(controller.add);
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });
  return controller.stream;
});
