import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/login_screen.dart';
import '../theme/app_theme.dart';
import 'auth_session.dart';

/// Central gate for guest (not-signed-in) restrictions. Guests can browse and
/// view, but saving, sharing, creating more than one trip, and editing are
/// reserved for signed-in accounts.
class AuthGuard {
  static bool get isSignedIn {
    if (AuthSession.instance.isAuthenticated) return true;
    try {
      final s = Supabase.instance.client.auth.currentSession;
      if (s != null) {
        AuthSession.instance.updateSession(s);
        return true;
      }
    } catch (_) {}
    return false;
  }

  static bool get isGuest => !isSignedIn;

  /// Returns true if the user is signed in. If they're a guest, shows a
  /// sign-in prompt for [action] (e.g. "save trips") and returns false — the
  /// caller should then abort the action.
  /// If [onAuthorized] is provided, it will be executed upon successful login.
  static bool ensure(BuildContext context, {required String action, VoidCallback? onAuthorized}) {
    if (isSignedIn) {
      onAuthorized?.call();
      return true;
    }
    if (AuthSession.instance.isLoading) {
      AuthSession.instance.waitForSessionReady().then((_) {
        if (isSignedIn) {
          onAuthorized?.call();
        } else {
          _promptSignIn(context, action, onAuthorized: onAuthorized);
        }
      });
      return false;
    }
    _promptSignIn(context, action, onAuthorized: onAuthorized);
    return false;
  }

  /// Async variant of [ensure] that waits for hydration before checking.
  static Future<bool> ensureAsync(BuildContext context, {required String action, VoidCallback? onAuthorized}) async {
    if (isSignedIn) {
      onAuthorized?.call();
      return true;
    }
    if (AuthSession.instance.isLoading) {
      await AuthSession.instance.waitForSessionReady();
      if (isSignedIn) {
        onAuthorized?.call();
        return true;
      }
    }
    _promptSignIn(context, action, onAuthorized: onAuthorized);
    return false;
  }


  static void _promptSignIn(BuildContext context, String action, {VoidCallback? onAuthorized}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Voy.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.lock_outline_rounded, color: Voy.brand),
                const SizedBox(width: 10),
                const Expanded(
                    child: Text('Sign in to continue',
                        style: TextStyle(
                            color: Voy.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 8),
              Text(
                  'You need an account to $action. It’s free — create one or sign in to unlock saving, sharing and multiple trips.',
                  style: const TextStyle(
                      color: Voy.sub, fontSize: 13.5, height: 1.5)),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Voy.hairline),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child:
                        const Text('Not now', style: TextStyle(color: Voy.sub)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final success = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => LoginScreen(
                            onSuccess: onAuthorized,
                          ),
                        ),
                      );
                      if (success == true) {
                        onAuthorized?.call();
                      }
                    },
                    style: FilledButton.styleFrom(
                        backgroundColor: Voy.brand,
                        foregroundColor: const Color(0xFF04211F),
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: const Text('Sign in',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
