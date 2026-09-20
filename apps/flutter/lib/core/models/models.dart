class UserModel {
  UserModel({
    required this.id,
    required this.email,
    this.displayName,
    this.isAdmin = false,
  });

  final String id;
  final String email;
  final String? displayName;
  final bool isAdmin;

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id: json['id'] as String,
    email: json['email'] as String,
    displayName: json['displayName'] as String?,
    isAdmin: json['isAdmin'] as bool? ?? false,
  );
}

class ProductModel {
  ProductModel({
    required this.id,
    required this.title,
    required this.priceCredits,
    required this.stock,
    required this.category,
    required this.seller,
    this.description,
    this.imageUrl,
    this.status = 'published',
    this.catalogProductId,
    this.variantId,
    this.optionLabel,
    this.volumeMl,
    this.unitAmount,
    this.unit,
    this.packCount = 1,
    this.flavor,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    final sellerJson = json['seller'];
    return ProductModel(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      priceCredits: json['priceCredits'] as int? ?? 0,
      stock: json['stock'] as int? ?? 0,
      category: json['category'] as String? ?? '',
      seller: sellerJson is Map
          ? SellerSummaryModel.fromJson(Map<String, dynamic>.from(sellerJson))
          : SellerSummaryModel(id: '', shopName: '', sellerType: 'merchant'),
      description: json['description'] as String?,
      imageUrl: json['imageUrl'] as String?,
      status: json['status'] as String? ?? 'published',
      catalogProductId: json['catalogProductId'] as String?,
      variantId: json['variantId'] as String?,
      optionLabel: json['optionLabel'] as String?,
      volumeMl: json['volumeMl'] as int?,
      unitAmount: (json['unitAmount'] as num?)?.toDouble(),
      unit: json['unit'] as String?,
      packCount: json['packCount'] as int? ?? 1,
      flavor: json['flavor'] as String?,
    );
  }

  final String id;
  final String title;
  final int priceCredits;
  final int stock;
  final String category;
  final SellerSummaryModel seller;
  final String? description;
  final String? imageUrl;
  final String status;
  final String? catalogProductId;
  final String? variantId;
  final String? optionLabel;
  final int? volumeMl;
  final double? unitAmount;
  final String? unit;
  final int packCount;
  final String? flavor;

  bool get isOfficial => seller.sellerType == 'platform';
  bool get hasSellablePrice => priceCredits > 0;

  ProductModel copyWith({
    String? id,
    String? title,
    int? priceCredits,
    int? stock,
    String? category,
    SellerSummaryModel? seller,
    String? description,
    String? imageUrl,
    String? status,
    String? catalogProductId,
    String? variantId,
    String? optionLabel,
    int? volumeMl,
    double? unitAmount,
    String? unit,
    int? packCount,
    String? flavor,
  }) {
    return ProductModel(
      id: id ?? this.id,
      title: title ?? this.title,
      priceCredits: priceCredits ?? this.priceCredits,
      stock: stock ?? this.stock,
      category: category ?? this.category,
      seller: seller ?? this.seller,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      status: status ?? this.status,
      catalogProductId: catalogProductId ?? this.catalogProductId,
      variantId: variantId ?? this.variantId,
      optionLabel: optionLabel ?? this.optionLabel,
      volumeMl: volumeMl ?? this.volumeMl,
      unitAmount: unitAmount ?? this.unitAmount,
      unit: unit ?? this.unit,
      packCount: packCount ?? this.packCount,
      flavor: flavor ?? this.flavor,
    );
  }
}

class SellerProductCounts {
  const SellerProductCounts({
    this.all = 0,
    this.published = 0,
    this.pending = 0,
    this.soldOut = 0,
    this.hidden = 0,
  });

  factory SellerProductCounts.fromJson(Map<String, dynamic> json) {
    return SellerProductCounts(
      all: json['all'] as int? ?? 0,
      published: json['published'] as int? ?? 0,
      pending: json['pending'] as int? ?? 0,
      soldOut: json['soldOut'] as int? ?? 0,
      hidden: json['hidden'] as int? ?? 0,
    );
  }

  final int all;
  final int published;
  final int pending;
  final int soldOut;
  final int hidden;
}

class SellerProductListPage {
  const SellerProductListPage({
    required this.items,
    required this.total,
    this.counts = const SellerProductCounts(),
  });

  factory SellerProductListPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return SellerProductListPage(
      items: rawItems
          .whereType<Map>()
          .map((e) => ProductModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      total: json['total'] as int? ?? 0,
      counts: json['counts'] is Map
          ? SellerProductCounts.fromJson(Map<String, dynamic>.from(json['counts'] as Map))
          : const SellerProductCounts(),
    );
  }

