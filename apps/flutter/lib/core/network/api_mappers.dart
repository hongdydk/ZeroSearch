import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart';
import 'package:shopping_mall_api/shopping_mall_api.dart' as gen;

import '../models/models.dart';

UserModel userModelFromGenerated(gen.UserResponse user) => UserModel(
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      isAdmin: user.isAdmin ?? false,
    );

ProductModel productModelFromGenerated(gen.ProductResponse product) => ProductModel(
      id: product.id,
      title: product.title,
      priceCredits: product.priceCredits,
      stock: product.stock,
      category: product.category,
      seller: sellerSummaryFromGenerated(product.seller),
      description: product.description,
      imageUrl: product.imageUrl,
      status: gen.serializers.serialize(
            product.status,
            specifiedType: const FullType(gen.ProductResponseStatusEnum),
          ) as String? ??
          'published',
    );

SellerSummaryModel sellerSummaryFromGenerated(gen.SellerSummary seller) => SellerSummaryModel(
      id: seller.id,
      shopName: seller.shopName,
      sellerType: gen.serializers.serialize(
            seller.sellerType,
            specifiedType: const FullType(gen.SellerSummarySellerTypeEnum),
          ) as String,
    );

SellerModel? sellerModelFromGenerated(gen.SellerResponse? seller) {
  if (seller == null) return null;
  return SellerModel(
    id: seller.id,
    shopName: seller.shopName,
    slug: seller.slug,
    status: gen.serializers.serialize(
          seller.status,
          specifiedType: const FullType(gen.SellerResponseStatusEnum),
        ) as String,
    sellerType: gen.serializers.serialize(
          seller.sellerType,
          specifiedType: const FullType(gen.SellerResponseSellerTypeEnum),
        ) as String,
  );
}

SellerOrderItemModel sellerOrderItemFromGenerated(gen.SellerOrderItemResponse item) =>
    SellerOrderItemModel(
      id: item.id,
      orderId: item.orderId,
      productTitle: item.productTitle,
      qty: item.qty,
      lineTotalCredits: item.lineTotalCredits,
      fulfillmentStatus: gen.serializers.serialize(
            item.fulfillmentStatus,
            specifiedType: const FullType(gen.SellerOrderItemResponseFulfillmentStatusEnum),
          ) as String,
    );

SellerOrderItemModel adminOrderItemFromGenerated(gen.AdminOrderItemResponse item) =>
    SellerOrderItemModel(
      id: item.id,
      orderId: item.orderId,
      productTitle: item.productTitle,
      qty: item.qty,
      lineTotalCredits: item.lineTotalCredits,
      fulfillmentStatus: gen.serializers.serialize(
            item.fulfillmentStatus,
            specifiedType: const FullType(gen.AdminOrderItemResponseFulfillmentStatusEnum),
          ) as String,
      shopName: item.shopName,
      sellerType: gen.serializers.serialize(
            item.sellerType,
            specifiedType: const FullType(gen.AdminOrderItemResponseSellerTypeEnum),
          ) as String,
    );

List<ProductModel> productListFromGenerated(BuiltList<gen.ProductResponse> products) =>
    products.map(productModelFromGenerated).toList();

CartItemModel cartItemFromGenerated(gen.CartItemResponse item) => CartItemModel(
      id: item.id,
      productId: item.productId,
      productTitle: item.productTitle,
      qty: item.qty,
      priceCredits: item.priceCredits,
      lineTotalCredits: item.lineTotalCredits,
      sellerId: item.sellerId,
      shopName: item.shopName,
      sellerType: gen.serializers.serialize(
            item.sellerType,
            specifiedType: const FullType(gen.CartItemResponseSellerTypeEnum),
          ) as String,
      isAvailable: item.isAvailable,
      issueCode: item.issueCode == null
          ? null
          : gen.serializers.serialize(
              item.issueCode,
              specifiedType: const FullType(gen.CartItemResponseIssueCodeEnum),
            ) as String,
      issueMessage: item.issueMessage,
      maxQty: item.maxQty,
    );

CartModel cartModelFromGenerated(gen.CartResponse cart) => CartModel(
      items: cart.items.map(cartItemFromGenerated).toList(),
      totalCredits: cart.totalCredits,
      checkoutBlocked: cart.checkoutBlocked,
    );

OrderItemModel orderItemFromGenerated(gen.OrderItemResponse item) => OrderItemModel(
      id: item.id,
      productId: item.productId,
      productTitle: item.productTitle,
      qty: item.qty,
      unitPriceCredits: item.unitPriceCredits,
      fulfillmentStatus: gen.serializers.serialize(
            item.fulfillmentStatus,
            specifiedType: const FullType(gen.OrderItemResponseFulfillmentStatusEnum),
          ) as String,
      shopName: item.shopName,
      sellerType: gen.serializers.serialize(
            item.sellerType,
            specifiedType: const FullType(gen.OrderItemResponseSellerTypeEnum),
          ) as String,
    );

