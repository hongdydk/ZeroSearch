/// AI-Hub Validation 메타 기반 식탁 분류. 밥상 허용 중분류만.
class TableMajor {
  const TableMajor({required this.name, required this.mids});
  final String name;
  final List<TableMid> mids;
}

class TableMid {
  const TableMid({required this.name, required this.minors});
  final String name;
  final List<String> minors;
}

const List<TableMajor> kTableTaxonomy = [
  TableMajor(name: '면류', mids: [
    TableMid(name: '봉지면', minors: ['국물봉지라면', '비빔봉지라면']),
    TableMid(name: '용기면', minors: ['국물용기라면', '비빔용기라면']),
  ]),
  TableMajor(name: '상온HMR', mids: [
    TableMid(name: '절임/잼', minors: ['과일잼', '스프레드']),
    TableMid(name: '잡곡', minors: ['귀리', '기타잡곡류', '보리', '조/수수', '찹쌀', '콩', '현미', '혼합잡곡', '흑미']),
    TableMid(name: '레토르트', minors: ['기타레토르트', '즉석국/찌개', '즉석국밥', '즉석면류', '즉석밥', '즉석스프', '즉석죽', '즉석카레짜장']),
    TableMid(name: '분말조리식', minors: ['기타분말조리식', '분말국/찌개', '분말누룽지', '분말스프', '분말죽', '분말카레짜장']),
  ]),
  TableMajor(name: '음료', mids: [
    TableMid(name: '탄산수', minors: ['Flavor탄산수', '플레인탄산수', '플렝니탄산수']),
    TableMid(name: '과채음료', minors: ['과일음료', '과채혼합음료', '어린이음료', '원액', '채소음료']),
    TableMid(name: '두유', minors: ['기능성두유', '일반두유']),
    TableMid(name: '기능성음료', minors: ['기타', '기타기능성음료', '비타민/에너지음료', '숙취해소음료', '스포츠음료', '식이섬유음료', '한방음료']),
    TableMid(name: '차음료', minors: ['기타차음료', '일반', '일반차음료', '전통차음료']),
    TableMid(name: '냉장음료', minors: ['냉장곡물견과음료', '코코넛워터']),
    TableMid(name: '탄산음료', minors: ['무알콜맥주', '사이다', '콜라', '혼합탄산', '홉합탄산']),
    TableMid(name: '과일음료', minors: ['어린이음료']),
    TableMid(name: '생수', minors: ['일반생수']),
    TableMid(name: '커피음료', minors: ['커피음료']),
  ]),
  TableMajor(name: '유제품', mids: [
    TableMid(name: '우유', minors: ['가공우유', '일반우유']),
    TableMid(name: '버터', minors: ['가염버터', '마가린', '무염버터']),
    TableMid(name: '치즈', minors: ['까망베르치즈', '리코타치즈', '모짜렐라치즈', '생치즈', '체다치즈', '크림치즈']),
    TableMid(name: '요구르트', minors: ['떠먹는 요구르트', '마시는 요구르트']),
  ]),
  TableMajor(name: '커피차', mids: [
    TableMid(name: '액상차', minors: ['과실절임차', '기타', '생강차', '아이스티', '전통차', '커피']),
    TableMid(name: '분말차', minors: ['과실절임차', '기타', '꿀차', '녹차', '녹차/현미녹차', '둥굴레차', '마테차', '메밀차', '밀크티', '보리차', '뿌리차', '생강차', '아이스티', '옥수수차', '우엉차', '잎차', '전통차', '커피', '코코아/핫초코', '허브차', '홍차']),
  ]),
  TableMajor(name: '과자', mids: [
    TableMid(name: '스낵', minors: ['감자스낵', '고구마스낵', '과일스낙', '과일스낵', '밀가루스낵', '비스킷/스틱과자', '샌드', '스틱과자', '쌀과자', '쌀스낵', '야채스낵', '옥수수스낵', '일반스낵', '쿠키', '팝콘']),
    TableMid(name: '파이류', minors: ['과자세트', '과제세트', '케이크', '쿠키', '파이']),
    TableMid(name: '아이스크림', minors: ['구슬아이스크림']),
    TableMid(name: '껌류', minors: ['기능성껌', '일반꺼', '일반껌', '토이껌류', '풍선껌']),
    TableMid(name: '씨리얼', minors: ['기능성시리얼', '씨리얼바', '일반시리얼', '일반씨리얼', '일빈시리얼']),
    TableMid(name: '캔디', minors: ['기능성캔디', '사탕/캔디세트', '소프르캔디', '소프트캔디', '양갱', '젤리', '캐러멜', '케러멜', '토이캔디', '하드캔디', '하드켄디']),
    TableMid(name: '유아식품', minors: ['기타간식/안주형과자']),
    TableMid(name: '견과류', minors: ['기타견과류', '땅콩', '밤', '브라질넛', '아몬드', '피스타치오', '호두', '혼합견과']),
    TableMid(name: '전통과자', minors: ['기타전통과자']),
    TableMid(name: '과자', minors: ['밀가루스낵', '비스킷', '쌀과자']),
    TableMid(name: '비스킷', minors: ['밀가루스낵', '샌드', '스탁과자', '스틱과자', '쌀과자', '쌀스낵', '옥수수스낵', '쿠키', '크래커', '크레커']),
    TableMid(name: '초콜렛', minors: ['바초콜릿', '쉘초콜렛', '쉘초콜릿', '초콜릿세트', '초콜릿칩', '판초콜릿']),
    TableMid(name: '빵', minors: ['식빵', '일반빵', '호빵']),
    TableMid(name: '마른안주', minors: ['어포류']),
    TableMid(name: '사탕', minors: ['하드캔디']),
  ]),
  TableMajor(name: '디저트', mids: [
    TableMid(name: '건과일', minors: ['건포도', '대추']),
    TableMid(name: '퓨레', minors: ['과일퓨레']),
    TableMid(name: '베이커리', minors: ['과자빵']),
    TableMid(name: '디저트/베이커리', minors: ['냉동디저트', '냉장디저트']),
    TableMid(name: '푸딩/젤리', minors: ['냉장젤리류', '냉장푸딩류']),
    TableMid(name: '파이류', minors: ['케이크']),
  ]),
  TableMajor(name: '통조림/안주', mids: [
    TableMid(name: '통조림', minors: ['가미통조림', '과일통조림', '보일드통조림', '애견식품']),
    TableMid(name: '안주', minors: ['견과류', '냉장/냉동식품', '수산물/건해산']),
  ]),
  TableMajor(name: '소스', mids: [
    TableMid(name: '분말조미료', minors: ['가공조미료', '기타향신료', '깨', '자연조미료', '후추']),
    TableMid(name: '장류', minors: ['간장', '겨자/고추냉이', '고추장', '기타장류', '된장', '쌈장']),
    TableMid(name: '설탕류', minors: ['갈색설탕', '물엿/시럽', '하얀설탕']),
    TableMid(name: '소스류', minors: ['고기양념장', '국물용소스', '마요네즈', '물엿/시럽', '상온드레싱', '앙념소스', '양념소스', '케첩', '파스타소스']),
    TableMid(name: '가공분말류', minors: ['곡물가루', '기타제빵재료', '도넛가루/핫케이크가루', '부침가루', '빵가루', '빵믹스', '튀김가루']),
    TableMid(name: '절임/잼', minors: ['과일잼', '스프레드']),
    TableMid(name: '액상조미료', minors: ['맛술', '식초', '액상조미료', '액젓', '음용식초']),
    TableMid(name: '소금류', minors: ['암염', '정제염', '제재염', '천일염', '호수염']),
    TableMid(name: '식용유', minors: ['옥수수기름', '참기름/들기름', '콩기름', '향미유']),
  ]),
  TableMajor(name: '주류', mids: [
    TableMid(name: '전통주', minors: ['고량주', '과실주', '막걸리', '사케', '청주']),
    TableMid(name: '맥주', minors: ['국내맥주', '무알콜맥주', '수입맥주']),
    TableMid(name: '기타주류', minors: ['럼', '보드카', '샴페인', '요리주', '위스키', '진', '칵테일']),
    TableMid(name: '와인', minors: ['레드와인', '로제와인', '스파클링와인', '화이트와인']),
    TableMid(name: '소주', minors: ['증류식소주']),
  ]),
];

