/// 손님 브라우즈 1차 15개. SSOT: docs/guest-l1.md
class GuestL1Category {
  const GuestL1Category({
    required this.name,
    required this.defaultAxis,
    this.imageUrl,
  });

  final String name;
  /// `brand` | `menu`
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
