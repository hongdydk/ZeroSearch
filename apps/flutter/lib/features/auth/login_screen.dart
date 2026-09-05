import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/login_portal.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../core/routing/safe_next_path.dart';
import '../../shared/widgets/page_form_scaffold.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.portal = LoginPortal.buyer, this.next});

  final LoginPortal portal;
  final String? next;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _loading = false;

  String _registerLocation() {
    if (widget.portal == LoginPortal.seller) {
      return '/register?next=/seller';
    }
    final next = safeNextPath(widget.next);
    if (next == null) return '/register';
    return '/register?next=${Uri.encodeQueryComponent(next)}';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await ref.read(authStateProvider.notifier).login(
            _email.text.trim(),
            _password.text,
            portal: widget.portal,
          );
      if (mounted) {
        context.go(safeNextPath(widget.next) ?? widget.portal.homePath);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final portal = widget.portal;
    return PageFormScaffold(
      maxWidth: 400,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(portal.loginTitle, style: Theme.of(context).textTheme.headlineMedium),
          if (portal == LoginPortal.seller) ...[
            const SizedBox(height: 8),
            Text(
              '입점 신청은 로그인 후 이 화면에서 진행합니다.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            decoration: const InputDecoration(labelText: '이메일'),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            decoration: const InputDecoration(labelText: '비밀번호'),
            obscureText: true,
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: Text(_loading ? '로그인 중…' : '로그인'),
          ),
          if (portal != LoginPortal.admin)
            TextButton(
              onPressed: () => context.go(_registerLocation()),
              child: const Text('회원가입'),
            ),
          if (portal == LoginPortal.buyer) ...[
            TextButton(
              onPressed: () => context.go('/seller'),
              child: const Text('판매자 센터'),
            ),
            TextButton(
              onPressed: () => context.go('/admin'),
              child: const Text('관리자'),
            ),
          ],
        ],
      ),
    );
  }
}
