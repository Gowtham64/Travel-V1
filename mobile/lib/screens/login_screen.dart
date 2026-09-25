import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../services/auth_session.dart';
import '../services/auth_route.dart';
import '../widgets/app_design.dart';

class LoginScreen extends StatefulWidget {
  final bool startInSignUp;
  const LoginScreen({
    super.key,
    this.startInSignUp = false,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identifierController =
      TextEditingController(); // For login: Email or Phone
  final _passwordController = TextEditingController();

  // Custom SignUp controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();

  bool _isLoading = false;
  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _hasCompletedModalLogin = false;
  late final VoidCallback _authStateListener;

  final String _bgUrl =
      'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?q=80&w=2000&auto=format&fit=crop';

  @override
  void initState() {
    super.initState();
    _isSignUp = widget.startInSignUp;
    _authStateListener = _completeModalLoginIfNeeded;
    AuthSession.instance.addListener(_authStateListener);
  }

  /// A root login is replaced by [AuthStateWrapper] when AuthSession changes.
  /// When this screen was presented as an action prompt, close only that modal
  /// route so the caller can resume its authorized action. This observes the
  /// existing app auth state; it does not create another Supabase listener.
  void _completeModalLoginIfNeeded() {
    if (_hasCompletedModalLogin ||
        !mounted ||
        !AuthSession.instance.isAuthenticated ||
        !Navigator.of(context).canPop()) {
      return;
    }
    _hasCompletedModalLogin = true;
    Navigator.of(context).pop(true);
  }

  /// Where the auth provider should send the user back to.
  /// - Web: this Flutter app URL (Supabase completes the PKCE callback here).
  /// - Native: a deep link this app registers (intent-filter in AndroidManifest),
  ///   so the OAuth callback returns to the app instead of a dead web URL.
  String _authRedirectUrl() {
    if (kIsWeb) {
      return AuthRoute.oauthCallbackUri(
        Uri.base,
        canonicalAppUrl: AppConfig.webAuthCallbackUrl,
      ).toString();
    }
    return 'io.github.gowtham64.travelapp://login-callback/';
  }

  String _getDeviceAccessInfo() {
    if (kIsWeb) return 'Web Browser';
    try {
      if (Platform.isAndroid) return 'Android Device';
      if (Platform.isIOS) return 'iOS Device';
      if (Platform.isMacOS) return 'macOS App';
      if (Platform.isWindows) return 'Windows App';
      if (Platform.isLinux) return 'Linux App';
      return 'Mobile App';
    } catch (_) {
      return 'Unknown Device';
    }
  }

  /// Client-side signup validation for clear, immediate feedback (instead of an
  /// opaque server error). Returns an error message, or null if valid.
  String? _validateSignup({required String email, required String password}) {
    final emailOk = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (!emailOk) return 'Please enter a valid email address.';
    if (password.length < 6) return 'Password must be at least 6 characters.';
    return null;
  }

  Future<void> _authenticate() async {
    final password = _passwordController.text.trim();

    if (_isSignUp) {
      final name = _nameController.text.trim();
      final email = _emailController.text.trim();
      final phone = _phoneController.text.trim();
      final location = _locationController.text.trim();

      if (name.isEmpty ||
          email.isEmpty ||
          phone.isEmpty ||
          password.isEmpty ||
          location.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill in all signup fields')),
        );
        return;
      }
      final validationError = _validateSignup(email: email, password: password);
      if (validationError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(validationError)),
        );
        return;
      }

      setState(() => _isLoading = true);

      try {
        // Sign up with Supabase Auth (credentials are securely hashed by
        // Supabase Auth — we never persist the raw password ourselves).
        final authResponse = await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          emailRedirectTo: _authRedirectUrl(),
        );

        final user = authResponse.user;
        if (user != null) {
          final deviceAccess = _getDeviceAccessInfo();
          final session = authResponse.session ??
              Supabase.instance.client.auth.currentSession;

          // Authentication succeeds independently from optional profile setup.
          // A transient database/RLS issue must never strand a valid session on
          // the login screen.
          if (session != null) {
            AuthSession.instance.updateSession(session);
          }

          // Save non-sensitive profile details to public.user_details.
          // NOTE: the password is intentionally NOT stored here — Supabase Auth
          // already manages credentials securely.
          try {
            await Supabase.instance.client.from('user_details').insert({
              'user_id': user.id,
              'name': name,
              'phone': phone,
              'email': email,
              'location': location,
              'device_access': deviceAccess,
            });
          } catch (error) {
            debugPrint('Profile setup warning: $error');
          }

          if (mounted) {
            // If email confirmation is required, no session exists yet.
            final needsConfirmation = session == null;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(needsConfirmation
                    ? 'Account created! Check your email to confirm, then log in.'
                    : 'Registration successful! Logging you in...'),
              ),
            );
            if (needsConfirmation) {
              setState(() => _isSignUp = false);
            }
          }
        }
      } on AuthException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to register details: $e')));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      final identifier = _identifierController.text.trim();
      if (identifier.isEmpty || password.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill in all fields')),
        );
        return;
      }

      setState(() => _isLoading = true);

      try {
        final isPhone = RegExp(r'^\+?[0-9]{7,15}$')
            .hasMatch(identifier.replaceAll(RegExp(r'[^0-9+]'), ''));
        final AuthResponse res;
        if (isPhone) {
          res = await Supabase.instance.client.auth
              .signInWithPassword(
                phone: identifier,
                password: password,
              )
              .timeout(const Duration(seconds: 10));
        } else {
          res = await Supabase.instance.client.auth
              .signInWithPassword(
                email: identifier,
                password: password,
              )
              .timeout(const Duration(seconds: 10));
        }
        if (res.session != null) {
          AuthSession.instance.updateSession(res.session);
        } else if (Supabase.instance.client.auth.currentSession != null) {
          AuthSession.instance
              .updateSession(Supabase.instance.client.auth.currentSession);
        }
      } on AuthException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Login failed: ${e.toString().contains('TimeoutException') ? 'Connection timed out. Please try again.' : e}'),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth
          .signInWithOAuth(
            OAuthProvider.google,
            // Native: returns to the app via the registered deep link; web: the page URL.
            redirectTo: _authRedirectUrl(),
            // On iOS the default in-app browser view can fail to launch the OAuth
            // URL ("Error while launching …"); force the external browser (Safari)
            // on native so the Google flow opens reliably. Ignored on web.
            authScreenLaunchMode: kIsWeb
                ? LaunchMode.platformDefault
                : LaunchMode.externalApplication,
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Failed to sign in with Google: ${e.toString().contains('TimeoutException') ? 'Connection timed out.' : e}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    AuthSession.instance.removeListener(_authStateListener);
    _identifierController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.obsidian,
      body: AnimatedBackground(
        imageUrl: _bgUrl,
        overlayOpacity: 0.58,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding =
                  constraints.maxWidth < 520 ? 20.0 : 32.0;
              return Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    28,
                    horizontalPadding,
                    40,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: RevealIn(
                      child: Container(
                        padding: EdgeInsets.all(
                          constraints.maxWidth < 520 ? 24 : 32,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFCFDFF),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.72),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x660F172A),
                              blurRadius: 44,
                              offset: Offset(0, 22),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: RevealIn.stagger([
                            _buildBrand(),
                            const SizedBox(height: 28),
                            Text(
                              _isSignUp
                                  ? 'Start your next journey'
                                  : 'Welcome back',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isSignUp
                                  ? 'Create your account and keep every trip in one place.'
                                  : 'Sign in to pick up where your planning left off.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 15,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 28),
                            if (_isSignUp) ...[
                              _buildTextField(
                                controller: _nameController,
                                label: 'Full name',
                                hint: 'John Doe',
                                icon: Icons.person_outline_rounded,
                                autofillHints: const [AutofillHints.name],
                              ),
                              const SizedBox(height: 16),
                              _buildTextField(
                                controller: _emailController,
                                label: 'Email address',
                                hint: 'you@example.com',
                                icon: Icons.mail_outline_rounded,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                              ),
                              const SizedBox(height: 16),
                              _buildTextField(
                                controller: _phoneController,
                                label: 'Phone number',
                                hint: '+91 98765 43210',
                                icon: Icons.phone_outlined,
                                keyboardType: TextInputType.phone,
                                autofillHints: const [
                                  AutofillHints.telephoneNumber
                                ],
                              ),
                              const SizedBox(height: 16),
                              _buildTextField(
                                controller: _locationController,
                                label: 'Home base',
                                hint: 'Coimbatore, India',
                                icon: Icons.location_on_outlined,
                                autofillHints: const [
                                  AutofillHints.addressCity
                                ],
                              ),
                              const SizedBox(height: 16),
                            ] else ...[
                              _buildTextField(
                                controller: _identifierController,
                                label: 'Email or phone number',
                                hint: 'you@example.com',
                                icon: Icons.person_outline_rounded,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.username],
                              ),
                              const SizedBox(height: 16),
                            ],
                            _buildTextField(
                              controller: _passwordController,
                              label: 'Password',
                              hint: 'Enter your password',
                              icon: Icons.lock_outline_rounded,
                              isPassword: true,
                              autofillHints: [
                                _isSignUp
                                    ? AutofillHints.newPassword
                                    : AutofillHints.password,
                              ],
                              onSubmitted: (_) => _authenticate(),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _authenticate,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      const Color(0xFFE2E8F0),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        _isSignUp
                                            ? 'Create account'
                                            : 'Continue',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _isLoading
                                  ? null
                                  : () => setState(
                                        () => _isSignUp = !_isSignUp,
                                      ),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.accent,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                              ),
                              child: Text(
                                _isSignUp
                                    ? 'Already have an account? Sign in'
                                    : 'New to VoyPlan? Create an account',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Row(
                              children: [
                                Expanded(
                                  child: Divider(
                                    color: Color(0xFFE2E8F0),
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  child: Text(
                                    'OR',
                                    style: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Divider(
                                    color: Color(0xFFE2E8F0),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              height: 52,
                              child: OutlinedButton.icon(
                                onPressed:
                                    _isLoading ? null : _signInWithGoogle,
                                icon: const Text(
                                  'G',
                                  style: TextStyle(
                                    color: Color(0xFF4285F4),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                label: const Text(
                                  'Continue with Google',
                                  style: TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Color(0xFFCBD5E1),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  backgroundColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Your trips and account stay private and secure.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBrand() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          height: 38,
          width: 38,
          decoration: BoxDecoration(
            gradient: AppColors.accentGradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withOpacity(0.26),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Icon(
            Icons.explore_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'VoyPlan',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    TextInputType? keyboardType,
    Iterable<String>? autofillHints,
    ValueChanged<String>? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF334155),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: isPassword && _obscurePassword,
          keyboardType: keyboardType,
          autofillHints: autofillHints,
          enableSuggestions: !isPassword,
          autocorrect: !isPassword,
          style: const TextStyle(color: Color(0xFF0F172A), fontSize: 16),
          cursorColor: AppColors.accent,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
            prefixIcon: Icon(icon, color: AppColors.accent),
            suffixIcon: isPassword
                ? IconButton(
                    tooltip:
                        _obscurePassword ? 'Show password' : 'Hide password',
                    onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: const Color(0xFF64748B),
                    ),
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 17,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: Color(0xFFCBD5E1),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: Color(0xFFCBD5E1),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.accentLight,
                width: 1.6,
              ),
            ),
          ),
          onSubmitted: onSubmitted,
        ),
      ],
    );
  }
}
