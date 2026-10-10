import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/session_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/auth_repository.dart';
import '../../shared/widgets/app_logo.dart';
import '../tracking/tracking_screen.dart';

/// Driver sign-in. The server URL is tucked into an "Advanced" section since
/// drivers rarely need to change it.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _serverCtrl = TextEditingController(text: AppConfig.defaultBaseUrl);
  final _passwordFocus = FocusNode();

  bool _loading = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    SessionStorage.lastServerUrl().then((url) {
      if (mounted) _serverCtrl.text = url;
    });
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _serverCtrl.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || !(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final session = await const AuthRepository().login(
        serverUrl: _serverCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TrackingScreen(session: session)),
      );
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Unable to sign in: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.danger),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          // Decorative brand gradient behind the top of the form.
          Container(
            height: 280,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.brandDeep, AppColors.brand],
              ),
            ),
          ),
          // SafeArea on all sides keeps content clear of the status bar,
          // display cutouts and the Android navigation bar.
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.xl,
                  vertical: Insets.xl,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    children:
                        [
                              const AppLogo(size: 64),
                              const Gap(Insets.lg),
                              Text(
                                AppConfig.appName,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Gap(Insets.xs),
                              Text(
                                'Sign in to start sharing your route',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                              const Gap(Insets.xl),
                              _buildForm(theme, scheme),
                            ]
                            .animate(interval: 60.ms)
                            .fadeIn(duration: 350.ms)
                            .slideY(begin: 0.08),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(ThemeData theme, ColorScheme scheme) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(Insets.xl),
        child: Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Welcome back', style: theme.textTheme.titleLarge),
                const Gap(Insets.xs),
                Text(
                  'Use the account given by your fleet admin.',
                  style: theme.textTheme.bodySmall,
                ),
                const Gap(Insets.xl),
                TextFormField(
                  controller: _usernameCtrl,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter your username'
                      : null,
                  onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                ),
                const Gap(Insets.md),
                TextFormField(
                  controller: _passwordCtrl,
                  focusNode: _passwordFocus,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter your password' : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                Theme(
                  // Remove ExpansionTile's default divider lines.
                  data: theme.copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: Insets.sm),
                    dense: true,
                    leading: const Icon(Icons.tune_rounded, size: 18),
                    title: Text('Advanced', style: theme.textTheme.bodySmall),
                    children: [
                      TextFormField(
                        controller: _serverCtrl,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Server URL',
                          prefixIcon: Icon(Icons.dns_outlined),
                        ),
                        validator: (v) {
                          final uri = Uri.tryParse(v?.trim() ?? '');
                          return (uri == null ||
                                  !uri.hasScheme ||
                                  uri.host.isEmpty)
                              ? 'Enter a valid URL (https://…)'
                              : null;
                        },
                      ),
                    ],
                  ),
                ),
                const Gap(Insets.sm),
                FilledButton(
                  // Kept enabled while loading so the spinner stays on-brand;
                  // _submit() itself ignores taps during a request.
                  onPressed: _submit,
                  child: AnimatedSwitcher(
                    duration: 200.ms,
                    child: _loading
                        ? SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: scheme.onPrimary,
                            ),
                          )
                        : const Text('Sign in'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
