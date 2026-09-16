import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../routing/safe_next_path.dart';

/// 게스트 담기 후 로그인하면 같은 오퍼·수량으로 재시도한다.
class PendingCartAdd {
  const PendingCartAdd({required this.productId, required this.qty});

  static const offerKey = 'addOffer';
  static const qtyKey = 'addQty';

  final String productId;
  final int qty;

  static final _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,80}$');

  static PendingCartAdd? tryParse(Uri uri) {
    final id = uri.queryParameters[offerKey]?.trim() ?? '';
    final qty = int.tryParse(uri.queryParameters[qtyKey] ?? '');
    if (!_idPattern.hasMatch(id) || qty == null || qty < 1) return null;
    return PendingCartAdd(productId: id, qty: qty.clamp(1, 99));
  }
}

final pendingCartAddProvider = StateProvider<PendingCartAdd?>((ref) => null);

final pendingCartAddClaimedProvider = StateProvider<bool>((ref) => false);

Uri withPendingCartAdd(
  Uri location, {
  required String productId,
  required int qty,
}) {
  final path = location.path.isEmpty ? '/' : location.path;
  final q = Map<String, String>.from(location.queryParameters);
  q[PendingCartAdd.offerKey] = productId;
  q[PendingCartAdd.qtyKey] = '${qty.clamp(1, 99)}';
  return Uri(path: path, queryParameters: q);
}

String? stripPendingCartQuery(String? path) {
  final safe = safeNextPath(path);
  if (safe == null) return null;
  final uri = Uri.parse(safe);
  final q = Map<String, String>.from(uri.queryParameters)
    ..remove(PendingCartAdd.offerKey)
    ..remove(PendingCartAdd.qtyKey);
  if (q.isEmpty) return uri.path;
  return Uri(path: uri.path, queryParameters: q).toString();
}

void restorePendingCartAddFromNext(WidgetRef ref, String? next) {
  final path = safeNextPath(next);
  if (path == null) return;
  final parsed = PendingCartAdd.tryParse(Uri.parse(path));
  if (parsed == null) return;
  ref.read(pendingCartAddProvider.notifier).state ??= parsed;
}
