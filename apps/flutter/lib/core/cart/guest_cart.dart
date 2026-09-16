import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// 게스트 장바구니 한 줄. 제목·가격·수량을 로컬에 두고 수량 변경 때 product GET을 하지 않는다.
class GuestCartLine {
  const GuestCartLine({
    required this.productId,
    required this.productTitle,
    required this.qty,
    required this.priceCredits,
    required this.sellerId,
    required this.shopName,
    required this.sellerType,
    this.maxQty = 99,
  });

  final String productId;
  final String productTitle;
  final int qty;
  final int priceCredits;
  final String sellerId;
  final String shopName;
  final String sellerType;
  final int maxQty;

  GuestCartLine copyWith({int? qty}) {
    return GuestCartLine(
      productId: productId,
      productTitle: productTitle,
      qty: qty ?? this.qty,
      priceCredits: priceCredits,
      sellerId: sellerId,
      shopName: shopName,
      sellerType: sellerType,
      maxQty: maxQty,
    );
  }

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productTitle': productTitle,
        'qty': qty,
        'priceCredits': priceCredits,
        'sellerId': sellerId,
        'shopName': shopName,
        'sellerType': sellerType,
        'maxQty': maxQty,
      };

  factory GuestCartLine.fromJson(Map<String, dynamic> json) {
    return GuestCartLine(
      productId: json['productId'] as String? ?? '',
      productTitle: json['productTitle'] as String? ?? '',
      qty: json['qty'] as int? ?? 1,
      priceCredits: json['priceCredits'] as int? ?? 0,
      sellerId: json['sellerId'] as String? ?? '',
      shopName: json['shopName'] as String? ?? '',
      sellerType: json['sellerType'] as String? ?? 'merchant',
      maxQty: json['maxQty'] as int? ?? 99,
    );
  }

  CartItemModel toCartItem() {
    final q = qty < 1 ? 1 : qty;
    return CartItemModel(
      id: productId,
      productId: productId,
      productTitle: productTitle,
      qty: q,
      priceCredits: priceCredits,
      lineTotalCredits: priceCredits * q,
      sellerId: sellerId,
      shopName: shopName,
      sellerType: sellerType,
      maxQty: maxQty < 1 ? 99 : maxQty,
    );
  }

  static GuestCartLine fromCartItem(CartItemModel item) {
    return GuestCartLine(
      productId: item.productId,
      productTitle: item.productTitle,
      qty: item.qty,
      priceCredits: item.priceCredits,
      sellerId: item.sellerId,
      shopName: item.shopName,
      sellerType: item.sellerType,
      maxQty: item.maxQty,
    );
  }
}

CartModel cartModelFromGuestLines(List<GuestCartLine> lines) {
  final items = [for (final line in lines) if (line.productId.isNotEmpty) line.toCartItem()];
  return CartModel.empty.copyWith(items: items);
}

List<GuestCartLine> guestLinesFromCart(CartModel cart) {
  return [for (final item in cart.items) GuestCartLine.fromCartItem(item)];
}

abstract class GuestCartStore {
  Future<List<GuestCartLine>> load();

  Future<void> save(List<GuestCartLine> lines);

  Future<void> clear() => save(const []);
}

class PrefsGuestCartStore implements GuestCartStore {
  static const prefsKey = 'mall:guestCart.v1';

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<GuestCartLine>> load() async {
    final prefs = await _prefs();
    if (prefs == null) return const [];
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final row in decoded)
          if (row is Map)
            GuestCartLine.fromJson(Map<String, dynamic>.from(row)),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> save(List<GuestCartLine> lines) async {
    final prefs = await _prefs();
    if (prefs == null) return;
    try {
      if (lines.isEmpty) {
        await prefs.remove(prefsKey);
        return;
      }
      await prefs.setString(
        prefsKey,
        jsonEncode([for (final line in lines) line.toJson()]),
      );
    } catch (_) {}
  }

  @override
  Future<void> clear() => save(const []);
}

class MemoryGuestCartStore implements GuestCartStore {
  MemoryGuestCartStore([List<GuestCartLine>? seed]) : lines = [...?seed];

  List<GuestCartLine> lines;

  @override
  Future<List<GuestCartLine>> load() async => [...lines];

  @override
  Future<void> save(List<GuestCartLine> next) async {
    lines = [...next];
  }

  @override
  Future<void> clear() async {
    lines = [];
  }
}
