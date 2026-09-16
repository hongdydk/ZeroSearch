import '../models/models.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import 'guest_cart_storage.dart';

CartModel emptyCart() =>
    CartModel(items: const [], totalCredits: 0, checkoutBlocked: false);

GuestCartLine guestSnapshot({
  required String productId,
  required int qty,
  required String productTitle,
  required int priceCredits,
  required String sellerId,
  required String shopName,
  required String sellerType,
}) {
  return GuestCartLine(
    productId: productId,
    qty: qty.clamp(1, 99),
    productTitle: productTitle,
    priceCredits: priceCredits,
    sellerId: sellerId,
    shopName: shopName,
    sellerType: sellerType,
  );
}

String catalogOfferCartTitle(String catalogTitle, {String? optionLabel, String? flavor}) {
  final extra = [
    if (optionLabel != null && optionLabel.isNotEmpty) optionLabel,
    if (flavor != null && flavor.isNotEmpty) flavor,
  ].join(' · ');
  return extra.isEmpty ? catalogTitle : '$catalogTitle · $extra';
}

CartItemModel cartItemFromProduct(ProductModel product, int qty) {
  final safeQty = qty.clamp(1, 99);
  final maxQty = product.stock < 1 ? 0 : (product.stock > 99 ? 99 : product.stock);
  final available = product.status == 'published' && product.stock >= safeQty;
  String? issueCode;
  String? issueMessage;
  if (product.status != 'published') {
    issueCode = 'offer_unavailable';
    issueMessage = '판매가 종료된 상품입니다.';
  } else if (product.stock <= 0) {
    issueCode = 'out_of_stock';
    issueMessage = '품절된 상품입니다.';
  } else if (safeQty > product.stock) {
    issueCode = 'insufficient_stock';
    issueMessage = '재고가 ${product.stock}개만 남았습니다.';
  }
  return CartItemModel(
    id: product.id,
    productId: product.id,
    productTitle: product.title,
    qty: safeQty,
    priceCredits: product.priceCredits,
    lineTotalCredits: product.priceCredits * safeQty,
    sellerId: product.seller.id,
    shopName: product.seller.shopName,
    sellerType: product.seller.sellerType,
    isAvailable: available,
    issueCode: issueCode,
    issueMessage: issueMessage,
    maxQty: maxQty,
  );
}

CartItemModel cartItemFromGuestLine(GuestCartLine line) {
  final qty = line.qty.clamp(1, 99);
  final price = line.priceCredits ?? 0;
  return CartItemModel(
    id: line.productId,
    productId: line.productId,
    productTitle: line.productTitle?.trim().isNotEmpty == true
        ? line.productTitle!
        : '상품',
    qty: qty,
    priceCredits: price,
    lineTotalCredits: price * qty,
    sellerId: line.sellerId ?? '',
    shopName: line.shopName ?? '',
    sellerType: line.sellerType ?? 'merchant',
    isAvailable: false,
    issueCode: 'offer_unavailable',
    issueMessage: '판매가 종료된 상품입니다.',
    maxQty: 0,
  );
}

CartModel cartModelFromItems(List<CartItemModel> items) {
  final total = items.fold(0, (sum, item) => sum + item.lineTotalCredits);
  return CartModel(
    items: items,
    totalCredits: total,
    checkoutBlocked: items.any((item) => !item.isAvailable),
  );
}

Future<CartModel> loadGuestCart({
  required ApiClient api,
  required GuestCartStorage guest,
}) async {
  final lines = await guest.load();
  if (lines.isEmpty) return emptyCart();
  final items = <CartItemModel>[];
  for (final line in lines) {
    try {
      final product = await api.product(line.productId);
      items.add(cartItemFromProduct(product, line.qty));
    } catch (_) {
      items.add(cartItemFromGuestLine(line));
    }
  }
  return cartModelFromItems(items);
}

/// 로그인 후 게스트 줄을 사용자 카트에 합친다. 같은 오퍼는 서버가 한 줄로 더한다.
Future<void> mergeGuestCartIntoUser({
  required ApiClient api,
  required GuestCartStorage guest,
}) async {
  final lines = await guest.load();
  if (lines.isEmpty) return;
  for (final line in lines) {
    try {
      await api.addToCart(line.productId, qty: line.qty);
      await guest.remove(line.productId);
    } on ApiException catch (e) {
      final code = e.statusCode;
      if (code == 400 || code == 404) {
        await guest.remove(line.productId);
      }
    }
  }
}

Future<CartModel> loadVisibleCart({
  required ApiClient api,
  required GuestCartStorage guest,
  required bool isBuyer,
}) async {
  if (isBuyer) {
    await mergeGuestCartIntoUser(api: api, guest: guest);
    return api.cart();
  }
  return loadGuestCart(api: api, guest: guest);
}
