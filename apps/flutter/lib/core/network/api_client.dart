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
    : _tokenReader = tokenReader ?? TokenStorage().readActiveToken {
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
    _generated = gen.ShoppingMallApi(dio: _dio, interceptors: []);
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
      return ApiException('연결이 끊겼습니다. 서버가 꺼진 것은 아닐 수 있습니다. 요청이 길면 다시 시도하세요.');
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
        loginRequest: gen.LoginRequest(
          (b) => b
            ..email = email
            ..password = password
            ..portal = _loginRequestPortal(portal),
        ),
      ),
    );
    return data.accessToken;
  }

  Future<String> register(
    String email,
    String password, {
    String? displayName,
  }) async {
    final data = await _generatedCall(
      () => _generated.getAuthApi().registerAuthRegisterPost(
        registerRequest: gen.RegisterRequest(
          (b) => b
            ..email = email
            ..password = password
            ..displayName = displayName,
        ),
      ),
    );
    return data.accessToken;
  }

  Future<UserModel> me() async {
    final data = await _generatedCall(
      () => _generated.getAuthApi().meAuthMeGet(),
    );
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

  Future<CatalogProductPageModel> catalogProducts({
    String? q,
    String? category,
    String? categoryMajor,
    String? categoryMid,
    String? l1Tag,
    String? l2Tag,
    String? storage,
    String? brand,
    String? menu,
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
          if (categoryMajor != null && categoryMajor.isNotEmpty)
            'categoryMajor': categoryMajor,
          if (categoryMid != null && categoryMid.isNotEmpty)
            'categoryMid': categoryMid,
          if (l1Tag != null && l1Tag.isNotEmpty) 'l1Tag': l1Tag,
          if (l2Tag != null && l2Tag.isNotEmpty) 'l2Tag': l2Tag,
          if (storage != null && storage.isNotEmpty) 'storage': storage,
          if (brand != null && brand.isNotEmpty) 'brand': brand,
          if (menu != null && menu.isNotEmpty) 'menu': menu,
          if (flavor != null && flavor.isNotEmpty) 'flavor': flavor,
          if (volumeMlMin != null) 'volumeMlMin': volumeMlMin,
          if (volumeMlMax != null) 'volumeMlMax': volumeMlMax,
          'offset': offset,
          'limit': limit,
        },
      );
      final items = response.data?['items'] as List<dynamic>? ?? [];
      final total = response.data?['total'] as int? ?? items.length;
      final flavors = (response.data?['availableFlavors'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
      final hasVolumeMin2000 =
          response.data?['hasVolumeMin2000'] as bool? ?? false;
      return CatalogProductPageModel(
        items: items
            .whereType<Map>()
            .map(
              (e) => CatalogProductModel.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList(),
        total: total,
        availableFlavors: flavors,
        hasVolumeMin2000: hasVolumeMin2000,
      );
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<CatalogOfferBrowsePageModel> catalogOffers({
    String? q,
    String? category,
    String? categoryMajor,
    String? categoryMid,
    String? l1Tag,
    String? l2Tag,
    String? storage,
    String? brand,
    String? menu,
    String? flavor,
    int? volumeMlMin,
    int? volumeMlMax,
    int offset = 0,
    int limit = 50,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'catalog-products/offers',
        queryParameters: {
          if (q != null && q.isNotEmpty) 'q': q,
          if (category != null && category.isNotEmpty) 'category': category,
          if (categoryMajor != null && categoryMajor.isNotEmpty)
            'categoryMajor': categoryMajor,
          if (categoryMid != null && categoryMid.isNotEmpty)
            'categoryMid': categoryMid,
          if (l1Tag != null && l1Tag.isNotEmpty) 'l1Tag': l1Tag,
          if (l2Tag != null && l2Tag.isNotEmpty) 'l2Tag': l2Tag,
          if (storage != null && storage.isNotEmpty) 'storage': storage,
          if (brand != null && brand.isNotEmpty) 'brand': brand,
          if (menu != null && menu.isNotEmpty) 'menu': menu,
          if (flavor != null && flavor.isNotEmpty) 'flavor': flavor,
          if (volumeMlMin != null) 'volumeMlMin': volumeMlMin,
          if (volumeMlMax != null) 'volumeMlMax': volumeMlMax,
          'offset': offset,
          'limit': limit,
        },
      );
      final items = response.data?['items'] as List<dynamic>? ?? [];
      final total = response.data?['total'] as int? ?? items.length;
      return CatalogOfferBrowsePageModel(
        items: items
            .whereType<Map>()
            .map(
              (e) =>
                  CatalogOfferBrowseModel.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList(),
        total: total,
      );
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<GuestL1FacetsModel> guestL1Facets({
    String? l1Tag,
    String? l2Tag,
    String? q,
    String? storage,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'catalog-products/guest-l1/facets',
        queryParameters: {
          if (l1Tag != null && l1Tag.isNotEmpty) 'l1Tag': l1Tag,
          if (l2Tag != null && l2Tag.isNotEmpty) 'l2Tag': l2Tag,
          if (q != null && q.isNotEmpty) 'q': q,
          if (storage != null && storage.isNotEmpty) 'storage': storage,
        },
      );
      final data = response.data;
      if (data == null) throw ApiException('응답 데이터가 없습니다.');
      return GuestL1FacetsModel.fromJson(data);
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
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'catalog-products/$id',
        queryParameters: {
          if (flavor != null) 'flavor': flavor,
          if (volumeMlMin != null) 'volumeMlMin': volumeMlMin,
          if (volumeMlMax != null) 'volumeMlMax': volumeMlMax,
        },
      );
      return CatalogProductDetailModel.fromJson(response.data ?? const {});
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<ProductModel> product(String id) async {
    final data = await _generatedCall(
      () => _generated.getProductsApi().getProductByIdProductsProductIdGet(
        productId: id,
      ),
    );
    return productModelFromGenerated(data);
  }

  Future<CartModel> cart() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('me/cart');
      final data = response.data;
      if (data == null) throw ApiException('응답 데이터가 없습니다.');
      return CartModel.fromJson(data);
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<CartModel> addToCart(String productId, {int qty = 1}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'me/cart',
        data: {'productId': productId, 'qty': qty},
      );
      final data = response.data;
      if (data == null) throw ApiException('응답 데이터가 없습니다.');
      return CartModel.fromJson(data);
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<CartModel> updateCartItem(String productId, int qty) async {
    try {
      final response = await _dio.put<Map<String, dynamic>>(
        'me/cart',
        data: {'productId': productId, 'qty': qty},
      );
      final data = response.data;
      if (data == null) throw ApiException('응답 데이터가 없습니다.');
      return CartModel.fromJson(data);
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<CartModel> removeFromCart(String productId) async {
    try {
      final response = await _dio.delete<Map<String, dynamic>>(
        'me/cart',
        data: {'productId': productId},
      );
      final data = response.data;
      if (data == null) throw ApiException('응답 데이터가 없습니다.');
      return CartModel.fromJson(data);
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<OrderModel> checkout({String? idempotencyKey}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'me/orders',
        options: Options(
          headers: {
            if (idempotencyKey != null && idempotencyKey.isNotEmpty)
              'Idempotency-Key': idempotencyKey,
          },
        ),
      );
      final order = response.data?['order'];
      if (order is! Map) {
        throw ApiException('응답 데이터가 없습니다.');
      }
      return OrderModel.fromJson(Map<String, dynamic>.from(order));
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<List<ShippingAddressModel>> addresses() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('me/addresses');
      final data = response.data;
      if (data == null) throw ApiException('응답 데이터가 없습니다.');
      final items = data['items'] as List<dynamic>? ?? [];
      return items
          .whereType<Map>()
          .map((e) => ShippingAddressModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<ShippingAddressModel> createAddress({
    required String recipientName,
    required String phone,
    required String zonecode,
    required String address,
    required String detailAddress,
    bool isDefault = false,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'me/addresses',
        data: {
          'recipientName': recipientName,
          'phone': phone,
          'zonecode': zonecode,
          'address': address,
          'detailAddress': detailAddress,
          'isDefault': isDefault,
        },
      );
      final data = response.data;
      if (data == null) throw ApiException('응답 데이터가 없습니다.');
      return ShippingAddressModel.fromJson(data);
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<ShippingAddressModel> updateAddress(
    String id, {
    String? recipientName,
    String? phone,
    String? zonecode,
    String? address,
    String? detailAddress,
    bool? isDefault,
  }) async {
    try {
      final body = <String, dynamic>{
        if (recipientName != null) 'recipientName': recipientName,
        if (phone != null) 'phone': phone,
        if (zonecode != null) 'zonecode': zonecode,
        if (address != null) 'address': address,
        if (detailAddress != null) 'detailAddress': detailAddress,
        if (isDefault != null) 'isDefault': isDefault,
      };
      final response = await _dio.patch<Map<String, dynamic>>(
        'me/addresses/$id',
        data: body,
      );
      final data = response.data;
      if (data == null) throw ApiException('응답 데이터가 없습니다.');
      return ShippingAddressModel.fromJson(data);
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<List<ShippingAddressModel>> deleteAddress(String id) async {
    try {
      final response = await _dio.delete<Map<String, dynamic>>('me/addresses/$id');
      final data = response.data;
      if (data == null) throw ApiException('응답 데이터가 없습니다.');
      final items = data['items'] as List<dynamic>? ?? [];
      return items
          .whereType<Map>()
          .map((e) => ShippingAddressModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<TossPrepareModel> prepareTossPayment({
    required String idempotencyKey,
    required String addressId,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'payments/toss/prepare',
        data: {'addressId': addressId},
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      final data = response.data;
      if (data == null) throw ApiException('응답 데이터가 없습니다.');
      return TossPrepareModel(
        orderId: data['orderId'] as String,
        amount: (data['amount'] as num).toInt(),
        orderName: data['orderName'] as String,
        clientKey: data['clientKey'] as String,
        customerKey: data['customerKey'] as String,
      );
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<OrderModel> confirmTossPayment({
    required String paymentKey,
    required String orderId,
    required int amount,
  }) async {
    final data = await _generatedCall(
      () =>
          _generated.getPaymentsApi().confirmTossPaymentPaymentsTossConfirmPost(
            tossConfirmRequest: gen.TossConfirmRequest(
              (builder) => builder
                ..paymentKey = paymentKey
                ..orderId = orderId
                ..amount = amount,
            ),
          ),
    );
    return orderModelFromGenerated(data.order);
  }

  Future<TossPaymentStatusModel> tossPaymentStatus(String orderId) async {
    final data = await _generatedCall(
      () => _generated.getPaymentsApi().readTossPaymentPaymentsTossOrderIdGet(
        orderId: orderId,
      ),
    );
    final status =
        gen.serializers.serialize(
              data.status,
              specifiedType: const FullType(
                gen.TossPaymentStatusResponseStatusEnum,
              ),
            )
            as String;
    return TossPaymentStatusModel(
      orderId: data.orderId,
      status: status,
      localOrderId: data.localOrderId,
      failureMessage: data.failureMessage,
    );
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
      () =>
          _generated.getMembershipApi().getMembershipPlansMembershipPlansGet(),
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
      () => _generated
          .getMembershipApi()
          .subscribeMembershipMeMembershipSubscribePost(
            subscribeRequest: gen.SubscribeRequest(
              (b) => b..planSlug = planSlug,
            ),
          ),
    );
    return SubscriptionModel(
      id: data.id,
      planSlug: data.planSlug,
      planName: data.planName,
      status:
          gen.serializers.serialize(
                data.status,
                specifiedType: const FullType(
                  gen.SubscriptionResponseStatusEnum,
                ),
              )
              as String,
      currentPeriodEnd: data.currentPeriodEnd,
    );
  }

  Future<Map<String, dynamic>> adminStats() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('admin/stats');
      return response.data ?? {};
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<Map<String, dynamic>> sellerStats() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('seller/stats');
      return response.data ?? {};
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<Map<String, dynamic>> adminUsers({String? q}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'admin/users',
        queryParameters: {
          if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        },
      );
      return response.data ?? {};
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<Map<String, dynamic>> adminUpdateUser(
    String userId, {
    required bool isAdmin,
    bool? isBuyer,
    bool? isSeller,
    String? displayName,
    String? sellerName,
  }) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        'admin/users/$userId',
        data: {
          'isAdmin': isAdmin,
          if (isBuyer != null) 'isBuyer': isBuyer,
          if (isSeller != null) 'isSeller': isSeller,
          if (displayName != null) 'displayName': displayName,
          if (sellerName != null) 'sellerName': sellerName,
        },
      );
      final data = response.data;
      if (data == null) throw ApiException('응답 데이터가 없습니다.');
      return data;
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<void> adminDeleteUser(String userId) async {
    try {
      await _dio.delete<void>('admin/users/$userId');
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<void> adminGrantCredits(String userId, int amount) async {
    try {
      await _generated
          .getAdminApi()
          .grantUserCreditsAdminUsersUserIdCreditsPost(
            userId: userId,
            adminCreditGrantRequest: gen.AdminCreditGrantRequest(
              (b) => b..amount = amount,
            ),
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
        options: Options(receiveTimeout: const Duration(minutes: 15)),
      );
      return response.data ?? {};
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<SellerModel?> sellerMe() async {
    try {
      final response = await _dio.get<dynamic>('seller/me');
      final data = response.data;
      if (data is! Map) return null;
      final json = Map<String, dynamic>.from(data);
      if (json['id'] == null) return null;
      return SellerModel.fromJson(json);
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<SellerModel> sellerApply(String shopName) async {
    final data = await _generatedCall(
      () => _generated.getSellerApi().sellerApplySellerApplyPost(
        sellerApplyRequest: gen.SellerApplyRequest(
          (b) => b..shopName = shopName,
        ),
      ),
    );
    return sellerModelFromGenerated(data)!;
  }

  Future<CatalogProductSearchPage> sellerSearchCatalog({
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
      return CatalogProductSearchPage(
        items: items
            .whereType<Map>()
            .map(
              (e) => CatalogProductModel.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList(),
        total: response.data?['total'] as int? ?? items.length,
      );
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  static const _importMaxBytes = 4 * 1024 * 1024;
  static const _importMaxRows = 20000;

  Future<List<int>> adminDownloadCatalogCsv({required bool template}) async {
    try {
      final response = await _dio.get<List<int>>(
        template ? 'admin/catalog/export/template' : 'admin/catalog/export',
        options: Options(responseType: ResponseType.bytes),
      );
      return response.data ?? const [];
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<({int sourceRows, int upserted})> adminImportCatalog(
    List<int> bytes,
    String filename, {
    void Function(double fraction)? onSendProgress,
    void Function()? onProcessing,
  }) async {
    if (bytes.length > _importMaxBytes) {
      throw ApiException('파일이 너무 큽니다. 카탈로그 템플릿 형식으로 4MB 이하 파일을 올리세요.');
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
      throw ApiException('행이 너무 많습니다. 카탈로그 템플릿 형식으로 2만 줄 이하 파일을 올리세요.');
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
          throw ApiException(data['error'] as String? ?? '카탈로그 반영에 실패했습니다.');
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
          '업로드 연결이 끊겼습니다. 잠시 뒤 카탈로그 CSV를 다시 올리세요.',
        );
      }
      throw mapped;
    }
  }

  Future<SellerProductListPage> sellerProducts({
    String? q,
    String? filter,
    String? sort,
    int offset = 0,
    int limit = 20,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'seller/products',
        queryParameters: {
          if (q != null && q.isNotEmpty) 'q': q,
          if (filter != null && filter.isNotEmpty) 'filter': filter,
          if (sort != null && sort.isNotEmpty) 'sort': sort,
          'offset': offset,
          'limit': limit,
        },
      );
      return SellerProductListPage.fromJson(response.data ?? const {});
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<ProductModel> sellerProduct(String productId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'seller/products/$productId',
      );
      final data = response.data;
      if (data == null) throw ApiException('응답 데이터가 없습니다.');
      return ProductModel.fromJson(data);
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<ProductModel> sellerCreateProduct({
    required String title,
    required String category,
    int? priceCredits,
    int? stock,
    String? description,
    String status = 'draft',
    String? catalogProductId,
    String? variantId,
    String? optionLabel,
    int? volumeMl,
    double? unitAmount,
    String? unit,
    int? packCount,
    String? flavor,
    String? imageUrl,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'seller/products',
        data: {
          'title': title,
          'category': category,
          'status': status,
          if (priceCredits != null) 'priceCredits': priceCredits,
          if (stock != null) 'stock': stock,
          if (description != null && description.isNotEmpty) 'description': description,
          if (catalogProductId != null) 'catalogProductId': catalogProductId,
          if (variantId != null) 'variantId': variantId,
          if (optionLabel != null && optionLabel.isNotEmpty) 'optionLabel': optionLabel,
          if (volumeMl != null) 'volumeMl': volumeMl,
          if (unitAmount != null) 'unitAmount': unitAmount,
          if (unit != null && unit.isNotEmpty) 'unit': unit,
          if (packCount != null) 'packCount': packCount,
          if (flavor != null && flavor.isNotEmpty) 'flavor': flavor,
          if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
        },
      );
      final data = response.data;
      if (data == null) throw ApiException('응답 데이터가 없습니다.');
      return ProductModel.fromJson(data);
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<ProductModel> sellerUpdateProduct(
    String productId, {
    int? priceCredits,
    int? stock,
    String? imageUrl,
    String? status,
    String? optionLabel,
    double? unitAmount,
    String? unit,
    int? packCount,
    String? flavor,
  }) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        'seller/products/$productId',
        data: {
          if (priceCredits != null) 'priceCredits': priceCredits,
          if (stock != null) 'stock': stock,
          if (imageUrl != null) 'imageUrl': imageUrl,
          if (status != null) 'status': status,
          if (optionLabel != null) 'optionLabel': optionLabel,
          if (unitAmount != null) 'unitAmount': unitAmount,
          if (unit != null) 'unit': unit,
          if (packCount != null) 'packCount': packCount,
          if (flavor != null) 'flavor': flavor,
        },
      );
      final data = response.data;
      if (data == null) throw ApiException('응답 데이터가 없습니다.');
      return ProductModel.fromJson(data);
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<SellerProductBulkResult> sellerBulkUpdateProducts({
    required List<String> ids,
    int? priceCredits,
    int? stock,
    String? status,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'seller/products/bulk',
        data: {
          'ids': ids,
          if (priceCredits != null) 'priceCredits': priceCredits,
          if (stock != null) 'stock': stock,
          if (status != null) 'status': status,
        },
      );
      return SellerProductBulkResult.fromJson(response.data ?? const {});
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<void> sellerDeleteProduct(String productId) async {
    try {
      await _dio.delete<void>('seller/products/$productId');
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<List<IntakeDraftModel>> sellerCardDrafts() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'seller/card-drafts',
      );
      final items = response.data?['items'] as List<dynamic>? ?? [];
      return items
          .whereType<Map>()
          .map((e) => IntakeDraftModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<IntakeDraftModel> sellerCreateCardDraft({
    required String manufacturer,
    required String title,
    required String category,
    String? catalogProductId,
    String? variantName,
    List<Map<String, dynamic>> variants = const [],
    String? optionLabel,
    int? priceCredits,
    int? stock,
    String? imageUrl,
    String? flavor,
    int? volumeMl,
    double? unitAmount,
    String? unit,
    int? packCount,
    String? description,
    String? visibility,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'seller/card-drafts',
        data: {
          'manufacturer': manufacturer,
          'title': title,
          'category': category,
          if (catalogProductId != null) 'catalogProductId': catalogProductId,
          if (variantName != null) 'variantName': variantName,
          if (variants.isNotEmpty) 'variants': variants,
          if (optionLabel != null && optionLabel.isNotEmpty) 'optionLabel': optionLabel,
          if (priceCredits != null) 'priceCredits': priceCredits,
          if (stock != null) 'stock': stock,
          if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
          if (flavor != null && flavor.isNotEmpty) 'flavor': flavor,
          if (volumeMl != null) 'volumeMl': volumeMl,
          if (unitAmount != null) 'unitAmount': unitAmount,
          if (unit != null && unit.isNotEmpty) 'unit': unit,
          if (packCount != null) 'packCount': packCount,
          if (description != null && description.isNotEmpty)
            'description': description,
          if (visibility != null) 'visibility': visibility,
        },
      );
      final data = response.data;
      if (data == null) throw ApiException('응답 데이터가 없습니다.');
      return IntakeDraftModel.fromJson(data);
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<IntakeDraftModel> sellerUpdateCardDraft(
    String draftId, {
    int? priceCredits,
    int? stock,
    String? imageUrl,
    String? flavor,
    String? optionLabel,
    double? unitAmount,
    String? unit,
    int? packCount,
    String? visibility,
  }) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        'seller/card-drafts/$draftId',
        data: {
          if (priceCredits != null) 'priceCredits': priceCredits,
          if (stock != null) 'stock': stock,
          if (imageUrl != null) 'imageUrl': imageUrl,
          if (flavor != null) 'flavor': flavor,
          if (optionLabel != null) 'optionLabel': optionLabel,
          if (unitAmount != null) 'unitAmount': unitAmount,
          if (unit != null) 'unit': unit,
          if (packCount != null) 'packCount': packCount,
          if (visibility != null) 'visibility': visibility,
        },
      );
      final data = response.data;
      if (data == null) throw ApiException('응답 데이터가 없습니다.');
      return IntakeDraftModel.fromJson(data);
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<String> sellerUploadImage(List<int> bytes, String filename) async {
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      });
      final response = await _dio.post<Map<String, dynamic>>(
        'seller/uploads/image',
        data: form,
      );
      final url = response.data?['imageUrl'] as String?;
      if (url == null || url.isEmpty) {
        throw ApiException('사진 주소를 받지 못했습니다.');
      }
      return url;
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<List<IntakeDraftModel>> adminCatalogDrafts() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'admin/catalog/drafts',
      );
      final items = response.data?['items'] as List<dynamic>? ?? [];
      return items
          .whereType<Map>()
          .map((e) => IntakeDraftModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<IntakeDraftModel> adminAttachCatalogDraft({
    required String draftId,
    required String kind,
    String? catalogProductId,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'admin/catalog/drafts/$draftId/attach',
        data: {
          'kind': kind,
          if (catalogProductId != null && catalogProductId.isNotEmpty)
            'catalogProductId': catalogProductId,
        },
      );
      final data = response.data;
      if (data == null) throw ApiException('응답 데이터가 없습니다.');
      return IntakeDraftModel.fromJson(data);
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<IntakeDraftModel> adminPromoteCatalogDraft({
    required String draftId,
    required String category,
    String? manufacturer,
    String? title,
    List<String>? l1Tags,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'admin/catalog/drafts/$draftId/promote',
        data: {
          'category': category,
          if (manufacturer != null && manufacturer.isNotEmpty)
            'manufacturer': manufacturer,
          if (title != null && title.isNotEmpty) 'title': title,
          if (l1Tags != null) 'l1Tags': l1Tags,
        },
      );
      final data = response.data;
      if (data == null) throw ApiException('응답 데이터가 없습니다.');
      return IntakeDraftModel.fromJson(data);
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<List<SellerOrderItemModel>> sellerOrders() async {
    final data = await _generatedCall(
      () => _generated.getSellerApi().sellerListOrdersSellerOrdersGet(),
    );
    return data.items.map(sellerOrderItemFromGenerated).toList();
  }

  Future<void> sellerUpdateOrderStatus(String itemId, String status) async {
    await _generatedCall(
      () => _generated
          .getSellerApi()
          .sellerUpdateOrderItemStatusSellerOrdersItemsItemIdStatusPatch(
            itemId: itemId,
            sellerOrderItemStatusUpdate: gen.SellerOrderItemStatusUpdate(
              (b) => b
                ..fulfillmentStatus =
                    gen.SellerOrderItemStatusUpdateFulfillmentStatusEnum.valueOf(
                      status,
                    ),
            ),
          ),
    );
  }

  Future<List<AdminSellerModel>> adminSellers({String? status}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'admin/sellers',
        queryParameters: {
          if (status != null && status.isNotEmpty) 'status': status,
        },
      );
      final items = response.data?['items'] as List<dynamic>? ?? [];
      return items
          .whereType<Map>()
          .map((e) => AdminSellerModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<AdminSellerModel> _adminSellerAction(
    String path, {
    String? reason,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        path,
        data: {if (reason != null) 'reason': reason},
      );
      final data = response.data;
      if (data == null) throw ApiException('응답 데이터가 없습니다.');
      return AdminSellerModel.fromJson(data);
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<AdminSellerModel> adminApproveSeller(String sellerId) {
    return _adminSellerAction('admin/sellers/$sellerId/approve');
  }

  Future<AdminSellerModel> adminWarnSeller(String sellerId, String reason) {
    return _adminSellerAction('admin/sellers/$sellerId/warn', reason: reason);
  }

  Future<AdminSellerModel> adminSuspendSeller(String sellerId, String reason) {
    return _adminSellerAction('admin/sellers/$sellerId/suspend', reason: reason);
  }

  Future<AdminSellerModel> adminUnsuspendSeller(String sellerId, String reason) {
    return _adminSellerAction(
      'admin/sellers/$sellerId/unsuspend',
      reason: reason,
    );
  }

  Future<AdminSellerModel> adminRemoveSeller(String sellerId, String reason) {
    return _adminSellerAction('admin/sellers/$sellerId/remove', reason: reason);
  }

  Future<List<SellerModerationEventModel>> adminSellerModeration(
    String sellerId,
  ) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'admin/sellers/$sellerId/moderation',
      );
      final items = response.data?['items'] as List<dynamic>? ?? [];
      return items
          .whereType<Map>()
          .map(
            (e) => SellerModerationEventModel.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList();
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<List<SellerModerationEventModel>> sellerModerationEvents() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'seller/moderation-events',
      );
      final items = response.data?['items'] as List<dynamic>? ?? [];
      return items
          .whereType<Map>()
          .map(
            (e) => SellerModerationEventModel.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList();
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<AdminCatalogProductPageModel> adminCatalogProducts({
    String? q,
    bool includeRetired = false,
    String? l1Tag,
    int offset = 0,
    int limit = 24,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'admin/catalog/products',
        queryParameters: {
          if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
          if (includeRetired) 'includeRetired': true,
          if (l1Tag != null && l1Tag.trim().isNotEmpty) 'l1Tag': l1Tag.trim(),
          'offset': offset,
          'limit': limit,
        },
      );
      final data = response.data ?? const <String, dynamic>{};
      return AdminCatalogProductPageModel.fromJson(data);
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<AdminCatalogProductModel> adminCreateCatalogProduct({
    required String manufacturer,
    required String title,
    required String category,
    String? description,
    String? imageUrl,
    List<String> volumeOptions = const [],
    List<Map<String, dynamic>> variants = const [],
    String priceUnit = 'credits',
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'admin/catalog/products',
        data: {
          'manufacturer': manufacturer,
          'title': title,
          'category': category,
          if (description != null && description.isNotEmpty)
            'description': description,
          if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
          'volumeOptions': volumeOptions,
          'variants': variants,
          'priceUnit': priceUnit,
        },
      );
      final data = response.data;
      if (data == null) throw ApiException('응답 데이터가 없습니다.');
      return AdminCatalogProductModel.fromJson(data);
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<List<CatalogVariantModel>> adminAddCatalogVariants(
    String catalogId,
    List<Map<String, dynamic>> variants,
  ) async {
    try {
      final response = await _dio.post<List<dynamic>>(
        'admin/catalog/products/$catalogId/variants/batch',
        data: {'variants': variants},
      );
      return (response.data ?? const [])
          .whereType<Map>()
          .map((row) => CatalogVariantModel.fromJson(Map<String, dynamic>.from(row)))
          .toList();
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<AdminCatalogProductModel> adminDeleteCatalogProduct(String id) async {
    try {
      final response = await _dio.delete<Map<String, dynamic>>(
        'admin/catalog/products/$id',
      );
      final data = response.data;
      if (data == null) throw ApiException('응답 데이터가 없습니다.');
      return AdminCatalogProductModel.fromJson(data);
    } on DioException catch (e) {
      throw _apiExceptionFromDio(e);
    }
  }

  Future<List<SellerOrderItemModel>> adminOrders() async {
    final data = await _generatedCall(
      () => _generated.getAdminApi().listAdminOrdersAdminOrdersGet(),
    );
    return data.items.map(adminOrderItemFromGenerated).toList();
  }

  Future<void> adminUpdateOrderStatus(String itemId, String status) async {
    await _generatedCall(
      () => _generated
          .getAdminApi()
          .adminUpdateOrderItemStatusAdminOrdersItemsItemIdStatusPatch(
            itemId: itemId,
            sellerOrderItemStatusUpdate: gen.SellerOrderItemStatusUpdate(
              (b) => b
                ..fulfillmentStatus =
                    gen.SellerOrderItemStatusUpdateFulfillmentStatusEnum.valueOf(
                      status,
                    ),
            ),
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
