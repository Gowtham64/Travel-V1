// Conditional export: real Turnstile widget on web, secure fallback elsewhere.
export 'turnstile_captcha_stub.dart'
    if (dart.library.html) 'turnstile_captcha_web.dart';
