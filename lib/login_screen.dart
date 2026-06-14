import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    setState(() => _isLoading = true);

    try {
      if (_isSignUp) {
        if (password != _confirmPasswordController.text.trim()) {
          _showError('Passwords do not match');
          setState(() => _isLoading = false);
          return;
        }

        final userCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        final uid = userCred.user!.uid;

        final usersSnapshot = await FirebaseFirestore.instance.collection('users').limit(1).get();
        final isFirstUser = usersSnapshot.docs.isEmpty;
        final role = isFirstUser ? 'admin' : 'sales';

        final tenantId = FirebaseFirestore.instance.collection('tenants').doc().id;
        await FirebaseFirestore.instance.collection('tenants').doc(tenantId).set({
          'name': '${email.split('@')[0]}\'s Business',
          'createdAt': FieldValue.serverTimestamp(),
        });

        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'name': email.split('@')[0],
          'email': email,
          'role': role,
          'tenantId': tenantId,
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('You are registered as $role.'), backgroundColor: Colors.green),
          );
        }
        // No manual navigation – AuthWrapper will handle it.
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        // Add a small delay to ensure Firestore rules are applied.
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'No account found. Please sign up first.';
          break;
        case 'wrong-password':
          message = 'Incorrect password.';
          break;
        case 'invalid-email':
          message = 'Invalid email format.';
          break;
        case 'email-already-in-use':
          message = 'Email already in use. Please login.';
          break;
        case 'operation-not-allowed':
          message = 'Email/Password sign‑in is disabled. Enable it in Firebase Console.';
          break;
        default:
          message = e.message ?? 'Authentication failed.';
      }
      _showError(message);
    } catch (e) {
      _showError('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.storefront, size: 80, color: Colors.green),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofocus: true,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Please enter your email';
                    if (!value.contains('@') || !value.contains('.')) return 'Enter a valid email address';
                    return null;
                  },
                  onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  obscureText: _obscurePassword,
                  textInputAction: _isSignUp ? TextInputAction.next : TextInputAction.done,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please enter your password';
                    if (_isSignUp && value.length < 6) return 'Password must be at least 6 characters';
                    return null;
                  },
                  onFieldSubmitted: (_) {
                    if (_isSignUp) {
                      FocusScope.of(context).nextFocus();
                    } else {
                      _submit();
                    }
                  },
                ),
                if (_isSignUp) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmPasswordController,
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                      ),
                    ),
                    obscureText: _obscureConfirmPassword,
                    textInputAction: TextInputAction.done,
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Please confirm your password';
                      if (value != _passwordController.text.trim()) return 'Passwords do not match';
                      return null;
                    },
                    onFieldSubmitted: (_) => _submit(),
                  ),
                ],
                const SizedBox(height: 24),
                if (_isLoading)
                  const CircularProgressIndicator()
                else
                  ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: Text(_isSignUp ? 'Sign Up' : 'Login'),
                  ),
                TextButton(
                  onPressed: () => setState(() => _isSignUp = !_isSignUp),
                  child: Text(_isSignUp ? 'Already have an account? Login' : 'Create a new account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}