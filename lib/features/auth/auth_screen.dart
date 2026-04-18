import 'package:flutter/material.dart';
import 'package:supabase/supabase.dart' show AuthApiException, AuthException;

import '../../config/app_config.dart';
import '../../repositories/auth_repository.dart';
import 'turnstile_widget.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    required this.authRepository,
    required this.currentUser,
    this.onAuthChanged,
    this.isGate = false,
    super.key,
  });

  final AuthRepository authRepository;
  final AuthUser? currentUser;

  /// When provided, auth state changes (sign in, sign up, sign out) invoke
  /// this callback instead of popping the route. Use when AuthScreen is the
  /// root page of the navigator (e.g. as an access gate).
  final Future<void> Function()? onAuthChanged;

  /// When true the screen is used as an access gate and the leading back
  /// button / close affordance is suppressed.
  final bool isGate;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _captchaController = TurnstileController();

  bool _isSignInMode = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _infoMessage;
  String? _captchaToken;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _finishAuthChange() async {
    final callback = widget.onAuthChanged;
    if (callback != null) {
      await callback();
      return;
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.authRepository.isConfigured) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Sign in'),
          automaticallyImplyLeading: !widget.isGate,
        ),
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
        appBar: AppBar(
          title: const Text('Account'),
          automaticallyImplyLeading: !widget.isGate,
        ),
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
                          await _finishAuthChange();
                        } catch (error) {
                          if (!mounted) {
                            return;
                          }
                          setState(() {
                            _isSubmitting = false;
                            _errorMessage = _friendlyAuthError(error);
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
        automaticallyImplyLeading: !widget.isGate,
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
                    ? (widget.isGate
                        ? 'Sign in to access the question bank'
                        : 'Sign in to sync your progress')
                    : (widget.isGate
                        ? 'Create an account to access the question bank'
                        : 'Create an account to sync your progress'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (widget.isGate) ...[
                const SizedBox(height: 8),
                Text(
                  'Core Review now requires an account. Sign in or create one to continue.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
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
              if (AppConfig.hasCaptcha) ...[
                TurnstileWidget(
                  siteKey: AppConfig.turnstileSiteKey,
                  controller: _captchaController,
                  theme: Theme.of(context).brightness == Brightness.dark
                      ? 'dark'
                      : 'light',
                  onToken: (token) {
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _captchaToken = token;
                    });
                  },
                ),
                const SizedBox(height: 16),
              ],
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

    if (AppConfig.hasCaptcha && (_captchaToken == null || _captchaToken!.isEmpty)) {
      setState(() {
        _errorMessage = 'Please complete the captcha before continuing.';
        _infoMessage = null;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    final captchaToken = _captchaToken;
    try {
      if (_isSignInMode) {
        await widget.authRepository.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          captchaToken: captchaToken,
        );
      } else {
        final result = await widget.authRepository.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          captchaToken: captchaToken,
        );
        if (result.requiresEmailConfirmation) {
          if (!mounted) {
            return;
          }
          _captchaController.reset();
          setState(() {
            _isSubmitting = false;
            _isSignInMode = true;
            _captchaToken = null;
            _passwordController.clear();
            _infoMessage = result.message;
          });
          return;
        }
      }

      if (!mounted) {
        return;
      }
      await _finishAuthChange();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _captchaController.reset();
      setState(() {
        _isSubmitting = false;
        _captchaToken = null;
        _errorMessage = _friendlyAuthError(error);
        _infoMessage = null;
      });
    }
  }

  // Maps common Supabase auth failures to plain-English messages. Anything
  // unrecognized falls back to a generic "try again" so users never see raw
  // `AuthApiException(...)` text.
  String _friendlyAuthError(Object error) {
    if (error is AuthApiException) {
      final code = error.code;
      final status = error.statusCode;
      if (code == 'over_email_send_rate_limit' || status == '429') {
        return 'Too many sign-up attempts right now. Please try again in a few minutes.';
      }
      if (code == 'user_already_exists' ||
          code == 'user_already_registered' ||
          code == 'email_exists') {
        return 'An account with this email already exists. Try signing in instead.';
      }
      if (code == 'invalid_credentials' ||
          code == 'invalid_grant' ||
          code == 'invalid_login_credentials') {
        return 'Incorrect email or password.';
      }
      if (code == 'email_not_confirmed') {
        return 'Please confirm your email before signing in. Check your inbox for the confirmation link.';
      }
      if (code == 'weak_password') {
        return 'That password is too weak. Please choose a longer one.';
      }
      if (code == 'signup_disabled') {
        return 'New sign-ups are currently disabled. Please contact support.';
      }
      if (code == 'captcha_failed') {
        return 'Captcha check failed. Please try again.';
      }
    }
    if (error is AuthException) {
      final message = error.message.trim();
      if (message.toLowerCase().contains('captcha')) {
        return 'Captcha check failed. Please try again.';
      }
      if (message.isNotEmpty) {
        return message;
      }
    }
    return 'Something went wrong. Please try again.';
  }
}
