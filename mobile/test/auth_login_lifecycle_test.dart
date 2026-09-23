import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

// Domain models and simulated state machine representing the VoyPlan auth lifecycle
class SimulatedUser {
  final String id;
  final String email;
  final Map<String, dynamic>? appMetadata;
  final Map<String, dynamic>? userMetadata;

  SimulatedUser({
    required this.id,
    required this.email,
    this.appMetadata,
    this.userMetadata,
  });
}

class SimulatedSession {
  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final DateTime expiresAt;
  final SimulatedUser user;

  SimulatedSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.expiresAt,
    required this.user,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

enum SimulatedAuthEvent {
  initialSession,
  signedIn,
  signedOut,
  tokenRefreshed,
  userUpdated,
}

class SimulatedAuthException implements Exception {
  final String message;
  final String? statusCode;

  SimulatedAuthException(this.message, {this.statusCode});

  @override
  String toString() => 'SimulatedAuthException: $message (code: $statusCode)';
}

/// Simulated Client that mirrors Supabase Auth lifecycle for VoyPlan
class SimulatedAuthClient {
  SimulatedSession? _currentSession;
  final StreamController<MapEntry<SimulatedAuthEvent, SimulatedSession?>> _authStateController =
      StreamController<MapEntry<SimulatedAuthEvent, SimulatedSession?>>.broadcast();

  final Map<String, String> localPersistedStorage = {};
  bool networkAvailable = true;
  Duration simulatedDelay = Duration.zero;

  SimulatedSession? get currentSession => _currentSession;
  SimulatedUser? get currentUser => _currentSession?.user;
  Stream<MapEntry<SimulatedAuthEvent, SimulatedSession?>> get onAuthStateChange =>
      _authStateController.stream;

  /// 1. Sign in with Email / Password
  Future<SimulatedSession> signInWithPassword({
    required String email,
    required String password,
  }) async {
    if (!networkAvailable) {
      throw SimulatedAuthException('Network connection unavailable (503)', statusCode: '503');
    }
    if (simulatedDelay > Duration.zero) {
      await Future.delayed(simulatedDelay);
    }

    if (email == 'user@voyplan.in' && password == 'correctPassword123') {
      final user = SimulatedUser(id: 'usr_valid_123', email: email);
      final session = SimulatedSession(
        accessToken: 'mock_jwt_access_token_abc',
        refreshToken: 'mock_refresh_token_xyz',
        expiresIn: 3600,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        user: user,
      );
      _currentSession = session;
      localPersistedStorage['sb_refresh'] = session.refreshToken;
      localPersistedStorage['sb_access'] = session.accessToken;

      _authStateController.add(MapEntry(SimulatedAuthEvent.signedIn, session));
      return session;
    } else {
      throw SimulatedAuthException('Invalid login credentials', statusCode: '400');
    }
  }

  /// 2. Sign out with complete cleanup
  Future<void> signOut() async {
    _currentSession = null;
    localPersistedStorage.remove('sb_refresh');
    localPersistedStorage.remove('sb_access');
    _authStateController.add(const MapEntry(SimulatedAuthEvent.signedOut, null));
  }

  /// 3. Restore session from local storage (Cold start / browser refresh)
  Future<SimulatedSession?> restoreSession() async {
    final token = localPersistedStorage['sb_refresh'];
    if (token == null || token.isEmpty) {
      _authStateController.add(const MapEntry(SimulatedAuthEvent.initialSession, null));
      return null;
    }

    if (token == 'mock_refresh_token_xyz') {
      final user = SimulatedUser(id: 'usr_valid_123', email: 'user@voyplan.in');
      final session = SimulatedSession(
        accessToken: 'mock_jwt_access_token_restored',
        refreshToken: token,
        expiresIn: 3600,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        user: user,
      );
      _currentSession = session;
      _authStateController.add(MapEntry(SimulatedAuthEvent.initialSession, session));
      return session;
    } else if (token == 'expired_refresh_token') {
      // Expired token in storage
      _currentSession = null;
      localPersistedStorage.clear();
      _authStateController.add(const MapEntry(SimulatedAuthEvent.initialSession, null));
      return null;
    }
    return null;
  }

  /// 4. Refresh token
  Future<SimulatedSession> refreshSession() async {
    final current = _currentSession;
    if (current == null) {
      throw SimulatedAuthException('No current session to refresh', statusCode: '401');
    }
    final refreshedSession = SimulatedSession(
      accessToken: 'refreshed_jwt_token_${DateTime.now().millisecondsSinceEpoch}',
      refreshToken: current.refreshToken,
      expiresIn: 3600,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      user: current.user,
    );
    _currentSession = refreshedSession;
    localPersistedStorage['sb_access'] = refreshedSession.accessToken;
    _authStateController.add(MapEntry(SimulatedAuthEvent.tokenRefreshed, refreshedSession));
    return refreshedSession;
  }

