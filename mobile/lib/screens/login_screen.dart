import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

      setState(() => _isLoading = true);

      try {
        final currentUrl = Uri.base.toString().split('?').first;
        // Sign up with Supabase Auth
        final authResponse = await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          emailRedirectTo: currentUrl,
        );

        final user = authResponse.user;
        if (user != null) {
          final deviceAccess = _getDeviceAccessInfo();
          
          // Save details to public.user_details table
          await Supabase.instance.client.from('user_details').insert({
            'user_id': user.id,
            'name': name,
            'phone': phone,
            'email': email,
            'password_hash': password, // Storing password as requested
            'location': location,
            'device_access': deviceAccess,
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Registration successful! Logging you in...')),
            );
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
      final currentUrl = Uri.base.toString().split('?').first;
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: currentUrl, 
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
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Image.network(
              _bgUrl,
              fit: BoxFit.cover,
            ),
          ),
          // Dark Overlay
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.4),
            ),
          ),
          // Content
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    width: 400,
                    padding: const EdgeInsets.all(32.0),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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
