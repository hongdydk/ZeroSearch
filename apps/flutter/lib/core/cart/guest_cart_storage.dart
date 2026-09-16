import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 비로그인 장바구니 한 줄. 새로고침 뒤에도 같은 오퍼는 한 줄로 유지한다.
class GuestCartLine {
  const GuestCartLine({
    required this.productId,
    required this.qty,
    this.productTitle,
    this.priceCredits,
    this.sellerId,
    this.shopName,
    this.sellerType,
  });

  final String productId;
  final int qty;
  final String? productTitle;
  final int? priceCredits;
  final String? sellerId;
  final String? shopName;
  final String? sellerType;

  GuestCartLine copyWith({
    String? productId,
    int? qty,
    String? productTitle,
    int? priceCredits,
    String? sellerId,
    String? shopName,
    String? sellerType,
  }) {
    return GuestCartLine(
      productId: productId ?? this.productId,
      qty: qty ?? this.qty,
      productTitle: productTitle ?? this.productTitle,
      priceCredits: priceCredits ?? this.priceCredits,
      sellerId: sellerId ?? this.sellerId,
      shopName: shopName ?? this.shopName,
      sellerType: sellerType ?? this.sellerType,
    );
  }

  Map<String, Object?> toJson() => {
        'productId': productId,
        'qty': qty,
        if (productTitle != null) 'productTitle': productTitle,
        if (priceCredits != null) 'priceCredits': priceCredits,
        if (sellerId != null) 'sellerId': sellerId,
        if (shopName != null) 'shopName': shopName,
        if (sellerType != null) 'sellerType': sellerType,
      };

  static GuestCartLine? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final id = (json['productId'] as String?)?.trim() ?? '';
    final qty = json['qty'];
    final parsedQty = qty is int ? qty : int.tryParse('$qty');
    if (!_idPattern.hasMatch(id) || parsedQty == null || parsedQty < 1) {
      return null;
    }
    return GuestCartLine(
      productId: id,
      qty: parsedQty.clamp(1, 99),
      productTitle: json['productTitle'] as String?,
      priceCredits: json['priceCredits'] is int ? json['priceCredits'] as int : null,
      sellerId: json['sellerId'] as String?,
      shopName: json['shopName'] as String?,
      sellerType: json['sellerType'] as String?,
    );
  }
}

final _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,80}$');

/// 웹에서는 SharedPreferences가 localStorage로 붙는다.
class GuestCartStorage {
  GuestCartStorage();

  static const prefsKey = 'mall:guestCart';

  List<GuestCartLine>? _cache;

  Future<List<GuestCartLine>> load() async {
    if (_cache != null) return List.of(_cache!);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) {
        _cache = [];
        return [];
      }
      final decoded = jsonDecode(raw);
      final list = decoded is List ? decoded : decoded is Map ? decoded['items'] : null;
      if (list is! List) {
        _cache = [];
        return [];
      }
      final parsed = <GuestCartLine>[];
      for (final item in list) {
        final line = GuestCartLine.tryParse(item);
        if (line != null) parsed.add(line);
      }
      _cache = parsed;
    } catch (_) {
      _cache = [];
    }
    return List.of(_cache!);
  }

  Future<void> add(
    String productId,
    int qty, {
    GuestCartLine? snapshot,
  }) async {
    if (!_idPattern.hasMatch(productId)) return;
    final nextQty = qty.clamp(1, 99);
    final lines = await load();
    final index = lines.indexWhere((line) => line.productId == productId);
    if (index < 0) {
      lines.add(
        (snapshot ?? GuestCartLine(productId: productId, qty: nextQty)).copyWith(
          productId: productId,
          qty: nextQty,
        ),
      );
    } else {
      final current = lines[index];
      final merged = (current.qty + nextQty).clamp(1, 99);
      lines[index] = (snapshot ?? current).copyWith(
        productId: productId,
        qty: merged,
        productTitle: snapshot?.productTitle ?? current.productTitle,
        priceCredits: snapshot?.priceCredits ?? current.priceCredits,
        sellerId: snapshot?.sellerId ?? current.sellerId,
        shopName: snapshot?.shopName ?? current.shopName,
        sellerType: snapshot?.sellerType ?? current.sellerType,
      );
    }
    await save(lines);
  }

  Future<void> updateQty(String productId, int qty) async {
    if (qty <= 0) {
      await remove(productId);
      return;
    }
    final lines = await load();
    final index = lines.indexWhere((line) => line.productId == productId);
    if (index < 0) return;
    lines[index] = lines[index].copyWith(qty: qty.clamp(1, 99));
    await save(lines);
  }

  Future<void> remove(String productId) async {
    final lines = await load();
    lines.removeWhere((line) => line.productId == productId);
    await save(lines);
  }

  Future<void> clear() async {
    await save(const []);
  }

  Future<void> save(List<GuestCartLine> lines) async {
    _cache = List.of(lines);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (lines.isEmpty) {
        await prefs.remove(prefsKey);
        return;
      }
      await prefs.setString(
        prefsKey,
        jsonEncode(lines.map((line) => line.toJson()).toList()),
      );
    } catch (_) {}
  }
}
