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
  });

  final String id;
  final String productId;
  final String productTitle;
  final int qty;
  final int priceCredits;
  final int lineTotalCredits;
}

class CartModel {
  CartModel({
    required this.items,
    required this.totalCredits,
  });

  final List<CartItemModel> items;
  final int totalCredits;
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

class OrderModel {
  OrderModel({
    required this.id,
    required this.status,
    required this.totalCredits,
    required this.items,
    this.createdAt,
  });

  final String id;
  final String status;
  final int totalCredits;
  final List<OrderItemModel> items;
  final DateTime? createdAt;
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
    this.description,
    this.imageUrl,
    this.medianUnitPrice,
    this.medianPriceCredits,
  });

  final String id;
  final String title;
  final String category;
  final int offerCount;
  final String priceUnit;
  final String displayPriceLabel;
  final String? description;
  final String? imageUrl;
  final double? medianUnitPrice;
  final int? medianPriceCredits;
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
  });

  final String id;
  final String title;
  final String category;
  final int offerCount;
  final List<CatalogOfferModel> offers;
  final String? description;
  final String? imageUrl;
}
