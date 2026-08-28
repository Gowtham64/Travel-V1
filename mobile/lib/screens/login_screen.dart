import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_design.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identifierController = TextEditingController(); // For login: Email or Phone
  final _passwordController = TextEditingController();
  
  // Custom SignUp controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();
  
  bool _isLoading = false;
  bool _isSignUp = false;

  final String _bgUrl = 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?q=80&w=2000&auto=format&fit=crop';

  /// Where the auth provider should send the user back to.
  /// - Web: the current page URL (Supabase completes the session in-page).
  /// - Native: a deep link this app registers (intent-filter in AndroidManifest),
  ///   so the OAuth callback returns to the app instead of a dead web URL.
  String _authRedirectUrl() {
    if (kIsWeb) return Uri.base.toString().split('?').first;
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

      if (name.isEmpty || email.isEmpty || phone.isEmpty || password.isEmpty || location.isEmpty) {
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

          // Save non-sensitive profile details to public.user_details.
          // NOTE: the password is intentionally NOT stored here — Supabase Auth
          // already manages credentials securely.
          await Supabase.instance.client.from('user_details').insert({
            'user_id': user.id,
            'name': name,
            'phone': phone,
            'email': email,
            'location': location,
            'device_access': deviceAccess,
          });

          if (mounted) {
            // If email confirmation is required, no session exists yet.
            final needsConfirmation =
                Supabase.instance.client.auth.currentSession == null;
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to register details: $e')));
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
        final isPhone = RegExp(r'^\+?[0-9]{7,15}$').hasMatch(identifier.replaceAll(RegExp(r'[^0-9+]'), ''));
        if (isPhone) {
          await Supabase.instance.client.auth.signInWithPassword(
            phone: identifier,
            password: password,
          );
        } else {
          await Supabase.instance.client.auth.signInWithPassword(
            email: identifier,
            password: password,
          );
        }
      } on AuthException catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('An unexpected error occurred: $e')));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        // Native: returns to the app via the registered deep link; web: the page URL.
        redirectTo: _authRedirectUrl(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to sign in with Google: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AnimatedBackground(
        imageUrl: _bgUrl,
        overlayOpacity: 0.45,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: RevealIn(
              child: SizedBox(
                width: 400,
                child: GlassCard(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: RevealIn.stagger([
                        Text(
                          _isSignUp ? 'Create Account' : 'Welcome Back',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isSignUp ? 'Sign up to start planning your trips' : 'Log in to continue exploring',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 32),
                        
                        if (_isSignUp) ...[
                          _buildTextField(
                            controller: _nameController,
                            label: 'Full Name',
                            hint: 'John Doe',
                            icon: Icons.person_outline,
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _emailController,
                            label: 'Email ID',
                            hint: 'johndoe@example.com',
                            icon: Icons.mail_outline,
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _phoneController,
                            label: 'Phone Number',
                            hint: '+919876543210',
                            icon: Icons.phone_outlined,
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _locationController,
                            label: 'Location',
                            hint: 'Coimbatore, India',
                            icon: Icons.location_on_outlined,
                          ),
                        ] else ...[
                          _buildTextField(
                            controller: _identifierController,
                            label: 'Email or Phone Number',
                            hint: 'user@example.com or +1234567890',
                            icon: Icons.person_outline,
                          ),
                        ],
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _passwordController,
                          label: 'Password',
                          hint: '••••••••',
                          icon: Icons.lock_outline,
                          isPassword: true,
                          onSubmitted: (_) => _authenticate(),
                        ),
                        const SizedBox(height: 24),
                        
                        ElevatedButton(
                          onPressed: _isLoading ? null : _authenticate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E75B6),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(
                                  _isSignUp ? 'Sign Up' : 'Log In',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
                                ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => setState(() => _isSignUp = !_isSignUp),
                          child: Text(
                            _isSignUp ? 'Already have an account? Log In' : 'Need an account? Sign Up',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: Divider(color: Colors.white.withOpacity(0.3))),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text('OR', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                            ),
                            Expanded(child: Divider(color: Colors.white.withOpacity(0.3))),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        OutlinedButton.icon(
                          onPressed: _isLoading ? null : _signInWithGoogle,
                          icon: Image.network(
                            'https://upload.wikimedia.org/wikipedia/commons/thumb/5/53/Google_%22G%22_Logo.svg/512px-Google_%22G%22_Logo.svg.png',
                            height: 20,
                          ),
                          label: const Text(
                            'Sign in with Google',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: Colors.white.withOpacity(0.3)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            backgroundColor: Colors.white.withOpacity(0.05),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    Function(String)? onSubmitted,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Icon(icon, color: Colors.white.withOpacity(0.7)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: isPassword,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                hintText: hint,
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onSubmitted: onSubmitted,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
