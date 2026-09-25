import 'package:flutter_test/flutter_test.dart';
import 'package:travel_app/services/auth_route.dart';
import 'package:travel_app/services/auth_session.dart';

void main() {
  group('auth route policy', () {
    test('holds the route at loading until the initial SDK session is known',
        () {
      expect(
        AuthRoute.resolve(AuthStatus.loading),
        AuthDestination.loading,
      );
    });

    test('sends an unauthenticated visitor to the canonical login screen', () {
      expect(
        AuthRoute.resolve(AuthStatus.unauthenticated),
        AuthDestination.login,
      );
    });

    test('sends an authenticated session to the dashboard', () {
      expect(
        AuthRoute.resolve(AuthStatus.authenticated),
        AuthDestination.dashboard,
      );
    });

    test('OAuth callback stays in the Flutter app and preserves a deep link',
        () {
      final callback = AuthRoute.oauthCallbackUri(
        Uri.parse(
          'https://voyplan.in/app/?auth=login&from=Bengaluru&to=Coorg#old',
        ),
      );

      expect(callback.origin, 'https://voyplan.in');
      expect(callback.path, '/app/');
      expect(callback.queryParameters['auth'], 'login');
      expect(callback.queryParameters['from'], 'Bengaluru');
      expect(callback.queryParameters['to'], 'Coorg');
      expect(callback.fragment, isEmpty);
    });

    test('production OAuth uses the canonical app URL from a Pages preview',
        () {
      final callback = AuthRoute.oauthCallbackUri(
        Uri.parse('https://preview.voyplan.pages.dev/app/?auth=login'),
        canonicalAppUrl: 'https://voyplan.in/app/',
      );

      expect(callback.toString(), 'https://voyplan.in/app/?auth=login');
    });
  });
}
