import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Email + password sign-in.
///
/// Nothing can be written to the database without a session — the RLS policies
/// reject every anonymous write — so this gate comes before the rest of the app.
class AuthScreen extends StatefulWidget {
  /// Lets the user browse the sample data without an account.
  final VoidCallback onBrowseSample;

  const AuthScreen({super.key, required this.onBrowseSample});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _signUpMode = false;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    final auth = Supabase.instance.client.auth;
    try {
      if (_signUpMode) {
        final res = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
        );
        // With "Confirm email" enabled, sign-up returns no session and the
        // account stays dormant until the emailed link is clicked.
        if (res.session == null && mounted) {
          setState(() => _notice = '注册成功，请到邮箱点击验证链接后再登录。');
        }
      } else {
        await auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
      // On success the auth state stream swaps this screen out; no navigation
      // needed here.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.travel_explore,
                      size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('旅行日志',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    _signUpMode ? '创建一个账号' : '登录以同步你的记录',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.hintColor),
                  ),
                  const SizedBox(height: 28),

                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: '邮箱',
                      prefixIcon: Icon(Icons.alternate_email),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final s = v?.trim() ?? '';
                      if (s.isEmpty) return '请输入邮箱';
                      if (!s.contains('@') || !s.contains('.')) {
                        return '邮箱格式看起来不对';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: '密码',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                    onFieldSubmitted: (_) => _busy ? null : _submit(),
                    validator: (v) {
                      if ((v ?? '').isEmpty) return '请输入密码';
                      // Supabase enforces 6 as its own minimum.
                      if (_signUpMode && (v ?? '').length < 6) {
                        return '密码至少 6 位';
                      }
                      return null;
                    },
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    _Banner(
                      text: _error!,
                      color: theme.colorScheme.errorContainer,
                      textColor: theme.colorScheme.onErrorContainer,
                      icon: Icons.error_outline,
                    ),
                  ],
                  if (_notice != null) ...[
                    const SizedBox(height: 14),
                    _Banner(
                      text: _notice!,
                      color: theme.colorScheme.secondaryContainer,
                      textColor: theme.colorScheme.onSecondaryContainer,
                      icon: Icons.mark_email_unread_outlined,
                    ),
                  ],

                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_signUpMode ? '注册' : '登录'),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _signUpMode = !_signUpMode;
                              _error = null;
                              _notice = null;
                            }),
                    child: Text(_signUpMode ? '已有账号？去登录' : '还没有账号？去注册'),
                  ),

                  const Divider(height: 32),
                  TextButton.icon(
                    onPressed: _busy ? null : widget.onBrowseSample,
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('先用示例数据看看'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;
  final IconData icon;

  const _Banner({
    required this.text,
    required this.color,
    required this.textColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: textColor, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