const List<String> kTableMajorOrder = [
  '면류',
  '상온HMR',
  '음료',
  '유제품',
  '커피차',
  '과자',
  '디저트',
  '통조림/안주',
  '소스',
  '주류',
];

const List<String> kTodayMajorNames = [
  '면류',
  '상온HMR',
  '음료',
  '유제품',
  '과자',
  '디저트',
];

const Map<String, String> kTableMajorLabels = {
  '상온HMR': '간편식',
  '통조림/안주': '통조림·안주',
  '커피차': '커피·차',
};

const Map<String, String> kTableMajorImageUrls = {
  '면류':
      'https://images.unsplash.com/photo-1612929633738-8fe44f7ec841?auto=format&fit=crop&w=400&q=80',
  '상온HMR':
      'https://images.unsplash.com/photo-1516684669134-de6f7c473a2a?auto=format&fit=crop&w=400&q=80',
  '음료':
      'https://images.unsplash.com/photo-1548839140-29a749e1cf4d?auto=format&fit=crop&w=400&q=80',
  '유제품':
      'https://images.unsplash.com/photo-1563636619-e9143da7973b?auto=format&fit=crop&w=400&q=80',
  '커피차':
      'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?auto=format&fit=crop&w=400&q=80',
  '과자':
      'https://images.unsplash.com/photo-1599490659213-e2b9527bd087?auto=format&fit=crop&w=400&q=80',
  '디저트':
      'https://images.unsplash.com/photo-1488477181946-6428a0291777?auto=format&fit=crop&w=400&q=80',
  '통조림/안주':
      'https://images.unsplash.com/photo-1588166524941-3bf61a9c41db?auto=format&fit=crop&w=400&q=80',
  '소스':
      'https://images.unsplash.com/photo-1472476443507-6e15bbba9d8d?auto=format&fit=crop&w=400&q=80',
  '주류':
      'https://images.unsplash.com/photo-1510812431401-41d2bd2722f3?auto=format&fit=crop&w=400&q=80',
};

String tableMajorLabel(String name) => kTableMajorLabels[name] ?? name;
String? tableMajorImageUrl(String name) => kTableMajorImageUrls[name];

List<TableMajor> orderedTableTaxonomy() {
  final byName = {for (final m in kTableTaxonomy) m.name: m};
  final out = <TableMajor>[];
  for (final name in kTableMajorOrder) {
    final m = byName.remove(name);
    if (m != null) out.add(m);
  }
  out.addAll(byName.values);
  return out;
}

TableMajor? tableMajorByName(String name) {
  for (final m in kTableTaxonomy) {
    if (m.name == name) return m;
  }
  return null;
}