OrderModel orderModelFromGenerated(gen.OrderResponse order) => OrderModel(
      id: order.id,
      status: _orderStatusWire(order.status),
      totalCredits: order.totalCredits,
      items: order.items.map(orderItemFromGenerated).toList(),
      createdAt: order.createdAt,
    );

List<OrderModel> orderListFromGenerated(BuiltList<gen.OrderResponse> orders) =>
    orders.map(orderModelFromGenerated).toList();

MembershipPlanModel membershipPlanFromGenerated(gen.MembershipPlanResponse plan) =>
    MembershipPlanModel(
      id: plan.id,
      slug: plan.slug,
      name: plan.name,
      priceCredits: plan.priceCredits,
      interval: plan.interval,
    );

List<MembershipPlanModel> membershipPlansFromGenerated(
  BuiltList<gen.MembershipPlanResponse> plans,
) =>
    plans.map(membershipPlanFromGenerated).toList();

SubscriptionModel? subscriptionFromGenerated(gen.MembershipResponse? membership) {
  final sub = membership?.subscription;
  if (sub == null) return null;
  return SubscriptionModel(
    id: sub.id,
    planSlug: sub.planSlug,
    planName: sub.planName,
    status: _subscriptionStatusWire(sub.status),
    currentPeriodEnd: sub.currentPeriodEnd,
  );
}

String _orderStatusWire(gen.OrderResponseStatusEnum status) =>
    gen.serializers.serialize(status, specifiedType: const FullType(gen.OrderResponseStatusEnum))
        as String;

String _subscriptionStatusWire(gen.SubscriptionResponseStatusEnum status) =>
    gen.serializers.serialize(
      status,
      specifiedType: const FullType(gen.SubscriptionResponseStatusEnum),
    ) as String;

Map<String, dynamic> adminStatsToMap(gen.AdminStatsResponse response) => {
      'userCount': response.userCount,
      'productCount': response.productCount,
      'orderCount': response.orderCount,
      'sellerCount': response.sellerCount,
      'pendingSellerCount': response.pendingSellerCount,
    };

Map<String, dynamic> adminUsersToMap(gen.AdminUserListResponse response) => {
      'items': response.items
          .map(
            (user) => {
              'id': user.id,
              'email': user.email,
              'displayName': user.displayName,
              'isAdmin': user.isAdmin,
              'createdAt': user.createdAt.toIso8601String(),
            },
          )
          .toList(),
      'total': response.total,
      'offset': response.offset,
      'limit': response.limit,
    };

Map<String, dynamic> dbResetResponseToMap(gen.DbResetResponse response) => {
      'mode': gen.serializers.serialize(
        response.mode,
        specifiedType: const FullType(gen.DbResetResponseModeEnum),
      ),
      'message': response.message,
    };

CatalogProductModel catalogProductModelFromGenerated(gen.CatalogProductListItem item) =>
    CatalogProductModel(
      id: item.id,
      title: item.title,
      category: item.category,
      description: item.description,
      imageUrl: item.imageUrl,
      offerCount: item.offerCount,
      medianUnitPrice: item.medianUnitPrice?.toDouble(),
      medianPriceCredits: item.medianPriceCredits,
      priceUnit: gen.serializers.serialize(
            item.priceUnit,
            specifiedType: const FullType(gen.CatalogProductListItemPriceUnitEnum),
          ) as String,
      displayPriceLabel: item.displayPriceLabel,
    );

List<CatalogProductModel> catalogProductListFromGenerated(
  BuiltList<gen.CatalogProductListItem> items,
) =>
    items.map(catalogProductModelFromGenerated).toList();

CatalogOfferModel catalogOfferFromGenerated(gen.CatalogOfferItem offer) => CatalogOfferModel(
      id: offer.id,
      optionLabel: offer.optionLabel,
      flavor: offer.flavor,
      volumeMl: offer.volumeMl,
      priceCredits: offer.priceCredits,
      stock: offer.stock,
      seller: sellerSummaryFromGenerated(offer.seller),
    );

CatalogProductDetailModel catalogProductDetailFromGenerated(gen.CatalogProductDetailResponse detail) =>
    CatalogProductDetailModel(
      id: detail.id,
      title: detail.title,
      category: detail.category,
      description: detail.description,
      imageUrl: detail.imageUrl,
      offerCount: detail.offerCount,
      offers: detail.offers.map(catalogOfferFromGenerated).toList(),
      referenceVariants: [
        for (final v in detail.referenceVariants ?? BuiltList<gen.CatalogReferenceVariant>())
          CatalogReferenceVariantModel(
            originalTitle: v.originalTitle,
            flavors: (v.flavors ?? BuiltList<String>()).toList(),
            volumes: (v.volumes ?? BuiltList<String>()).toList(),
            barcode: v.barcode,
          ),
      ],
    );
