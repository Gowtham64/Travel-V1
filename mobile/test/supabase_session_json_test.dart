import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('Check Supabase recoverSession restores session', () async {
    final client = SupabaseClient(
      'https://dtemayjpttktntooxraa.supabase.co',
      'sb_publishable_sGmsHOvBlUiRKXz0ajEErg_vecwGFnh',
    );
    final jsSessionJson = {
      "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test",
      "token_type": "bearer",
      "expires_in": 3600,
      "expires_at": (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600,
      "refresh_token": "test_refresh_token_123",
      "user": {
        "id": "11111111-2222-3333-4444-555555555555",
        "aud": "authenticated",
        "role": "authenticated",
        "email": "user@voyplan.in",
        "email_confirmed_at": "2026-01-01T00:00:00.000Z",
        "phone": "",
        "confirmed_at": "2026-01-01T00:00:00.000Z",
        "last_sign_in_at": "2026-01-01T00:00:00.000Z",
        "app_metadata": {"provider": "email", "providers": ["email"]},
        "user_metadata": {"full_name": "Test User"},
        "identities": [],
        "created_at": "2026-01-01T00:00:00.000Z",
        "updated_at": "2026-01-01T00:00:00.000Z"
      }
    };
    final res = await client.auth.recoverSession(jsonEncode(jsSessionJson));
    expect(res.session, isNotNull);
    expect(client.auth.currentSession, isNotNull);
    expect(client.auth.currentSession?.user.email, equals("user@voyplan.in"));
  });
}
