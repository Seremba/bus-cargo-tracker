import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// Shown on first login for the auto-seeded default admin account.
/// The admin cannot dismiss this screen — they must set a real password
/// before accessing the dashboard. This closes the hardcoded 'admin123'
/// backdoor that exists on every fresh install.
class ForcePasswordChangeScreen extends StatefulWidget {
  final String userId;
  final VoidCallback onPasswordChanged;

  const ForcePasswordChangeScreen({
    super.key,
    required this.userId,
    required this.onPasswordChanged,
  });

  @override
  State<ForcePasswordChangeScreen> createState() =>
      _ForcePasswordChangeScreenState();
}

class _ForcePasswordChangeScreenState
    extends State<ForcePasswordChangeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  final FocusNode _confirmFocus = FocusNode();

  bool _loading = false;
  bool _hideNew = true;
  bool _hideConfirm = true;

  @override
  void dispose() {
    _newPassword.dispose();
    _confirmPassword.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _submit() async {
    if (_loading) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final ok = await AuthService.changeFirstLoginPassword(
        userId: widget.userId,
        newPassword: _newPassword.text.trim(),
      );

      if (!mounted) return;

      if (!ok) {
        _snack('Something went wrong. Please try again.');
        return;
      }

      _snack('Password updated successfully ✅');
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;

      widget.onPasswordChanged();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.65);

    // PopScope with canPop: false prevents back navigation — admin must
    // complete this step before accessing any part of the app.
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false, // no back arrow
          elevation: 0,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Header ──────────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.lock_outline, color: cs.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'UNEX LOGISTICS',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Admin setup',
                          style: TextStyle(color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // ── Info banner ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: cs.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This is your first time logging in as admin. '
                        'Please set a secure password before continuing. '
                        'This replaces the default password and cannot be skipped.',
                        style: TextStyle(
                          color: cs.onPrimaryContainer,
                          fontSize: 13.5,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // ── Form card ───────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.60),
                  ),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Set your admin password',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Choose something strong — at least 8 characters '
                        'with a mix of letters and numbers.',
                        style: TextStyle(color: muted, fontSize: 13.5),
                      ),

                      const SizedBox(height: 20),

                      // New password
                      TextFormField(
                        controller: _newPassword,
                        enabled: !_loading,
                        obscureText: _hideNew,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) =>
                            _confirmFocus.requestFocus(),
                        decoration: InputDecoration(
                          labelText: 'New Password',
                          helperText: 'Minimum 8 characters.',
                          border: const OutlineInputBorder(),
                          prefixIcon:
                              const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _hideNew ? 'Show' : 'Hide',
                            icon: Icon(
                              _hideNew
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: _loading
                                ? null
                                : () => setState(
                                      () => _hideNew = !_hideNew,
                                    ),
                          ),
                        ),
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return 'Password is required';
                          if (t.length < 8) {
                            return 'At least 8 characters required';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 14),

                      // Confirm password
                      TextFormField(
                        controller: _confirmPassword,
                        focusNode: _confirmFocus,
                        enabled: !_loading,
                        obscureText: _hideConfirm,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) =>
                            _loading ? null : _submit(),
                        decoration: InputDecoration(
                          labelText: 'Confirm Password',
                          border: const OutlineInputBorder(),
                          prefixIcon:
                              const Icon(Icons.lock_reset_outlined),
                          suffixIcon: IconButton(
                            tooltip: _hideConfirm ? 'Show' : 'Hide',
                            icon: Icon(
                              _hideConfirm
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: _loading
                                ? null
                                : () => setState(
                                      () =>
                                          _hideConfirm = !_hideConfirm,
                                    ),
                          ),
                        ),
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) {
                            return 'Please confirm your password';
                          }
                          if (t != _newPassword.text.trim()) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 22),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: _loading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check_circle_outline),
                          label: Text(
                            _loading
                                ? 'Saving…'
                                : 'Set Password & Continue',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}