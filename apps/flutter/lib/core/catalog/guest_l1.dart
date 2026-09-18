/// 손님 브라우즈 1차 15개. SSOT: docs/guest-l1.md
class GuestL1Category {
  const GuestL1Category({
    required this.name,
    required this.defaultAxis,
    this.imageUrl,
  });

  final String name;
  /// 1차 기본 축. `brand` | `menu` (판매자 오퍼는 기본값이 아님)
  final String defaultAxis;
  final String? imageUrl;
}

const List<GuestL1Category> kGuestL1Categories = [
  GuestL1Category(
    name: '생수/음료',
    defaultAxis: 'brand',
    imageUrl:
        'https://images.unsplash.com/photo-1548839140-29a749e1cf4d?auto=format&fit=crop&w=400&q=80',
  ),
  GuestL1Category(
    name: '커피/원두/차',
    defaultAxis: 'brand',
    imageUrl:
        'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?auto=format&fit=crop&w=400&q=80',
  ),
  GuestL1Category(
    name: '과자/초콜릿/시리얼',
    defaultAxis: 'brand',
    imageUrl:
        'https://images.unsplash.com/photo-1599490659213-e2b9527bd087?auto=format&fit=crop&w=400&q=80',
  ),
  GuestL1Category(
    name: '라면/면류',
    defaultAxis: 'brand',
    imageUrl:
        'https://images.unsplash.com/photo-1612929633738-8fe44f7ec841?auto=format&fit=crop&w=400&q=80',
  ),
  GuestL1Category(
    name: '통조림/캔',
    defaultAxis: 'brand',
    imageUrl:
        'https://images.unsplash.com/photo-1588166524941-3bf61a9c41db?auto=format&fit=crop&w=400&q=80',
  ),
  GuestL1Category(
    name: '반찬/간편식/대용식',
    defaultAxis: 'menu',
    imageUrl:
        'https://images.unsplash.com/photo-1516684669134-de6f7c473a2a?auto=format&fit=crop&w=400&q=80',
  ),
  GuestL1Category(
    name: '국/탕/찌개',
    defaultAxis: 'menu',
    imageUrl:
        'https://images.unsplash.com/photo-1547592166-23ac45744acd?auto=format&fit=crop&w=400&q=80',
  ),
  GuestL1Category(
    name: '즉석밥/볶음밥',
    defaultAxis: 'menu',
    imageUrl:
        'https://images.unsplash.com/photo-1516684669134-de6f7c473a2a?auto=format&fit=crop&w=400&q=80',
  ),
  GuestL1Category(
    name: '죽/스프',
    defaultAxis: 'menu',
    imageUrl:
        'https://images.unsplash.com/photo-1547592166-23ac45744acd?auto=format&fit=crop&w=400&q=80',
  ),
  GuestL1Category(
    name: '분식/만두/피자',
    defaultAxis: 'menu',
    imageUrl:
        'https://images.unsplash.com/photo-1496116218417-1a781b1c416c?auto=format&fit=crop&w=400&q=80',
  ),
  GuestL1Category(
    name: '짜장/카레/돈까스',
    defaultAxis: 'menu',
    imageUrl:
        'https://images.unsplash.com/photo-1635321593217-440d141e9987?auto=format&fit=crop&w=400&q=80',
  ),
  GuestL1Category(
    name: '냉장/냉동/간편요리',
    defaultAxis: 'menu',
    imageUrl:
        'https://images.unsplash.com/photo-1496116218417-1a781b1c416c?auto=format&fit=crop&w=400&q=80',
  ),
  GuestL1Category(
    name: '가루/조미료/오일',
    defaultAxis: 'brand',
    imageUrl:
        'https://images.unsplash.com/photo-1472476443507-6e15bbba9d8d?auto=format&fit=crop&w=400&q=80',
  ),
  GuestL1Category(
    name: '장류/소스',
    defaultAxis: 'brand',
    imageUrl:
        'https://images.unsplash.com/photo-1472476443507-6e15bbba9d8d?auto=format&fit=crop&w=400&q=80',
  ),
  GuestL1Category(
    name: '유제품/아이스크림',
    defaultAxis: 'brand',
    imageUrl:
        'https://images.unsplash.com/photo-1563636619-e9143da7973b?auto=format&fit=crop&w=400&q=80',
  ),
];

