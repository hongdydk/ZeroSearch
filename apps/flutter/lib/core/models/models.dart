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
  });

  final String id;
  final String title;
  final int priceCredits;
  final int stock;
  final String category;
  final SellerSummaryModel seller;
  final String? description;
  final String? imageUrl;
  final String status;

  bool get isOfficial => seller.sellerType == 'platform';
}

class SellerSummaryModel {
  SellerSummaryModel({
    required this.id,
    required this.shopName,
    required this.sellerType,
  });

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
  });

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
}

class AdminSellerModel {
  AdminSellerModel({
    required this.id,
    required this.shopName,
    required this.userEmail,
    required this.status,
    required this.sellerType,
  });

  final String id;
  final String shopName;
  final String userEmail;
  final String status;
  final String sellerType;
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
  CatalogProductPageModel({required this.items, required this.total});

  final List<CatalogProductModel> items;
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

  String get cardTitle {
    final maker = manufacturer.trim();
    final product = title.trim();
    if (maker.isEmpty || product == maker || product.startsWith('$maker ')) {
      return product;
    }
    return '$maker $product';
  }
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
  });

  final String id;
  final String? optionLabel;
  final String? flavor;
  final int? volumeMl;
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
  });

  final String id;
  final String title;
  final String category;
  final int offerCount;
  final List<CatalogOfferModel> offers;
  final String? description;
  final String? imageUrl;
  final List<CatalogReferenceVariantModel> referenceVariants;
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
    this.description,
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
      description: json['description'] as String?,
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
  final String? description;

  bool get isCard => kind == 'card';
  bool get isOffer => kind == 'offer';
  bool get isPending => status == 'pending';

  String get cardTitle {
    final maker = manufacturer.trim();
    final product = title.trim();
    if (maker.isEmpty || product == maker || product.startsWith('$maker ')) {
      return product;
    }
    return '$maker $product';
  }
}
