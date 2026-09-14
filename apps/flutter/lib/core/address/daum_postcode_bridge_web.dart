import 'dart:js_interop';
import 'dart:js_interop_unsafe';

class DaumPostcodeResult {
  const DaumPostcodeResult({required this.zonecode, required this.address});

  final String zonecode;
  final String address;
}

@JS('requestDaumPostcode')
external JSPromise<JSAny?> _requestDaumPostcode();

bool get daumPostcodeSupported => true;

Future<DaumPostcodeResult?> requestDaumPostcode() async {
  if (!globalContext.has('requestDaumPostcode')) {
    throw StateError('주소 검색을 불러오지 못했습니다. 페이지를 새로고침해 주세요.');
  }
  try {
    final raw = await _requestDaumPostcode().toDart;
    if (raw == null) return null;
    final map = (raw.dartify() as Map?)?.cast<String, dynamic>();
    if (map == null) return null;
    final zonecode = map['zonecode']?.toString().trim() ?? '';
    final address = map['address']?.toString().trim() ?? '';
    if (zonecode.isEmpty || address.isEmpty) return null;
    return DaumPostcodeResult(zonecode: zonecode, address: address);
  } catch (error) {
    final text = error.toString().trim();
    if (text.contains('취소')) return null;
    throw StateError(
      text.replaceFirst(RegExp(r'^Error:\s*'), '').isEmpty
          ? '주소 검색을 열지 못했습니다.'
          : text.replaceFirst(RegExp(r'^Error:\s*'), ''),
    );
  }
}
