import 'package:flutter/material.dart';

/// 클릭한 동작의 응답이 오기 전에 같은 키를 다시 누르지 못하게 한다.
mixin AsyncBusyState<T extends StatefulWidget> on State<T> {
  final Set<String> _busyKeys = <String>{};

  bool isBusy([String? key]) =>
      key == null ? _busyKeys.isNotEmpty : _busyKeys.contains(key);

  Future<void> runBusy(String key, Future<void> Function() action) async {
    if (_busyKeys.contains(key)) return;
    setState(() => _busyKeys.add(key));
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busyKeys.remove(key));
    }
  }
}

Widget busyProgress({double size = 16}) {
  return SizedBox(
    width: size,
    height: size,
    child: const CircularProgressIndicator(strokeWidth: 2),
  );
}