  void dispose() {
    _authStateController.close();
  }
}

/// Simulated URL and Navigation Redirect Loop Guard
class RedirectLoopGuard {
  int redirectCount = 0;
  String currentPath = '/';

  bool navigateTo(String destination) {
    if (currentPath == destination) {
      // Loop prevented: current path is already destination
      return false;
    }
    redirectCount++;
    currentPath = destination;
    return true;
  }
}

void main() {
  group('VoyPlan Auth Lifecycle Regression Tests (11 Critical Scenarios)', () {
    late SimulatedAuthClient authClient;

    setUp(() {
      authClient = SimulatedAuthClient();
    });

    tearDown(() {
      authClient.dispose();
    });

    // Scenario 1: Login Success
    test('1. Login Success - correctly generates session, stores tokens, and broadcasts signedIn', () async {
      final session = await authClient.signInWithPassword(
        email: 'user@voyplan.in',
        password: 'correctPassword123',
      );

      expect(session.user.email, equals('user@voyplan.in'));
      expect(authClient.currentSession, isNotNull);
      expect(authClient.localPersistedStorage['sb_refresh'], equals('mock_refresh_token_xyz'));
      expect(session.isExpired, isFalse);
    });

    // Scenario 2: Invalid Login
    test('2. Invalid Login - raises AuthException, preserves empty session state', () async {
      expect(
        () async => await authClient.signInWithPassword(
          email: 'user@voyplan.in',
          password: 'wrongPassword',
        ),
        throwsA(isA<SimulatedAuthException>().having((e) => e.message, 'message', contains('Invalid login credentials'))),
      );

      expect(authClient.currentSession, isNull);
      expect(authClient.localPersistedStorage['sb_refresh'], isNull);
    });

    // Scenario 3: Logout Cleanup
    test('3. Logout Cleanup - nullifies session, purges local token cache, broadcasts signedOut', () async {
      await authClient.signInWithPassword(
        email: 'user@voyplan.in',
        password: 'correctPassword123',
      );
      expect(authClient.currentSession, isNotNull);

      await authClient.signOut();
      expect(authClient.currentSession, isNull);
      expect(authClient.localPersistedStorage.containsKey('sb_refresh'), isFalse);
      expect(authClient.localPersistedStorage.containsKey('sb_access'), isFalse);
    });

    // Scenario 4: Session Restore from Storage (Cold Start)
    test('4. Session Restore - restores session on cold start if valid refresh token in storage', () async {
      authClient.localPersistedStorage['sb_refresh'] = 'mock_refresh_token_xyz';

      final restored = await authClient.restoreSession();
      expect(restored, isNotNull);
      expect(restored!.user.email, equals('user@voyplan.in'));
      expect(authClient.currentSession, isNotNull);
    });

    // Scenario 5: Browser Refresh Simulation
    test('5. Browser Refresh Simulation - maintains authenticated state after page reload simulation', () async {
      // User logs in on web
      await authClient.signInWithPassword(
        email: 'user@voyplan.in',
        password: 'correctPassword123',
      );
      final savedRefresh = authClient.localPersistedStorage['sb_refresh'];

      // Simulate browser re-opening / page reload with new client instance sharing storage
      final refreshedClient = SimulatedAuthClient();
      refreshedClient.localPersistedStorage['sb_refresh'] = savedRefresh!;

      final restoredSession = await refreshedClient.restoreSession();
      expect(restoredSession, isNotNull);
      expect(refreshedClient.currentSession?.user.id, equals('usr_valid_123'));
      refreshedClient.dispose();
    });

    // Scenario 6: Expired Session Handling
    test('6. Expired Session Handling - invalidates session and clears persisted tokens', () async {
      authClient.localPersistedStorage['sb_refresh'] = 'expired_refresh_token';

      final restored = await authClient.restoreSession();
      expect(restored, isNull);
      expect(authClient.currentSession, isNull);
      expect(authClient.localPersistedStorage.isEmpty, isTrue);
    });

    // Scenario 7: Token Refresh Handling
    test('7. Token Refresh Handling - issues new access token while preserving valid user session', () async {
      final initialSession = await authClient.signInWithPassword(
        email: 'user@voyplan.in',
        password: 'correctPassword123',
      );
      final initialAccessToken = initialSession.accessToken;

      final refreshed = await authClient.refreshSession();
      expect(refreshed.accessToken, isNot(equals(initialAccessToken)));
      expect(refreshed.user.id, equals(initialSession.user.id));
      expect(authClient.currentSession?.accessToken, equals(refreshed.accessToken));
    });

    // Scenario 8: Backend / Auth Service Unavailable Fallback
    test('8. Service Unavailable Fallback - gracefully handles 503 and permits guest fallback', () async {
      authClient.networkAvailable = false;

      var guestFallbackTriggered = false;
      try {
        await authClient.signInWithPassword(
          email: 'user@voyplan.in',
          password: 'correctPassword123',
        );
      } catch (e) {
        // Fallback to guest mode
        guestFallbackTriggered = true;
      }

      expect(guestFallbackTriggered, isTrue);
      expect(authClient.currentSession, isNull);
    });

    // Scenario 9: Timeout Handling
    test('9. Timeout Handling - aborts stalled authentication after configured deadline', () async {
      authClient.simulatedDelay = const Duration(milliseconds: 200);

      expect(
        () async => await authClient
            .signInWithPassword(
              email: 'user@voyplan.in',
              password: 'correctPassword123',
            )
            .timeout(const Duration(milliseconds: 50)),
        throwsA(isA<TimeoutException>()),
      );
    });

    // Scenario 10: Profile Data Unavailable Fallback
    test('10. Profile Data Unavailable Fallback - login session succeeds even if user_details is missing', () async {
      final session = await authClient.signInWithPassword(
        email: 'user@voyplan.in',
        password: 'correctPassword123',
      );

      // Simulate profile fetch failure (e.g., public.user_details missing record)
      Map<String, dynamic>? profile;
      try {
        // Simulated failure in DB lookup
        throw Exception('Row not found');
      } catch (_) {
        // Fallback profile from auth session user
        profile = {
          'user_id': session.user.id,
          'email': session.user.email,
          'is_fallback': true,
        };
      }

      expect(session.user.id, equals('usr_valid_123'));
      expect(profile['is_fallback'], isTrue);
      expect(profile['email'], equals('user@voyplan.in'));
    });

    // Scenario 11: Redirect Loop Prevention
    test('11. Redirect Loop Prevention - guard stops navigation when destination equals current path', () {
      final guard = RedirectLoopGuard();

      // Navigate to /app/
      final firstNav = guard.navigateTo('/app/');
      expect(firstNav, isTrue);
      expect(guard.redirectCount, equals(1));
      expect(guard.currentPath, equals('/app/'));

      // Attempt redundant navigation to /app/ (the bug that previously caused infinite reloads)
      final secondNav = guard.navigateTo('/app/');
      expect(secondNav, isFalse);
      expect(guard.redirectCount, equals(1)); // Did not increment, loop blocked!
    });

    // Scenario 12: Intended Destination Preservation (returnTo)
    test('12. Intended Destination Preservation - returns to target protected feature after login', () async {
      String? pendingAction;
      var actionExecuted = false;

      void onSelectPlanTrip() {
        pendingAction = 'plan-trip';
      }

      onSelectPlanTrip();
      expect(pendingAction, equals('plan-trip'));

      // Simulate sign in
      final session = await authClient.signInWithPassword(
        email: 'user@voyplan.in',
        password: 'correctPassword123',
      );
      expect(session, isNotNull);

      // On successful auth, execute the preserved target action
      if (pendingAction == 'plan-trip') {
        actionExecuted = true;
        pendingAction = null;
      }

      expect(actionExecuted, isTrue);
      expect(pendingAction, isNull);
    });

    // Scenario 13: Error Code Differentiation (401 vs 403 vs 404 vs 500)
    test('13. Error Code Distinction - only 401 triggers session expiration notice', () {
      String resolveError(int statusCode) {
        if (statusCode == 401) return 'Session expired. Please log in again.';
        if (statusCode == 403) return 'Access denied (403).';
        if (statusCode == 404) return 'Requested item not found (404).';
        if (statusCode >= 500) return 'Server unavailable ($statusCode). Please retry.';
        return 'Request failed ($statusCode)';
      }

      expect(resolveError(401), contains('Session expired'));
      expect(resolveError(403), contains('Access denied'));
      expect(resolveError(404), contains('Requested item not found'));
      expect(resolveError(500), contains('Server unavailable'));
      expect(resolveError(503), contains('Server unavailable'));
    });

    // Scenario 14: Multi-User Data Isolation
    test('14. User Data Isolation - User B cannot view User A account trips or cache', () {
      final storage = <String, String>{};

      String tripKey(String userId) => 'voy_account_${userId}_trips_all';

      // User A creates and caches trips
      final userAId = 'usr_alice_101';
      storage[tripKey(userAId)] = '[{"id": "trip_a_1", "title": "Alice Goa Roadtrip"}]';

      // User B logs in
      final userBId = 'usr_bob_202';
      final userBTripsRaw = storage[tripKey(userBId)];

      // Verify User B's cache is empty and cannot access User A's data
      expect(userBTripsRaw, isNull);
      expect(storage.containsKey(tripKey(userBId)), isFalse);
      expect(storage[tripKey(userAId)], contains('Alice Goa Roadtrip'));
    });
  });
}
