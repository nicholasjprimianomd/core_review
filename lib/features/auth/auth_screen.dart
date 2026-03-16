import 'package:flutter/material.dart';

import '../../repositories/auth_repository.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    required this.authRepository,
    required this.currentUser,
    super.key,
  });

  final AuthRepository authRepository;
  final AuthUser? currentUser;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSignInMode = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _infoMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.authRepository.isConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sign in')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Cloud sign-in is not configured for this build. '
              'Set the Supabase environment values to enable shared accounts.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final currentUser = widget.currentUser;
    if (currentUser != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Account')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Signed in',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Text(currentUser.email),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () async {
                        setState(() {
                          _isSubmitting = true;
                          _errorMessage = null;
                          _infoMessage = null;
                        });
                        try {
                          await widget.authRepository.signOut();
                          if (!context.mounted) {
                            return;
                          }
                          Navigator.of(context).pop(true);
                        } catch (error) {
                          if (!mounted) {
                            return;
                          }
                          setState(() {
                            _isSubmitting = false;
                            _errorMessage = error.toString();
                            _infoMessage = null;
                          });
                        }
                      },
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isSignInMode ? 'Sign in' : 'Create account'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isSignInMode
                    ? 'Sign in to sync your progress'
                    : 'Create an account to sync your progress',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty || !text.contains('@')) {
                    return 'Enter a valid email.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value ?? '';
                  if (text.length < 6) {
                    return 'Password must be at least 6 characters.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              if (_infoMessage != null)
                Text(
                  _infoMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              if (_infoMessage != null) const SizedBox(height: 16),
              if (_errorMessage != null)
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_isSignInMode ? Icons.login : Icons.person_add),
                label: Text(_isSignInMode ? 'Sign in' : 'Create account'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isSubmitting
                    ? null
                    : () {
                        setState(() {
                          _isSignInMode = !_isSignInMode;
                          _errorMessage = null;
                          _infoMessage = null;
                        });
                      },
                child: Text(
                  _isSignInMode
                      ? 'Need an account? Create one'
                      : 'Already have an account? Sign in',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      if (_isSignInMode) {
        await widget.authRepository.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        final result = await widget.authRepository.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        if (result.requiresEmailConfirmation) {
          if (!mounted) {
            return;
          }
          setState(() {
            _isSubmitting = false;
            _isSignInMode = true;
            _passwordController.clear();
            _infoMessage = result.message;
          });
          return;
        }
      }

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _errorMessage = error.toString();
        _infoMessage = null;
      });
    }
  }
}
