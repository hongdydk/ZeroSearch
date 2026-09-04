import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:built_value/serializer.dart';
import 'package:shopping_mall_api/shopping_mall_api.dart' as gen;

import '../auth/login_portal.dart';
import '../config/api_config.dart';
import '../models/models.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';
import 'api_mappers.dart';

typedef TokenReader = Future<String?> Function();

/// `baseUrl/` + `/path` 결합 시 `//` 404 방지: base는 끝 `/` 하나, path는 앞 `/` 제거.
void _normalizeDioRequest(RequestOptions options) {
  if (options.path.startsWith('http')) return;
  final base = ApiConfig.normalizeBaseUrl(options.baseUrl);
  options.baseUrl = '$base/';
  options.path = options.path.replaceFirst(RegExp(r'^/+'), '');
}

class ApiClient {
  ApiClient({TokenReader? tokenReader})
      : _tokenReader = tokenReader ?? TokenStorage().read {
    _dio = Dio(
      BaseOptions(
        baseUrl: '${ApiConfig.baseUrl}/',
        connectTimeout: ApiConfig.defaultTimeout,
        receiveTimeout: ApiConfig.defaultTimeout,
        headers: {'Content-Type': 'application/json'},
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          _normalizeDioRequest(options);
          final token = await _tokenReader();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          if (options.data is FormData) {
            options.headers.remove('Content-Type');
          }
          handler.next(options);
        },
        onError: (error, handler) {
          handler.reject(error);
        },
      ),
    );
    _generated = gen.ShoppingMallApi(
      dio: _dio,
      interceptors: [],
    );
  }

  late final Dio _dio;
  late final gen.ShoppingMallApi _generated;
  final TokenReader _tokenReader;

  Dio get dio => _dio;

  Future<T> _generatedCall<T>(Future<Response<T>> Function() call) async {
    try {
      final response = await call();
      final data = response.data;
      if (data == null) {
        throw ApiException('응답 데이터가 없습니다.');
      }
      return data;
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  ApiException _apiExceptionFromDio(DioException e) {
    if (e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionTimeout) {
      return ApiException('요청 시간이 초과되었습니다. 잠시 후 다시 시도하세요.');
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.unknown) {
      return ApiException(
        '연결이 끊겼습니다. 서버가 꺼진 것은 아닐 수 있습니다. 요청이 길면 다시 시도하세요.',
      );
    }
    final status = e.response?.statusCode;
    final data = e.response?.data;
    Object? detail;
    var message = '요청에 실패했습니다.';
    if (data is Map<String, dynamic>) {
      detail = data['detail'];
      if (detail is String) {
        message = detail;
      } else if (detail != null) {
        message = detail.toString();
      }
    } else if (data is String) {
      message = data;
    }
    return ApiException(message, statusCode: status, detail: detail);
  }

  Future<String> login(
    String email,
    String password, {
    LoginPortal portal = LoginPortal.buyer,
  }) async {
    final data = await _generatedCall(
      () => _generated.getAuthApi().loginAuthLoginPost(
            loginRequest: gen.LoginRequest((b) => b
              ..email = email
              ..password = password
              ..portal = _loginRequestPortal(portal)),
          ),
    );
    return data.accessToken;
  }

  Future<String> register(String email, String password, {String? displayName}) async {
    final data = await _generatedCall(
      () => _generated.getAuthApi().registerAuthRegisterPost(
            registerRequest: gen.RegisterRequest((b) => b
              ..email = email
              ..password = password
              ..displayName = displayName),
          ),
    );
    return data.accessToken;
  }

  Future<UserModel> me() async {
    final data = await _generatedCall(() => _generated.getAuthApi().meAuthMeGet());
    return userModelFromGenerated(data);
  }

  Future<int> credits() async {
    final data = await _generatedCall(
      () => _generated.getCreditsApi().myCreditsMeCreditsGet(),
    );
    return data.balance;
  }

  Future<List<ProductModel>> products({int offset = 0, int limit = 50}) async {
    final data = await _generatedCall(
      () => _generated.getProductsApi().getProductsProductsGet(
            offset: offset,
            limit: limit,
          ),
    );
    return productListFromGenerated(data.items);
  }

  Future<List<CatalogProductModel>> catalogProducts({
    String? q,
    String? category,
    String? flavor,
    int? volumeMlMin,
    int? volumeMlMax,
    int offset = 0,
    int limit = 50,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'catalog-products',
        queryParameters: {
          if (q != null && q.isNotEmpty) 'q': q,
          if (category != null && category.isNotEmpty) 'category': category,
          if (flavor != null && flavor.isNotEmpty) 'flavor': flavor,
          if (volumeMlMin != null) 'volumeMlMin': volumeMlMin,
          if (volumeMlMax != null) 'volumeMlMax': volumeMlMax,
          'offset': offset,
          'limit': limit,
        },
      );
      final items = response.data?['items'] as List<dynamic>? ?? [];
      return items
          .whereType<Map>()
          .map((e) => CatalogProductModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<CatalogProductDetailModel> catalogProduct(
    String id, {
    String? flavor,
    int? volumeMlMin,
    int? volumeMlMax,
  }) async {
    final data = await _generatedCall(
      () => _generated.getCatalogProductsApi().getCatalogProductByIdCatalogProductsCatalogIdGet(
            catalogId: id,
            flavor: flavor,
            volumeMlMin: volumeMlMin,
            volumeMlMax: volumeMlMax,
          ),
    );
    return catalogProductDetailFromGenerated(data);
  }

  Future<ProductModel> product(String id) async {
    final data = await _generatedCall(
      () => _generated.getProductsApi().getProductByIdProductsProductIdGet(productId: id),
    );
    return productModelFromGenerated(data);
  }

  Future<CartModel> cart() async {
    final data = await _generatedCall(
      () => _generated.getCartApi().readCartMeCartGet(),
    );
    return cartModelFromGenerated(data);
  }

  Future<CartModel> addToCart(String productId, {int qty = 1}) async {
    final data = await _generatedCall(
      () => _generated.getCartApi().createCartItemMeCartPost(
            cartAddRequest: gen.CartAddRequest((b) => b
              ..productId = productId
              ..qty = qty),
          ),
    );
    return cartModelFromGenerated(data);
  }

  Future<CartModel> updateCartItem(String productId, int qty) async {
    final data = await _generatedCall(
      () => _generated.getCartApi().updateCartMeCartPut(
            cartUpdateRequest: gen.CartUpdateRequest((b) => b
              ..productId = productId
              ..qty = qty),
          ),
    );
    return cartModelFromGenerated(data);
  }

  Future<CartModel> removeFromCart(String productId) async {
    final data = await _generatedCall(
      () => _generated.getCartApi().deleteCartItemMeCartDelete(
            cartRemoveRequest: gen.CartRemoveRequest((b) => b..productId = productId),
          ),
    );
    return cartModelFromGenerated(data);
  }

  Future<OrderModel> checkout() async {
    final data = await _generatedCall(
      () => _generated.getOrdersApi().createOrderMeOrdersPost(),
    );
    return orderModelFromGenerated(data.order);
  }

  Future<List<OrderModel>> orders() async {
    final data = await _generatedCall(
      () => _generated.getOrdersApi().readOrdersMeOrdersGet(),
    );
    return orderListFromGenerated(data.items);
  }

  Future<OrderModel> order(String id) async {
    final data = await _generatedCall(
      () => _generated.getOrdersApi().readOrderMeOrdersOrderIdGet(orderId: id),
    );
    return orderModelFromGenerated(data);
  }

  Future<List<MembershipPlanModel>> membershipPlans() async {
    final data = await _generatedCall(
      () => _generated.getMembershipApi().getMembershipPlansMembershipPlansGet(),
    );
    return membershipPlansFromGenerated(data.items);
  }

  Future<SubscriptionModel?> myMembership() async {
    final data = await _generatedCall(
      () => _generated.getMembershipApi().readMembershipMeMembershipGet(),
    );
    return subscriptionFromGenerated(data);
  }

  Future<SubscriptionModel> subscribe(String planSlug) async {
    final data = await _generatedCall(
      () => _generated.getMembershipApi().subscribeMembershipMeMembershipSubscribePost(
            subscribeRequest: gen.SubscribeRequest((b) => b..planSlug = planSlug),
          ),
    );
    return SubscriptionModel(
      id: data.id,
      planSlug: data.planSlug,
      planName: data.planName,
      status: gen.serializers.serialize(
        data.status,
        specifiedType: const FullType(gen.SubscriptionResponseStatusEnum),
      ) as String,
      currentPeriodEnd: data.currentPeriodEnd,
    );
  }

  Future<Map<String, dynamic>> adminStats() async {
    final data = await _generatedCall(
      () => _generated.getAdminApi().adminStatsAdminStatsGet(),
    );
    return adminStatsToMap(data);
  }

  Future<Map<String, dynamic>> adminUsers() async {
    final data = await _generatedCall(
      () => _generated.getAdminApi().listUsersAdminUsersGet(),
    );
    return adminUsersToMap(data);
  }

  Future<void> adminGrantCredits(String userId, int amount) async {
    try {
      await _generated.getAdminApi().grantUserCreditsAdminUsersUserIdCreditsPost(
            userId: userId,
            adminCreditGrantRequest: gen.AdminCreditGrantRequest((b) => b..amount = amount),
          );
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<void> adminPromote(String userId) async {
    try {
      await _generated.getAdminApi().promoteUserAdminUsersUserIdPromotePost(
            userId: userId,
          );
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<Map<String, dynamic>> adminDbReset(String mode) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'admin/db/reset',
        data: {'confirm': 'RESET', 'mode': mode},
        options: Options(
          receiveTimeout: const Duration(minutes: 15),
        ),
      );
      return response.data ?? {};
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<SellerModel?> sellerMe() async {
    final data = await _generatedCall(() => _generated.getSellerApi().sellerMeSellerMeGet());
    return sellerModelFromGenerated(data);
  }

  Future<SellerModel> sellerApply(String shopName) async {
    final data = await _generatedCall(
      () => _generated.getSellerApi().sellerApplySellerApplyPost(
            sellerApplyRequest: gen.SellerApplyRequest((b) => b..shopName = shopName),
          ),
    );
    return sellerModelFromGenerated(data)!;
  }

  Future<List<CatalogProductModel>> sellerSearchCatalog({
    String? q,
    String? category,
    int offset = 0,
    int limit = 30,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'seller/catalog-products',
        queryParameters: {
          if (q != null && q.isNotEmpty) 'q': q,
          if (category != null && category.isNotEmpty) 'category': category,
          'offset': offset,
          'limit': limit,
        },
      );
      final items = response.data?['items'] as List<dynamic>? ?? [];
      return items
          .whereType<Map>()
          .map((e) => CatalogProductModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  static const _importMaxBytes = 4 * 1024 * 1024;
  static const _importMaxRows = 20000;

  Future<({int sourceRows, int upserted})> adminImportCatalog(
    List<int> bytes,
    String filename, {
    void Function(double fraction)? onSendProgress,
    void Function()? onProcessing,
  }) async {
    if (bytes.length > _importMaxBytes) {
      throw ApiException('파일이 너무 큽니다. data/aihub-catalog.csv만 올리세요.');
    }
    late final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw ApiException('CSV는 UTF-8이어야 합니다.');
    }
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty) {
      throw ApiException('빈 파일입니다.');
    }
    final dataLines = [
      for (final line in lines.skip(1))
        if (line.trim().isNotEmpty) line,
    ];
    if (dataLines.length > _importMaxRows) {
      throw ApiException('행이 너무 많습니다. data/aihub-catalog.csv만 올리세요.');
    }
    if (dataLines.isEmpty) {
      throw ApiException('데이터 행이 없습니다.');
    }

    onSendProgress?.call(0);
    try {
      final started = await _dio.post<Map<String, dynamic>>(
        'admin/catalog/import-jobs',
        data: {'csv': text},
      );
      final jobId = started.data?['jobId'] as String?;
      if (jobId == null || jobId.isEmpty) {
        throw ApiException('가져오기 작업을 시작하지 못했습니다.');
      }
      onProcessing?.call();
      onSendProgress?.call(0.15);

      var pulse = 0.15;
      final deadline = DateTime.now().add(const Duration(minutes: 10));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final polled = await _dio.get<Map<String, dynamic>>(
          'admin/catalog/import-jobs/$jobId',
        );
        final data = polled.data ?? {};
        final status = data['status'] as String? ?? '';
        final sourceRows = data['sourceRows'] as int? ?? 0;
        final upserted = data['upserted'] as int? ?? 0;
        if (sourceRows > 0) {
          onSendProgress?.call((upserted / sourceRows).clamp(0.15, 0.99));
        } else {
          pulse = (pulse + 0.05).clamp(0.15, 0.9);
          onSendProgress?.call(pulse);
        }
        if (status == 'done') {
          onSendProgress?.call(1);
          return (sourceRows: sourceRows, upserted: upserted);
        }
        if (status == 'error') {
          throw ApiException(
            data['error'] as String? ?? '카탈로그 반영에 실패했습니다.',
          );
        }
      }
      throw ApiException('반영이 너무 오래 걸립니다. 초기화가 끝나면 다시 올리세요.');
    } on ApiException {
      rethrow;
    } on DioException catch (e) {
      final mapped = _apiExceptionFromDio(e);
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.unknown) {
        throw ApiException(
          '업로드 연결이 끊겼습니다. 초기화가 끝난 뒤 data/aihub-catalog.csv만 다시 올리세요.',
        );
      }
      throw mapped;
    }
  }

  Future<List<ProductModel>> sellerProducts() async {
    final data = await _generatedCall(
      () => _generated.getSellerApi().sellerListProductsSellerProductsGet(),
    );
    return productListFromGenerated(data);
  }

  Future<ProductModel> sellerCreateProduct({
    required String title,
    required int priceCredits,
    required int stock,
    required String category,
    String? description,
    String status = 'draft',
    String? catalogProductId,
    String? optionLabel,
    int? volumeMl,
    String? flavor,
  }) async {
    final data = await _generatedCall(
      () => _generated.getSellerApi().sellerCreateProductSellerProductsPost(
            sellerProductCreateRequest: gen.SellerProductCreateRequest((b) => b
              ..title = title
              ..priceCredits = priceCredits
              ..stock = stock
              ..category = category
              ..description = description
              ..status = gen.SellerProductCreateRequestStatusEnum.valueOf(
                status == 'published' ? 'published' : 'draft',
              )
              ..catalogProductId = catalogProductId
              ..optionLabel = optionLabel
              ..volumeMl = volumeMl
              ..flavor = flavor),
          ),
    );
    return productModelFromGenerated(data);
  }

  Future<List<SellerOrderItemModel>> sellerOrders() async {
    final data = await _generatedCall(
      () => _generated.getSellerApi().sellerListOrdersSellerOrdersGet(),
    );
    return data.items.map(sellerOrderItemFromGenerated).toList();
  }

  Future<void> sellerUpdateOrderStatus(String itemId, String status) async {
    await _generatedCall(
      () => _generated.getSellerApi().sellerUpdateOrderItemStatusSellerOrdersItemsItemIdStatusPatch(
            itemId: itemId,
            sellerOrderItemStatusUpdate: gen.SellerOrderItemStatusUpdate((b) => b
              ..fulfillmentStatus = gen.SellerOrderItemStatusUpdateFulfillmentStatusEnum.valueOf(
                status,
              )),
          ),
    );
  }

  Future<List<AdminSellerModel>> adminSellers({String? status}) async {
    final data = await _generatedCall(
      () => _generated.getAdminApi().listSellersAdminSellersGet(status: status),
    );
    return data.items
        .map(
          (s) => AdminSellerModel(
            id: s.id,
            shopName: s.shopName,
            userEmail: s.userEmail,
            status: s.status,
            sellerType: s.sellerType,
          ),
        )
        .toList();
  }

  Future<void> adminApproveSeller(String sellerId) async {
    await _generatedCall(
      () => _generated.getAdminApi().approveSellerEndpointAdminSellersSellerIdApprovePost(
            sellerId: sellerId,
          ),
    );
  }

  Future<List<SellerOrderItemModel>> adminOrders() async {
    final data = await _generatedCall(
      () => _generated.getAdminApi().listAdminOrdersAdminOrdersGet(),
    );
    return data.items.map(adminOrderItemFromGenerated).toList();
  }

  Future<void> adminUpdateOrderStatus(String itemId, String status) async {
    await _generatedCall(
      () => _generated.getAdminApi().adminUpdateOrderItemStatusAdminOrdersItemsItemIdStatusPatch(
            itemId: itemId,
            sellerOrderItemStatusUpdate: gen.SellerOrderItemStatusUpdate((b) => b
              ..fulfillmentStatus = gen.SellerOrderItemStatusUpdateFulfillmentStatusEnum.valueOf(
                status,
              )),
          ),
    );
  }
}

gen.LoginRequestPortalEnum _loginRequestPortal(LoginPortal portal) {
  return switch (portal) {
    LoginPortal.buyer => gen.LoginRequestPortalEnum.buyer,
    LoginPortal.seller => gen.LoginRequestPortalEnum.seller,
    LoginPortal.admin => gen.LoginRequestPortalEnum.admin,
  };
}
