class DaumPostcodeResult {
  const DaumPostcodeResult({required this.zonecode, required this.address});

  final String zonecode;
  final String address;
}

bool get daumPostcodeSupported => false;

Future<DaumPostcodeResult?> requestDaumPostcode() async => null;
