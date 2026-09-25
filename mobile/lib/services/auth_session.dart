import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The one authoritative view of the Supabase session for the application.
///
/// Screens must not infer authentication from their own loading state or from
/// browser hand-off values. Supabase owns persistence/refresh; this notifier
/// exposes the resolved session to the app, route gate, action guards and API
/// client from that single source.
enum AuthStatus { loading, authenticated, unauthenticated }

class AuthSession extends ChangeNotifier {
  AuthSession._();

  static final AuthSession instance = AuthSession._();

  AuthStatus _status = AuthStatus.loading;
  Session? _session;
  StreamSubscription<AuthState>? _subscription;
  Future<void>? _initializing;
  final List<VoidCallback> _signOutCallbacks = [];

  AuthStatus get status => _status;
  Session? get session => _session;
  User? get user => _session?.user;
  User? get currentUser => _session?.user;
  String? get accessToken => _session?.accessToken;
  bool get isLoading => _status == AuthStatus.loading;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  /// Register a callback to be triggered upon signOut to clear service caches.
  void registerSignOutCallback(VoidCallback callback) {
    if (!_signOutCallbacks.contains(callback)) {
      _signOutCallbacks.add(callback);
    }
  }

  /// Resolves persisted Supabase state before the application exposes a route.
  /// Calling this more than once is safe and shares the original operation.
  Future<void> initialize() => _initializing ??= _initialize();

  /// Waits for the SDK-owned session restoration started by [initialize].
  /// There is deliberately no browser-storage fallback or time-based route
  /// decision: Supabase emits its initial session before this future resolves.
  Future<void> waitForSessionReady(
          [Duration timeout = const Duration(seconds: 4)]) =>
      initialize().timeout(timeout);

  Future<void> _initialize() async {
    try {
      final client = Supabase.instance.client;
      // Supabase.initialize has already restored persisted state and handled
      // a web OAuth callback before this app-level listener is installed.
      // This is the one listener that mirrors SDK state into the UI.
      _subscription = client.auth.onAuthStateChange.listen(
        (state) {
          _update(state.session);
        },
        onError: (error) {
          debugPrint('Auth state change error: $error');
          _update(null);
        },
      );
      _update(client.auth.currentSession, notify: false);
      notifyListeners();
    } on Object catch (error) {
      debugPrint('Auth session initialization failed: $error');
      _update(null, notify: false);
      notifyListeners();
    }
  }

  /// Manually update session and notify listeners immediately (e.g. after login).
  void updateSession(Session? next) {
    _update(next);
  }

  void _update(Session? next, {bool notify = true}) {
    final nextStatus =
        next == null ? AuthStatus.unauthenticated : AuthStatus.authenticated;
    final changed = _session?.accessToken != next?.accessToken ||
        _session?.user.id != next?.user.id ||
        _status != nextStatus;
    _session = next;
    _status = nextStatus;
    if (notify && changed) notifyListeners();
  }

  /// Returns a valid non-expired access token, auto-refreshing if near expiration.
  Future<String?> getValidAccessToken() async {
    Session? s = _session;
    if (s == null) {
      try {
        s = Supabase.instance.client.auth.currentSession;
        if (s != null) {
          _update(s, notify: true);
        }
      } catch (_) {}
    }
    if (s == null) return null;

    // Check if token expires within the next 60 seconds or is expired
    final expiresAt = s.expiresAt;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final isExpiring = expiresAt != null && (expiresAt - now) < 60;

    if (isExpiring || s.isExpired) {
      try {
        final res = await Supabase.instance.client.auth.refreshSession();
        _session = res.session;
        if (_session != null) {
          _status = AuthStatus.authenticated;
          notifyListeners();
          return _session?.accessToken;
        }
      } catch (e) {
        debugPrint('Session refresh warning: $e');
      }
    }

    return _session?.accessToken ?? s.accessToken;
  }

  /// Centralized sign-out logic for all platforms.
  Future<void> signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      debugPrint('Supabase signOut error: $e');
    }
    _session = null;
    _status = AuthStatus.unauthenticated;
    for (final cb in _signOutCallbacks) {
      try {
        cb();
      } catch (e) {
        debugPrint('SignOut callback error: $e');
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