const List<String> kTodayL1Names = [
  '라면/면류',
  '생수/음료',
  '국/탕/찌개',
  '분식/만두/피자',
  '과자/초콜릿/시리얼',
  '장류/소스',
];

const List<String> kGuestL1StorageFilters = ['상온', '냉장', '냉동'];

GuestL1Category? guestL1ByName(String name) {
  for (final item in kGuestL1Categories) {
    if (item.name == name) return item;
  }
  return null;
}

String guestL1DefaultAxis(String name) =>
    guestL1ByName(name)?.defaultAxis ?? 'brand';

/// 손님 L2. SSOT: docs/guest-l1.md — 등록 대·중·소가 아님. 겹침 허용.
const Map<String, List<String>> kGuestL2ByL1 = {
  '생수/음료': [
    '생수',
    '탄산·이온·스포츠',
    '주스·과채',
    '전통음료',
    '병·캔 커피·차',
    '기타음료',
  ],
  '커피/원두/차': ['원두·캡슐', '커피믹스', '티백·잎차', 'RTD 커피·차', '코코아·기타'],
  '과자/초콜릿/시리얼': ['스낵·과자', '초콜릿·캔디', '시리얼·바', '안주·육포'],
  '라면/면류': ['봉지라면', '컵·용기면', '국수·당면·파스타', '냉면·기타면'],
  '통조림/캔': ['참치·수산캔', '햄·고기캔', '농산·과일캔', '기타캔'],
  '반찬/간편식/대용식': ['즉석반찬', '간편식·도시락', '대용식·선식', '기타'],
  '국/탕/찌개': ['국', '탕', '찌개', '분말·즉석국'],
  '즉석밥/볶음밥': ['흰밥·잡곡밥', '볶음밥·컵밥', '주먹밥·기타'],
  '죽/스프': ['죽', '스프', '미음·기타'],
  '분식/만두/피자': ['만두·교자', '떡볶이·어묵', '피자·핫도그', '기타분식'],
  '짜장/카레/돈까스': ['짜장', '카레', '돈까스·커틀릿', '너겟·강정'],
  '냉장/냉동/간편요리': ['냉장HMR', '냉동HMR', '냉동만두·분식', '기타냉동'],
  '가루/조미료/오일': ['가루·분말', '조미료', '식용유·참기름', '기타'],
  '장류/소스': ['고추장·된장·쌈장', '간장', '소스·드레싱', '식초·맛술'],
  '유제품/아이스크림': ['우유', '요거트·치즈·버터', '아이스크림·빙과'],
};

List<String> guestL2For(String l1) =>
    List<String>.unmodifiable(kGuestL2ByL1[l1] ?? const <String>[]);

bool isGuestL2(String l1, String l2) => guestL2For(l1).contains(l2);

String? normalizeGuestL2(String? l1, String? raw) {
  final name = raw?.trim() ?? '';
  if (l1 == null || l1.isEmpty || name.isEmpty) return null;
  return isGuestL2(l1, name) ? name : null;
}

const kBrowseAxisBrand = 'brand';
const kBrowseAxisMenu = 'menu';
const kBrowseAxisSeller = 'seller';

String normalizeBrowseAxis(String? raw, {String fallback = kBrowseAxisBrand}) {
  if (raw == kBrowseAxisMenu ||
      raw == kBrowseAxisSeller ||
      raw == kBrowseAxisBrand) {
    return raw!;
  }
  return fallback;
}

bool isSellerBrowseAxis(String? axis) => axis == kBrowseAxisSeller;
