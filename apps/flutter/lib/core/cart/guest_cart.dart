import '../models/models.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import 'guest_cart_storage.dart';

export 'guest_cart_storage.dart';

CartModel emptyCart() => CartModel.empty;

GuestCartLine guestSnapshot({
  required String productId,
  required int qty,
  required String productTitle,
  required int priceCredits,
  required String sellerId,
  required String shopName,
  required String sellerType,
  int maxQty = 99,
}) {
  return GuestCartLine(
    productId: productId,
    qty: qty.clamp(1, 99),
    productTitle: productTitle,
    priceCredits: priceCredits,
    sellerId: sellerId,
    shopName: shopName,
    sellerType: sellerType,
    maxQty: maxQty < 1 ? 99 : maxQty,
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
    issueMessage = '요청한 수량을 준비하지 못했습니다.';
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

/// 게스트 스냅샷을 카트 줄로. 수량 변경 때 product GET을 하지 않는다.
CartItemModel cartItemFromGuestLine(GuestCartLine line) {
  final qty = line.qty.clamp(1, 99);
  final price = line.priceCredits ?? 0;
  final maxQty = line.maxQty ?? 99;
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
    maxQty: maxQty < 1 ? 99 : maxQty,
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

CartModel cartModelFromGuestLines(List<GuestCartLine> lines) {
  return cartModelFromItems([
    for (final line in lines)
      if (line.productId.isNotEmpty) cartItemFromGuestLine(line),
  ]);
}

List<GuestCartLine> guestLinesFromCart(CartModel cart) {
  return [
    for (final item in cart.items)
      GuestCartLine(
        productId: item.productId,
        qty: item.qty,
        productTitle: item.productTitle,
        priceCredits: item.priceCredits,
        sellerId: item.sellerId,
        shopName: item.shopName,
        sellerType: item.sellerType,
        maxQty: item.maxQty,
      ),
  ];
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
