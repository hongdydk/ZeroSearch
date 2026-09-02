import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/page_form_scaffold.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await ref.read(authStateProvider.notifier).register(
            _email.text.trim(),
            _password.text,
            displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
          );
      if (mounted) context.go('/');
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
    return PageFormScaffold(
      maxWidth: 400,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('회원가입', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          TextField(controller: _email, decoration: const InputDecoration(labelText: '이메일')),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: const InputDecoration(labelText: '닉네임 (선택)')),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            decoration: const InputDecoration(labelText: '비밀번호 (6자 이상)'),
            obscureText: true,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: Text(_loading ? '가입 중…' : '가입'),
          ),
          TextButton(onPressed: () => context.go('/login'), child: const Text('로그인')),
        ],
      ),
    );
  }
}