  final List<ProductModel> items;
  final int total;
  final SellerProductCounts counts;
}

class SellerProductBulkFailure {
  const SellerProductBulkFailure({required this.id, required this.detail});

  factory SellerProductBulkFailure.fromJson(Map<String, dynamic> json) {
    return SellerProductBulkFailure(
      id: json['id'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
    );
  }

  final String id;
  final String detail;
}

class SellerProductBulkResult {
  const SellerProductBulkResult({
    this.updated = const [],
    this.failed = const [],
    this.successCount = 0,
    this.failCount = 0,
  });

  factory SellerProductBulkResult.fromJson(Map<String, dynamic> json) {
    final rawUpdated = json['updated'] as List<dynamic>? ?? [];
    final rawFailed = json['failed'] as List<dynamic>? ?? [];
    return SellerProductBulkResult(
      updated: rawUpdated
          .whereType<Map>()
          .map((e) => ProductModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      failed: rawFailed
          .whereType<Map>()
          .map(
            (e) => SellerProductBulkFailure.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(),
      successCount: json['successCount'] as int? ?? 0,
      failCount: json['failCount'] as int? ?? 0,
    );
  }

  final List<ProductModel> updated;
  final List<SellerProductBulkFailure> failed;
  final int successCount;
  final int failCount;
}

class CatalogProductSearchPage {
  const CatalogProductSearchPage({
    required this.items,
    required this.total,
  });

  final List<CatalogProductModel> items;
  final int total;
}

class SellerSummaryModel {
  SellerSummaryModel({
    required this.id,
    required this.shopName,
    required this.sellerType,
  });

  factory SellerSummaryModel.fromJson(Map<String, dynamic> json) {
    return SellerSummaryModel(
      id: json['id'] as String? ?? '',
      shopName: json['shopName'] as String? ?? '',
      sellerType: json['sellerType'] as String? ?? 'merchant',
    );
  }

  final String id;
  final String shopName;
  final String sellerType;
}

class SellerModel {
  SellerModel({
    required this.id,
    required this.shopName,
    required this.slug,
    required this.status,
    required this.sellerType,
    this.storeDescription,
    this.storeLogoUrl,
    this.storeBannerUrl,
  });

  factory SellerModel.fromJson(Map<String, dynamic> json) {
    return SellerModel(
      id: json['id'] as String? ?? '',
      shopName: json['shopName'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      status: json['status'] as String? ?? '',
      sellerType: json['sellerType'] as String? ?? 'merchant',
      storeDescription: json['storeDescription'] as String?,
      storeLogoUrl: json['storeLogoUrl'] as String?,
      storeBannerUrl: json['storeBannerUrl'] as String?,
    );
  }

  final String id;
  final String shopName;
  final String slug;
  final String status;
  final String sellerType;
}

class SellerOrderItemModel {
  SellerOrderItemModel({
    required this.id,
    required this.orderId,
    required this.productTitle,
    required this.qty,
    required this.lineTotalCredits,
    required this.fulfillmentStatus,
    this.shopName,
    this.sellerType,
  });

  final String id;
  final String orderId;
  final String productTitle;
  final int qty;
  final int lineTotalCredits;
  final String fulfillmentStatus;
  final String? shopName;
  final String? sellerType;

  SellerOrderItemModel copyWith({
    String? id,
    String? orderId,
    String? productTitle,
    int? qty,
    int? lineTotalCredits,
    String? fulfillmentStatus,
    String? shopName,
    String? sellerType,
  }) {
    return SellerOrderItemModel(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      productTitle: productTitle ?? this.productTitle,
      qty: qty ?? this.qty,
      lineTotalCredits: lineTotalCredits ?? this.lineTotalCredits,
      fulfillmentStatus: fulfillmentStatus ?? this.fulfillmentStatus,
      shopName: shopName ?? this.shopName,
      sellerType: sellerType ?? this.sellerType,
    );
  }
}

class AdminSellerModel {
  AdminSellerModel({
    required this.id,
    required this.shopName,
    required this.userEmail,
    required this.status,
    required this.sellerType,
    this.warningCount = 0,
    this.lastModerationAction,
    this.lastModerationReason,
  });

  factory AdminSellerModel.fromJson(Map<String, dynamic> json) {
    return AdminSellerModel(
      id: json['id'] as String? ?? '',
      shopName: json['shopName'] as String? ?? '',
      userEmail: json['userEmail'] as String? ?? '',
      status: json['status'] as String? ?? '',
      sellerType: json['sellerType'] as String? ?? 'merchant',
      warningCount: json['warningCount'] as int? ?? 0,
      lastModerationAction: json['lastModerationAction'] as String?,
      lastModerationReason: json['lastModerationReason'] as String?,
    );
  }

  final String id;
  final String shopName;
  final String userEmail;
  final String status;
  final String sellerType;
  final int warningCount;
  final String? lastModerationAction;
  final String? lastModerationReason;

  bool get isPlatform => sellerType == 'platform';

  AdminSellerModel copyWith({
    String? status,
    int? warningCount,
    String? lastModerationAction,
    String? lastModerationReason,
  }) {
    return AdminSellerModel(
      id: id,
      shopName: shopName,
      userEmail: userEmail,
      status: status ?? this.status,
      sellerType: sellerType,
      warningCount: warningCount ?? this.warningCount,
      lastModerationAction: lastModerationAction ?? this.lastModerationAction,
      lastModerationReason: lastModerationReason ?? this.lastModerationReason,
    );
  }
}

class CartItemModel {
  CartItemModel({
    required this.id,
    required this.productId,
    required this.productTitle,
    required this.qty,
    required this.priceCredits,
    required this.lineTotalCredits,
    required this.sellerId,
    required this.shopName,
    required this.sellerType,
    this.isAvailable = true,
    this.issueCode,
    this.issueMessage,
    this.maxQty = 99,
  });

  factory CartItemModel.fromJson(Map<String, dynamic> json) {
    return CartItemModel(
      id: json['id'] as String? ?? '',
      productId: json['productId'] as String? ?? '',
      productTitle: json['productTitle'] as String? ?? '',
      qty: json['qty'] as int? ?? 0,
      priceCredits: json['priceCredits'] as int? ?? 0,
      lineTotalCredits: json['lineTotalCredits'] as int? ?? 0,
      sellerId: json['sellerId'] as String? ?? '',
      shopName: json['shopName'] as String? ?? '',
      sellerType: json['sellerType'] as String? ?? 'merchant',
      isAvailable: json['isAvailable'] as bool? ?? true,
      issueCode: json['issueCode'] as String?,
      issueMessage: json['issueMessage'] as String?,
      maxQty: json['maxQty'] as int? ?? 99,
    );
  }

  final String id;
  final String productId;
  final String productTitle;
  final int qty;
  final int priceCredits;
  final int lineTotalCredits;
  final String sellerId;
  final String shopName;
  final String sellerType;
  final bool isAvailable;
  final String? issueCode;
  final String? issueMessage;
  final int maxQty;

  CartItemModel copyWith({
    String? id,
    String? productId,
    String? productTitle,
    int? qty,
    int? priceCredits,
    int? lineTotalCredits,
    String? sellerId,
    String? shopName,
    String? sellerType,
    bool? isAvailable,
    String? issueCode,
    String? issueMessage,
    int? maxQty,
  }) {
    return CartItemModel(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productTitle: productTitle ?? this.productTitle,
      qty: qty ?? this.qty,
      priceCredits: priceCredits ?? this.priceCredits,
      lineTotalCredits: lineTotalCredits ?? this.lineTotalCredits,
      sellerId: sellerId ?? this.sellerId,
      shopName: shopName ?? this.shopName,
      sellerType: sellerType ?? this.sellerType,
      isAvailable: isAvailable ?? this.isAvailable,
      issueCode: issueCode ?? this.issueCode,
      issueMessage: issueMessage ?? this.issueMessage,
      maxQty: maxQty ?? this.maxQty,
    );
  }
}

class CartModel {
  CartModel({
    required this.items,
    required this.totalCredits,
    this.checkoutBlocked = false,
  });

  static final empty = CartModel(
    items: const [],
    totalCredits: 0,
    checkoutBlocked: false,
  );

  factory CartModel.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return CartModel(
      items: rawItems
          .whereType<Map>()
          .map((e) => CartItemModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      totalCredits: json['totalCredits'] as int? ?? 0,
      checkoutBlocked: json['checkoutBlocked'] as bool? ?? false,
    );
  }

  final List<CartItemModel> items;
  final int totalCredits;
  final bool checkoutBlocked;

  int get totalQty => items.fold(0, (sum, item) => sum + item.qty);

  CartModel copyWith({
    List<CartItemModel>? items,
    int? totalCredits,
    bool? checkoutBlocked,
  }) {
    final nextItems = items ?? this.items;
    return CartModel(
      items: nextItems,
      totalCredits: totalCredits ??
          nextItems.fold(0, (sum, item) => sum + item.lineTotalCredits),
      checkoutBlocked: checkoutBlocked ?? this.checkoutBlocked,
    );
  }

  CartModel withItemQty(String productId, int qty) {
    final next = <CartItemModel>[];
    for (final item in items) {
      if (item.productId != productId) {
        next.add(item);
        continue;
      }
      final q = qty.clamp(1, item.maxQty < 1 ? 1 : item.maxQty);
      next.add(
        item.copyWith(qty: q, lineTotalCredits: item.priceCredits * q),
      );
    }
    return copyWith(items: next);
  }

  CartModel withoutItem(String productId) {
    return copyWith(
      items: [for (final item in items) if (item.productId != productId) item],
    );
  }

  CartModel addingOrMerging(CartItemModel incoming) {
    final next = <CartItemModel>[];
    var merged = false;
    for (final item in items) {
      if (item.productId != incoming.productId) {
        next.add(item);
        continue;
      }
      merged = true;
      final q = (item.qty + incoming.qty).clamp(1, item.maxQty < 1 ? 1 : item.maxQty);
      next.add(item.copyWith(qty: q, lineTotalCredits: item.priceCredits * q));
    }
    if (!merged) next.add(incoming);
    return copyWith(items: next);
  }
}

class CatalogProductPageModel {
  CatalogProductPageModel({
    required this.items,
    required this.total,
    this.availableFlavors = const [],
    this.hasVolumeMin2000 = false,
  });

  final List<CatalogProductModel> items;
  final int total;
  final List<String> availableFlavors;
  final bool hasVolumeMin2000;

  bool get hasMore => items.length < total;
}

class CatalogOfferBrowseModel {
  CatalogOfferBrowseModel({
    required this.id,
    required this.catalogProductId,
    required this.title,
    required this.priceCredits,
    required this.stock,
    required this.seller,
    this.manufacturer = '',
    this.optionLabel,
    this.flavor,
    this.volumeMl,
    this.imageUrl,
  });

  factory CatalogOfferBrowseModel.fromJson(Map<String, dynamic> json) {
    final sellerRaw = json['seller'];
    return CatalogOfferBrowseModel(
      id: json['id'] as String? ?? '',
      catalogProductId: json['catalogProductId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      manufacturer: json['manufacturer'] as String? ?? '',
      optionLabel: json['optionLabel'] as String?,
      flavor: json['flavor'] as String?,
      volumeMl: json['volumeMl'] as int?,
      priceCredits: json['priceCredits'] as int? ?? 0,
      stock: json['stock'] as int? ?? 0,
      imageUrl: json['imageUrl'] as String?,
      seller: sellerRaw is Map
          ? SellerSummaryModel(
              id: sellerRaw['id'] as String? ?? '',
              shopName: sellerRaw['shopName'] as String? ?? '',
              sellerType: sellerRaw['sellerType'] as String? ?? 'merchant',
            )
          : SellerSummaryModel(id: '', shopName: '', sellerType: 'merchant'),
    );
  }

  final String id;
  final String catalogProductId;
  final String title;
  final String manufacturer;
  final String? optionLabel;
  final String? flavor;
  final int? volumeMl;
  final int priceCredits;
  final int stock;
  final String? imageUrl;
  final SellerSummaryModel seller;

  bool get isOfficial => seller.sellerType == 'platform';

  String get cardTitle {
    final maker = manufacturer.trim();
    final product = title.trim();
    if (maker.isEmpty || product == maker || product.startsWith('$maker ')) {
      return product;
    }
    return '$maker $product';
  }

  String get optionLine {
    final parts = <String>[];
    if (optionLabel != null && optionLabel!.trim().isNotEmpty) {
      parts.add(optionLabel!.trim());
    }
    if (flavor != null && flavor!.trim().isNotEmpty) {
      parts.add(flavor!.trim());
    }
    if (volumeMl != null && volumeMl! > 0) {
      parts.add('${volumeMl}ml');
    }
    return parts.join(' · ');
  }
}

class CatalogOfferBrowsePageModel {
  CatalogOfferBrowsePageModel({required this.items, required this.total});

  final List<CatalogOfferBrowseModel> items;
  final int total;

  bool get hasMore => items.length < total;
}

class OrderItemModel {
  OrderItemModel({
    required this.id,
    required this.productId,
    required this.productTitle,
    required this.qty,
    required this.unitPriceCredits,
    required this.fulfillmentStatus,
    required this.shopName,
    required this.sellerType,
  });

  final String id;
  final String productId;
  final String productTitle;
  final int qty;
  final int unitPriceCredits;
  final String fulfillmentStatus;
  final String shopName;
  final String sellerType;

  bool get isOfficialShipping => sellerType == 'platform';
}

class ShippingAddressModel {
  ShippingAddressModel({
    required this.id,
    required this.recipientName,
    required this.phone,
    required this.zonecode,
    required this.address,
    required this.detailAddress,
    this.isDefault = false,
  });

  factory ShippingAddressModel.fromJson(Map<String, dynamic> json) {
    return ShippingAddressModel(
      id: json['id'] as String? ?? '',
      recipientName: json['recipientName'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      zonecode: json['zonecode'] as String? ?? '',
      address: json['address'] as String? ?? '',
      detailAddress: json['detailAddress'] as String? ?? '',
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }

  final String id;
  final String recipientName;
  final String phone;
  final String zonecode;
  final String address;
  final String detailAddress;
  final bool isDefault;

  String get line => '($zonecode) $address $detailAddress';
}

class OrderModel {
  OrderModel({
    required this.id,
    required this.status,
    required this.totalCredits,
    required this.items,
    this.shipping,
    this.createdAt,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    final rawShipping = json['shipping'];
    return OrderModel(
      id: json['id'] as String,
      status: json['status'] as String? ?? 'paid',
      totalCredits: json['totalCredits'] as int? ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      shipping: rawShipping is Map
          ? ShippingAddressModel.fromJson(Map<String, dynamic>.from(rawShipping))
          : null,
      items: rawItems.whereType<Map>().map((e) {
        final m = Map<String, dynamic>.from(e);
        return OrderItemModel(
          id: m['id'] as String? ?? '',
          productId: m['productId'] as String? ?? '',
          productTitle: m['productTitle'] as String? ?? '',
          qty: m['qty'] as int? ?? 0,
          unitPriceCredits: m['unitPriceCredits'] as int? ?? 0,
          fulfillmentStatus: m['fulfillmentStatus'] as String? ?? 'paid',
          shopName: m['shopName'] as String? ?? '',
          sellerType: m['sellerType'] as String? ?? 'merchant',
        );
      }).toList(),
    );
  }

  final String id;
  final String status;
  final int totalCredits;
  final List<OrderItemModel> items;
  final ShippingAddressModel? shipping;
  final DateTime? createdAt;
}

class TossPrepareModel {
  TossPrepareModel({
    required this.orderId,
    required this.amount,
    required this.orderName,
    required this.clientKey,
    required this.customerKey,
  });

  final String orderId;
  final int amount;
  final String orderName;
  final String clientKey;
  final String customerKey;
}

class TossPaymentStatusModel {
  TossPaymentStatusModel({
    required this.orderId,
    required this.status,
    this.localOrderId,
    this.failureMessage,
  });

  final String orderId;
  final String status;
  final String? localOrderId;
  final String? failureMessage;
}

class MembershipPlanModel {
  MembershipPlanModel({
    required this.id,
    required this.slug,
    required this.name,
    required this.priceCredits,
    required this.interval,
  });

  final String id;
  final String slug;
  final String name;
  final int priceCredits;
  final String interval;
}

class SubscriptionModel {
  SubscriptionModel({
    required this.id,
    required this.planSlug,
    required this.planName,
    required this.status,
    required this.currentPeriodEnd,
  });

  final String id;
  final String planSlug;
  final String planName;
  final String status;
  final DateTime currentPeriodEnd;
}

class CatalogVariantModel {
  const CatalogVariantModel({
    required this.id,
    required this.name,
    required this.optionLabel,
    required this.unitAmount,
    required this.unit,
    required this.packCount,
    this.imageUrl,
  });

  factory CatalogVariantModel.fromJson(Map<String, dynamic> json) => CatalogVariantModel(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '기본',
    optionLabel: json['optionLabel'] as String? ?? '',
    unitAmount: (json['unitAmount'] as num?)?.toDouble() ?? 0,
    unit: json['unit'] as String? ?? '',
    packCount: json['packCount'] as int? ?? 1,
    imageUrl: json['imageUrl'] as String?,
  );

  final String id;
  final String name;
  final String optionLabel;
  final double unitAmount;
  final String unit;
  final int packCount;
  final String? imageUrl;

  String get displayLabel => name == '기본' ? optionLabel : '$name · $optionLabel';
}

class CatalogProductModel {
  CatalogProductModel({
    required this.id,
    required this.title,
    required this.category,
    required this.offerCount,
    required this.priceUnit,
    required this.displayPriceLabel,
    this.manufacturer = '',
    this.description,
    this.imageUrl,
    this.medianUnitPrice,
    this.medianPriceCredits,
    this.volumeOptions = const [],
    this.variants = const [],
    this.l1Tags = const [],
    this.l2Tags = const [],
    this.storage,
  });

  factory CatalogProductModel.fromJson(Map<String, dynamic> json) {
    return CatalogProductModel(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      manufacturer: json['manufacturer'] as String? ?? '',
      category: json['category'] as String? ?? '',
      offerCount: json['offerCount'] as int? ?? 0,
      priceUnit: json['priceUnit'] as String? ?? 'credits',
      displayPriceLabel: json['displayPriceLabel'] as String? ?? '',
      description: json['description'] as String?,
      imageUrl: json['imageUrl'] as String?,
      medianUnitPrice: (json['medianUnitPrice'] as num?)?.toDouble(),
      medianPriceCredits: json['medianPriceCredits'] as int?,
      volumeOptions: (json['volumeOptions'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      variants: (json['variants'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => CatalogVariantModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      l1Tags: (json['l1Tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      l2Tags: (json['l2Tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      storage: json['storage'] as String?,
    );
  }

  final String id;
  final String title;
  final String manufacturer;
  final String category;
  final int offerCount;
  final String priceUnit;
  final String displayPriceLabel;
  final String? description;
  final String? imageUrl;
  final double? medianUnitPrice;
  final int? medianPriceCredits;
  final List<String> volumeOptions;
  final List<CatalogVariantModel> variants;
  final List<String> l1Tags;
  final List<String> l2Tags;
  final String? storage;

  String get cardTitle {
    final maker = manufacturer.trim();
    final product = title.trim();
    if (maker.isEmpty || product == maker || product.startsWith('$maker ')) {
      return product;
    }
    return '$maker $product';
  }
}

class GuestL1FacetItem {
  const GuestL1FacetItem({required this.name, required this.count});

  factory GuestL1FacetItem.fromJson(Map<String, dynamic> json) {
    return GuestL1FacetItem(
      name: json['name'] as String? ?? '',
      count: json['count'] as int? ?? 0,
    );
  }

  final String name;
  final int count;
}

class GuestL1FacetsModel {
  const GuestL1FacetsModel({
    required this.l1Tag,
    this.l2Tag = '',
    this.l2s = const [],
    required this.defaultAxis,
    this.brands = const [],
    this.menus = const [],
  });

  factory GuestL1FacetsModel.fromJson(Map<String, dynamic> json) {
    List<GuestL1FacetItem> parse(String key) {
      final raw = json[key] as List<dynamic>? ?? [];
      return raw
          .whereType<Map>()
          .map((e) => GuestL1FacetItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    return GuestL1FacetsModel(
      l1Tag: json['l1Tag'] as String? ?? '',
      l2Tag: json['l2Tag'] as String? ?? '',
      l2s: (json['l2s'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList(),
      defaultAxis: json['defaultAxis'] as String? ?? 'brand',
      brands: parse('brands'),
      menus: parse('menus'),
    );
  }

  final String l1Tag;
  final String l2Tag;
  final List<String> l2s;
  final String defaultAxis;
  final List<GuestL1FacetItem> brands;
  final List<GuestL1FacetItem> menus;
}

class CatalogOfferModel {
  CatalogOfferModel({
    required this.id,
    required this.priceCredits,
    required this.stock,
    required this.seller,
    this.optionLabel,
    this.flavor,
    this.volumeMl,
    this.variantId,
  });

  final String id;
  final String? optionLabel;
  final String? flavor;
  final int? volumeMl;
  final String? variantId;
  final int priceCredits;
  final int stock;
  final SellerSummaryModel seller;

  bool get isOfficial => seller.sellerType == 'platform';
}

class CatalogProductDetailModel {
  CatalogProductDetailModel({
    required this.id,
    required this.title,
    required this.category,
    required this.offerCount,
    required this.offers,
    this.description,
    this.imageUrl,
    this.referenceVariants = const [],
    this.variants = const [],
  });

  final String id;
  final String title;
  final String category;
  final int offerCount;
  final List<CatalogOfferModel> offers;
  final String? description;
  final String? imageUrl;
  final List<CatalogReferenceVariantModel> referenceVariants;
  final List<CatalogVariantModel> variants;

  factory CatalogProductDetailModel.fromJson(Map<String, dynamic> json) => CatalogProductDetailModel(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    category: json['category'] as String? ?? '',
    offerCount: json['offerCount'] as int? ?? 0,
    description: json['description'] as String?,
    imageUrl: json['imageUrl'] as String?,
    variants: (json['variants'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) => CatalogVariantModel.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    offers: (json['offers'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) {
          final row = Map<String, dynamic>.from(e);
          return CatalogOfferModel(
            id: row['id'] as String? ?? '',
            variantId: row['variantId'] as String?,
            optionLabel: row['optionLabel'] as String?,
            flavor: row['flavor'] as String?,
            volumeMl: row['volumeMl'] as int?,
            priceCredits: row['priceCredits'] as int? ?? 0,
            stock: row['stock'] as int? ?? 0,
            seller: SellerSummaryModel.fromJson(Map<String, dynamic>.from(row['seller'] as Map? ?? {})),
          );
        }).toList(),
    referenceVariants: (json['referenceVariants'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) {
          final row = Map<String, dynamic>.from(e);
          return CatalogReferenceVariantModel(
            originalTitle: row['originalTitle'] as String? ?? '',
            flavors: (row['flavors'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
            volumes: (row['volumes'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
          );
        }).toList(),
  );
}

class CatalogReferenceVariantModel {
  CatalogReferenceVariantModel({
    required this.originalTitle,
    this.flavors = const [],
    this.volumes = const [],
  });

  final String originalTitle;
  final List<String> flavors;
  final List<String> volumes;

  String get displayLabel {
    final parts = <String>[];
    if (flavors.isNotEmpty) {
      parts.add(flavors.join('/'));
    }
    if (volumes.isNotEmpty) {
      parts.add(volumes.join(', '));
    }
    if (parts.isEmpty) {
      return originalTitle;
    }
    return '${parts.join(' · ')} ($originalTitle)';
  }
}

class CatalogVariantProposalModel {
  const CatalogVariantProposalModel({required this.name, required this.unitAmount, required this.unit, required this.packCount});

  factory CatalogVariantProposalModel.fromJson(Map<String, dynamic> json) => CatalogVariantProposalModel(
    name: json['name'] as String? ?? '기본',
    unitAmount: (json['unitAmount'] as num?)?.toDouble() ?? 0,
    unit: json['unit'] as String? ?? '',
    packCount: json['packCount'] as int? ?? 1,
  );

  final String name;
  final double unitAmount;
  final String unit;
  final int packCount;

  String get displayLabel => '$name · $unitAmount$unit × $packCount';
}

class IntakeDraftModel {
  IntakeDraftModel({
    required this.id,
    required this.kind,
    required this.status,
    required this.sellerId,
    required this.shopName,
    required this.title,
    required this.category,
    required this.priceCredits,
    required this.stock,
    this.catalogProductId,
    this.manufacturer = '',
    this.imageUrl,
    this.flavor,
    this.optionLabel,
    this.volumeMl,
    this.unitAmount,
    this.unit,
    this.packCount = 1,
    this.description,
    this.suggestedL1Tags = const [],
    this.l1Tags = const [],
    this.visibility = 'public',
    this.variants = const [],
  });

  factory IntakeDraftModel.fromJson(Map<String, dynamic> json) {
    return IntakeDraftModel(
      id: json['id'] as String,
      kind: json['kind'] as String? ?? 'card',
      status: json['status'] as String? ?? 'pending',
      sellerId: json['sellerId'] as String? ?? '',
      shopName: json['shopName'] as String? ?? '',
      title: json['title'] as String? ?? '',
      category: json['category'] as String? ?? '',
      priceCredits: json['priceCredits'] as int? ?? 0,
      stock: json['stock'] as int? ?? 0,
      catalogProductId: json['catalogProductId'] as String?,
      manufacturer: json['manufacturer'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      flavor: json['flavor'] as String?,
      optionLabel: json['optionLabel'] as String?,
      volumeMl: json['volumeMl'] as int?,
      unitAmount: (json['unitAmount'] as num?)?.toDouble(),
      unit: json['unit'] as String?,
      packCount: json['packCount'] as int? ?? 1,
      description: json['description'] as String?,
      suggestedL1Tags: (json['suggestedL1Tags'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .map(
            (e) => (
              tag: e['tag'] as String? ?? '',
              confidence: e['confidence'] as String? ?? 'mid',
            ),
          )
          .where((e) => e.tag.isNotEmpty)
          .toList(),
      l1Tags: (json['l1Tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      visibility: json['visibility'] as String? ?? 'public',
      variants: (json['variants'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((row) => CatalogVariantProposalModel.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
    );
  }

  final String id;
  final String kind;
  final String status;
  final String sellerId;
  final String shopName;
  final String title;
  final String category;
  final int priceCredits;
  final int stock;
  final String? catalogProductId;
  final String manufacturer;
  final String? imageUrl;
  final String? flavor;
  final String? optionLabel;
  final int? volumeMl;
  final double? unitAmount;
  final String? unit;
  final int packCount;
  final String? description;
  final List<({String tag, String confidence})> suggestedL1Tags;
  final List<String> l1Tags;
  final String visibility;
  final List<CatalogVariantProposalModel> variants;

  bool get isCard => kind == 'card';
  bool get isOffer => kind == 'offer';
  bool get isPending => status == 'pending';
  bool get hasSellablePrice => priceCredits > 0;
  bool get isPublic => visibility != 'hidden';

  String get cardTitle {
    final maker = manufacturer.trim();
    final product = title.trim();
    if (maker.isEmpty || product == maker || product.startsWith('$maker ')) {
      return product;
    }
    return '$maker $product';
  }
}

class AdminCatalogProductModel {
  AdminCatalogProductModel({
    required this.id,
    required this.title,
    required this.manufacturer,
    required this.category,
    required this.status,
    required this.offerCount,
    required this.publishedOfferCount,
    this.shopCount = 0,
    this.medianUnitPrice,
    this.medianPriceCredits,
    this.priceUnit = 'credits',
    this.displayPriceLabel = '원',
    this.imageUrl,
    this.l1Tags = const [],
  });

  factory AdminCatalogProductModel.fromJson(Map<String, dynamic> json) {
    return AdminCatalogProductModel(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      manufacturer: json['manufacturer'] as String? ?? '',
      category: json['category'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      offerCount: json['offerCount'] as int? ?? 0,
      publishedOfferCount: json['publishedOfferCount'] as int? ?? 0,
      shopCount: json['shopCount'] as int? ?? 0,
      medianUnitPrice: (json['medianUnitPrice'] as num?)?.toDouble(),
      medianPriceCredits: json['medianPriceCredits'] as int?,
      priceUnit: json['priceUnit'] as String? ?? 'credits',
      displayPriceLabel: json['displayPriceLabel'] as String? ?? '원',
      imageUrl: json['imageUrl'] as String?,
      l1Tags: (json['l1Tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  final String id;
  final String title;
  final String manufacturer;
  final String category;
  final String status;
  final int offerCount;
  final int publishedOfferCount;
  final int shopCount;
  final double? medianUnitPrice;
  final int? medianPriceCredits;
  final String priceUnit;
  final String displayPriceLabel;
  final String? imageUrl;
  final List<String> l1Tags;

  bool get isRetired => status == 'retired';

  String get cardTitle {
    final maker = manufacturer.trim();
    final product = title.trim();
    if (maker.isEmpty || product == maker || product.startsWith('$maker ')) {
      return product;
    }
    return '$maker $product';
  }
}

class AdminCatalogProductPageModel {
  const AdminCatalogProductPageModel({
    required this.items,
    required this.total,
    this.offset = 0,
    this.limit = 24,
  });

  factory AdminCatalogProductPageModel.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map(
          (e) => AdminCatalogProductModel.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList();
    return AdminCatalogProductPageModel(
      items: items,
      total: json['total'] as int? ?? items.length,
      offset: json['offset'] as int? ?? 0,
      limit: json['limit'] as int? ?? 24,
    );
  }

  final List<AdminCatalogProductModel> items;
  final int total;
  final int offset;
  final int limit;
}

class SellerModerationEventModel {
  SellerModerationEventModel({
    required this.id,
    required this.action,
    required this.reason,
    this.createdAt,
    this.adminEmail,
  });

  factory SellerModerationEventModel.fromJson(Map<String, dynamic> json) {
    return SellerModerationEventModel(
      id: json['id'] as String? ?? '',
      action: json['action'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      createdAt: json['createdAt'] as String?,
      adminEmail: json['adminEmail'] as String?,
    );
  }

  final String id;
  final String action;
  final String reason;
  final String? createdAt;
  final String? adminEmail;

  String get actionLabel => switch (action) {
        'warn' => '경고',
        'suspend' => '정지',
        'unsuspend' => '정지 해제',
        'remove' => '판매자 해제',
        _ => action,
      };
}

class StorefrontModel {
  const StorefrontModel({
    required this.id,
    required this.shopName,
    required this.slug,
    required this.sellerType,
    required this.productCount,
    this.storeDescription,
    this.storeLogoUrl,
    this.storeBannerUrl,
  });

  factory StorefrontModel.fromJson(Map<String, dynamic> json) => StorefrontModel(
        id: json['id'] as String? ?? '',
        shopName: json['shopName'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        sellerType: json['sellerType'] as String? ?? 'merchant',
        productCount: json['productCount'] as int? ?? 0,
        storeDescription: json['storeDescription'] as String?,
        storeLogoUrl: json['storeLogoUrl'] as String?,
        storeBannerUrl: json['storeBannerUrl'] as String?,
      );

  final String id;
  final String shopName;
  final String slug;
  final String sellerType;
  final String? storeDescription;
  final String? storeLogoUrl;
  final String? storeBannerUrl;
  final int productCount;
  final String? storeDescription;
  final String? storeLogoUrl;
  final String? storeBannerUrl;

  bool get isOfficial => sellerType == 'platform';
}

class StorefrontDetailModel extends StorefrontModel {
  const StorefrontDetailModel({
    required super.id,
    required super.shopName,
    required super.slug,
    required super.sellerType,
    required super.productCount,
    super.storeDescription,
    super.storeLogoUrl,
    super.storeBannerUrl,
    required this.products,
  });

  factory StorefrontDetailModel.fromJson(Map<String, dynamic> json) {
    final store = StorefrontModel.fromJson(json);
    return StorefrontDetailModel(
      id: store.id,
      shopName: store.shopName,
      slug: store.slug,
      sellerType: store.sellerType,
      productCount: store.productCount,
      storeDescription: store.storeDescription,
      storeLogoUrl: store.storeLogoUrl,
      storeBannerUrl: store.storeBannerUrl,
      products: (json['products'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((item) => ProductModel.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }

  final List<ProductModel> products;
}
