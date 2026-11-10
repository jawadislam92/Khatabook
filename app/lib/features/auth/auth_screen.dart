import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/big_button.dart';
import '../../core/widgets/brand_header.dart';
import '../../l10n/app_localizations.dart';
import '../groups/groups_models.dart';
import 'auth_repository.dart';
import 'pending_invite.dart';

enum _Mode { signIn, signUp }

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => AuthScreenState();
}

class AuthScreenState extends ConsumerState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  String? _info;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Any password the server takes: 6 characters is its lowest limit.
  static bool passwordIsStrong(String p) => p.length >= 6;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String _message(AuthFailure f, AppLocalizations l) => switch (f.kind) {
    AuthFailureKind.invalidCredentials => l.errorSignIn,
    AuthFailureKind.network => l.errorNetwork,
    AuthFailureKind.weakPassword => l.errorPasswordWeak,
    AuthFailureKind.emailTaken => l.haveAccount,
    AuthFailureKind.googleInUse => l.errorGoogleInUse,
    AuthFailureKind.cancelled || AuthFailureKind.unknown => l.errorGeneric,
  };

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final repo = ref.read(authRepositoryProvider);
    try {
      if (_mode == _Mode.signIn) {
        await repo.signIn(email: _email.text, password: _password.text);
      } else {
        final outcome = await repo.signUp(
          name: _name.text,
          email: _email.text,
          password: _password.text,
          languageCode: ref.read(appSettingsProvider).languageCode,
        );
        if (outcome == SignUpOutcome.confirmEmail && mounted) {
          setState(() {
            _mode = _Mode.signIn;
            _info = l.checkEmailBody(_email.text.trim());
          });
        }
      }
    } on AuthFailure catch (f) {
      if (mounted) setState(() => _error = _message(f, l));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } on AuthFailure catch (f) {
      if (f.kind == AuthFailureKind.cancelled) return;
      if (mounted) setState(() => _error = _message(f, l));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final l = AppLocalizations.of(context);
    final email = _email.text.trim();
    if (!_emailRe.hasMatch(email)) {
      setState(() => _error = l.errorInvalidEmail);
      return;
    }
    await ref.read(authRepositoryProvider).sendPasswordReset(email);
    if (mounted) setState(() => _info = l.resetSent);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final signUp = _mode == _Mode.signUp;
    final live = ref.watch(authRepositoryProvider).isLive;

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BrandHeader(
              title: l.appTitle,
              subtitle: signUp ? l.createAccount : l.signIn,
            ),
            Padding(
              padding: const EdgeInsets.all(Tokens.s4),
              child: Form(
                key: _form,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!live) _PreviewBanner(text: l.demoBanner),
                    const _InviteJoinCard(),
                    const SizedBox(height: Tokens.s4),
                    Text(
                      signUp ? l.createAccount : l.signIn,
                      style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: Tokens.s5),
                    if (signUp) ...[
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        decoration: InputDecoration(labelText: l.yourName),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? l.errorNameRequired
                            : null,
                      ),
                      const SizedBox(height: Tokens.s3),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      autocorrect: false,
                      decoration: InputDecoration(labelText: l.email),
                      validator: (v) => _emailRe.hasMatch((v ?? '').trim())
                          ? null
                          : l.errorInvalidEmail,
                    ),
                    const SizedBox(height: Tokens.s3),
                    TextFormField(
                      controller: _password,
                      obscureText: !_showPassword,
                      autofillHints: [
                        signUp
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      decoration: InputDecoration(
                        labelText: l.password,
                        helperText: signUp ? l.passwordHint : null,
                        helperMaxLines: 3,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                      validator: (v) {
                        if (!signUp) {
                          return (v == null || v.isEmpty)
                              ? l.errorSignIn
                              : null;
                        }
                        return passwordIsStrong(v ?? '')
                            ? null
                            : l.errorPasswordWeak;
                      },
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (!signUp)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          onPressed: _busy ? null : _forgot,
                          child: Text(l.forgotPassword),
                        ),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: Tokens.s3),
                      _Notice(
                        text: _error!,
                        color: scheme.error,
                        icon: Icons.error_outline,
                      ),
                    ],
                    if (_info != null) ...[
                      const SizedBox(height: Tokens.s3),
                      _Notice(
                        text: _info!,
                        color: scheme.primary,
                        icon: Icons.mark_email_read_outlined,
                      ),
                    ],
                    const SizedBox(height: Tokens.s5),
                    BigButton(
                      label: signUp ? l.createAccount : l.signIn,
                      onPressed: _submit,
                      busy: _busy,
                    ),
                    const SizedBox(height: Tokens.s4),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Tokens.s3,
                          ),
                          child: Text(l.orDivider, style: text.bodyMedium),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: Tokens.s4),
                    BigButton(
                      label: l.continueWithGoogle,
                      icon: Icons.g_mobiledata,
                      outlined: true,
                      onPressed: _busy ? null : _google,
                    ),
                    const SizedBox(height: Tokens.s4),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _mode = signUp ? _Mode.signIn : _Mode.signUp;
                              _error = null;
                              _info = null;
                            }),
                      child: Text(signUp ? l.haveAccount : l.noAccountYet),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.color, required this.icon});
  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Tokens.s3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Tokens.radius),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: Tokens.s4),
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.s3,
        vertical: Tokens.s2,
      ),
      decoration: BoxDecoration(
        color: scheme.secondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Tokens.radius),
      ),
      child: Row(
        children: [
          Icon(Icons.science_outlined, size: 20, color: scheme.secondary),
          const SizedBox(width: Tokens.s2),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// For someone who got an invite link: join with only a name, no email and
/// no password. Opens by itself when the app was opened from an invite.
class _InviteJoinCard extends ConsumerStatefulWidget {
  const _InviteJoinCard();

  @override
  ConsumerState<_InviteJoinCard> createState() => _InviteJoinCardState();
}

class _InviteJoinCardState extends ConsumerState<_InviteJoinCard> {
  final _link = TextEditingController();
  final _name = TextEditingController();
  var _open = false;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final pending = ref.read(pendingInviteProvider);
    if (pending != null) {
      _open = true;
      _link.text = InviteLink.build(pending);
    }
  }

  @override
  void dispose() {
    _link.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final l = AppLocalizations.of(context);
    final token = InviteLink.parse(_link.text);
    final name = _name.text.trim();
    if (token == null) {
      setState(() => _error = l.inviteNotFound);
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = l.errorNameRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    ref.read(pendingInviteProvider.notifier).set(token);
    try {
      await ref
          .read(authRepositoryProvider)
          .joinWithName(
            name,
            languageCode: ref.read(appSettingsProvider).languageCode,
          );
    } on AuthFailure catch (f) {
      if (mounted) {
        setState(
          () => _error = f.kind == AuthFailureKind.network
              ? l.errorNetwork
              : l.errorGeneric,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radius),
        side: BorderSide(color: Tokens.familyHue, width: _open ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Tokens.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Row(
                children: [
                  const Icon(Icons.mail_lock_outlined, color: Tokens.familyHue),
                  const SizedBox(width: Tokens.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.guestJoinTitle,
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(l.guestJoinBody, style: text.bodyMedium),
                      ],
                    ),
                  ),
                  Icon(_open ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
            if (_open) ...[
              const SizedBox(height: Tokens.s4),
              TextField(
                controller: _link,
                decoration: InputDecoration(
                  labelText: l.guestInviteLink,
                  prefixIcon: const Icon(Icons.link),
                ),
              ),
              const SizedBox(height: Tokens.s3),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: l.yourName),
                onSubmitted: (_) => _join(),
              ),
              if (_error != null) ...[
                const SizedBox(height: Tokens.s2),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
              const SizedBox(height: Tokens.s3),
              BigButton(
                label: l.guestJoinButton,
                onPressed: _busy ? null : _join,
                busy: _busy,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
