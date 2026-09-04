/// AI-Hub 카탈로그(대·중·소분류) 기반 식탁 분류. 제품 유무와 무관.
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
  TableMajor(name: '과자', mids: [
    TableMid(name: '스낵', minors: ['감자스낵', '고구마스낵', '과일스낙', '과일스낵', '밀가루스낵', '비스킷/스틱과자', '샌드', '스틱과자', '쌀과자', '쌀스낵', '야채스낵', '옥수수스낵', '일반스낵', '쿠키', '팝콘']),
    TableMid(name: '건채소', minors: ['고구마']),
    TableMid(name: '과채음료', minors: ['과일음료']),
    TableMid(name: '파이류', minors: ['과자세트', '과제세트', '케이크', '쿠키', '파이']),
    TableMid(name: '차류', minors: ['과칠차']),
    TableMid(name: '아이스크림', minors: ['구슬아이스크림']),
    TableMid(name: '껌류', minors: ['기능성껌', '일반꺼', '일반껌', '토이껌류', '풍선껌']),
    TableMid(name: '씨리얼', minors: ['기능성시리얼', '씨리얼바', '일반시리얼', '일반씨리얼', '일빈시리얼']),
    TableMid(name: '캔디', minors: ['기능성캔디', '사탕/캔디세트', '소프르캔디', '소프트캔디', '양갱', '젤리', '캐러멜', '케러멜', '토이캔디', '하드캔디', '하드켄디']),
    TableMid(name: '기타', minors: ['기타']),
    TableMid(name: '유아식품', minors: ['기타간식/안주형과자']),
    TableMid(name: '견과류', minors: ['기타견과류', '땅콩', '밤', '브라질넛', '아몬드', '피스타치오', '호두', '혼합견과']),
    TableMid(name: '전통과자', minors: ['기타전통과자']),
    TableMid(name: '가공분말류', minors: ['기타프리믹스']),
    TableMid(name: '냉장음료', minors: ['냉장곡물견과음료']),
    TableMid(name: '소스류', minors: ['맛가루']),
    TableMid(name: '문화용품', minors: ['문구']),
    TableMid(name: '과자', minors: ['밀가루스낵', '비스킷', '쌀과자']),
    TableMid(name: '비스킷', minors: ['밀가루스낵', '샌드', '스탁과자', '스틱과자', '쌀과자', '쌀스낵', '옥수수스낵', '쿠키', '크래커', '크레커']),
    TableMid(name: '초콜렛', minors: ['바초콜릿', '쉘초콜렛', '쉘초콜릿', '초콜릿세트', '초콜릿칩', '판초콜릿']),
    TableMid(name: '레저취미', minors: ['반려묘간식']),
    TableMid(name: '건강보조식품', minors: ['비타민/미네랄']),
    TableMid(name: '비스', minors: ['스틱과자']),
    TableMid(name: '빵', minors: ['식빵', '일반빵', '호빵']),
    TableMid(name: '마른안주', minors: ['어포류']),
    TableMid(name: '토이', minors: ['토이캔디']),
    TableMid(name: '사탕', minors: ['하드캔디']),
  ]),
  TableMajor(name: '디저트', mids: [
    TableMid(name: '건과일', minors: ['건포도', '대추']),
    TableMid(name: '병통조림', minors: ['과일병통조림']),
    TableMid(name: '과채음료', minors: ['과일음료']),
    TableMid(name: '퓨레', minors: ['과일퓨레']),
    TableMid(name: '베이커리', minors: ['과자빵']),
    TableMid(name: '디저트/베이커리', minors: ['냉동디저트', '냉장디저트']),
    TableMid(name: '푸딩/젤리', minors: ['냉장젤리류', '냉장푸딩류']),
    TableMid(name: '파이류', minors: ['케이크']),
    TableMid(name: '비스킷', minors: ['크래커']),
  ]),
  TableMajor(name: '면류', mids: [
    TableMid(name: '봉지면', minors: ['국물봉지라면', '비빔봉지라면']),
    TableMid(name: '용기면', minors: ['국물용기라면', '비빔용기라면']),
  ]),
  TableMajor(name: '상온HMR', mids: [
    TableMid(name: '분말조미료', minors: ['가공조미료', '기타향신료', '깨', '자연조미료', '후추']),
    TableMid(name: '가공분말류', minors: ['곡물가루']),
    TableMid(name: '가곡분말류', minors: ['곡물가루']),
    TableMid(name: '병통조림', minors: ['과일병통조림']),
    TableMid(name: '절임/잼', minors: ['과일잼', '스프레드']),
    TableMid(name: '레토르트', minors: ['기타레토르트']),
    TableMid(name: '분말조리식', minors: ['기타분말조리식']),
    TableMid(name: '설탕류', minors: ['기타설탕류']),
    TableMid(name: '식용유', minors: ['기타식용유', '올리브유', '참기름/들기름', '포도씨유']),
    TableMid(name: '잡곡', minors: ['기타잡곡류']),
    TableMid(name: '분말조미류', minors: ['기타향신료']),
    TableMid(name: '소스류', minors: ['맛가루', '상온드레싱', '향미유']),
    TableMid(name: '액상조미료', minors: ['식초']),
    TableMid(name: '소금류', minors: ['암염', '정제염', '천일염']),
    TableMid(name: '스낵', minors: ['야채스낵', '영유아과자']),
    TableMid(name: '비스킷', minors: ['쿠키']),
  ]),
  TableMajor(name: '생활용품', mids: [
    TableMid(name: '위생용품', minors: ['구강용품']),
    TableMid(name: '기타', minors: ['기타']),
  ]),
  TableMajor(name: '소스', mids: [
    TableMid(name: '분말조미료', minors: ['가공조미료', '기타향신료', '깨', '자연조미료', '후추']),
    TableMid(name: '치즈', minors: ['가루치즈']),
    TableMid(name: '장류', minors: ['간장', '겨자/고추냉이', '고추장', '기타장류', '된장', '쌈장']),
    TableMid(name: '설탕류', minors: ['갈색설탕', '물엿/시럽', '하얀설탕']),
    TableMid(name: '소스류', minors: ['고기양념장', '국물용소스', '마요네즈', '물엿/시럽', '상온드레싱', '앙념소스', '양념소스', '케첩', '파스타소스']),
    TableMid(name: '가공분말류', minors: ['곡물가루', '기타제빵재료', '도넛가루/핫케이크가루', '부침가루', '빵가루', '빵믹스', '튀김가루']),
    TableMid(name: '차류', minors: ['과실차', '허브/꽃차']),
    TableMid(name: '절임/잼', minors: ['과일잼', '스프레드']),
    TableMid(name: '액상조미료', minors: ['맛술', '식초', '액상조미료', '액젓', '음용식초']),
    TableMid(name: '가공분만류', minors: ['밀가루']),
    TableMid(name: '소금류', minors: ['암염', '정제염', '제재염', '천일염', '호수염']),
    TableMid(name: '식용유', minors: ['옥수수기름', '참기름/들기름', '콩기름', '향미유']),
    TableMid(name: '주방세제', minors: ['일반주방세제']),
  ]),
  TableMajor(name: '유제품', mids: [
    TableMid(name: '우유', minors: ['가공우유', '일반우유']),
    TableMid(name: '버터', minors: ['가염버터', '마가린', '무염버터']),
    TableMid(name: '치즈', minors: ['까망베르치즈', '리코타치즈', '모짜렐라치즈', '생치즈', '체다치즈', '크림치즈']),
    TableMid(name: '요구르트', minors: ['떠먹는 요구르트', '마시는 요구르트']),
  ]),
  TableMajor(name: '음료', mids: [
    TableMid(name: '탄산수', minors: ['Flavor탄산수', '플레인탄산수', '플렝니탄산수']),
    TableMid(name: '우유', minors: ['가공우유', '기능성우유']),
    TableMid(name: '장류', minors: ['간장']),
    TableMid(name: '소스류', minors: ['고추장']),
    TableMid(name: '차류', minors: ['과실차', '녹차/홍차']),
    TableMid(name: '과채음료', minors: ['과일음료', '과채혼합음료', '어린이음료', '원액', '채소음료']),
    TableMid(name: '맥주', minors: ['국산맥주', '수입맥주']),
    TableMid(name: '두유', minors: ['기능성두유', '일반두유']),
    TableMid(name: '기타', minors: ['기타']),
    TableMid(name: '기능성음료', minors: ['기타', '기타기능성음료', '비타민/에너지음료', '숙취해소음료', '스포츠음료', '식이섬유음료', '한방음료']),
    TableMid(name: '전통주', minors: ['기타전통주', '일본술']),
    TableMid(name: '차음료', minors: ['기타차음료', '일반', '일반차음료', '전통차음료']),
    TableMid(name: '냉장음료', minors: ['냉장곡물견과음료', '코코넛워터']),
    TableMid(name: '욕실주거세제', minors: ['다목적주방세제']),
    TableMid(name: '탄산음료', minors: ['무알콜맥주', '사이다', '콜라', '혼합탄산', '홉합탄산']),
    TableMid(name: '과일음료', minors: ['어린이음료']),
    TableMid(name: '액상조미료', minors: ['음용식초']),
    TableMid(name: '생수', minors: ['일반생수']),
    TableMid(name: '커피음료', minors: ['커피음료']),
  ]),
  TableMajor(name: '이/미용', mids: [
    TableMid(name: '캔디', minors: ['기능성캔디']),
    TableMid(name: '화장품', minors: ['메이크업세트']),
    TableMid(name: '면봉/화장솜', minors: ['면봉/화장솜']),
    TableMid(name: '레저취미', minors: ['반려견간식']),
    TableMid(name: '생수', minors: ['일반생수']),
  ]),
  TableMajor(name: '주류', mids: [
    TableMid(name: '전통주', minors: ['고량주', '과실주', '막걸리', '사케', '청주']),
    TableMid(name: '맥주', minors: ['국내맥주', '무알콜맥주', '수입맥주']),
    TableMid(name: '기타주류', minors: ['럼', '보드카', '샴페인', '요리주', '위스키', '진', '칵테일']),
    TableMid(name: '와인', minors: ['레드와인', '로제와인', '스파클링와인', '화이트와인']),
    TableMid(name: '소주', minors: ['증류식소주']),
  ]),
  TableMajor(name: '커피차', mids: [
    TableMid(name: '액상차', minors: ['과실절임차', '기타', '생강차', '아이스티', '전통차', '커피']),
    TableMid(name: '분말차', minors: ['과실절임차', '기타', '꿀차', '녹차', '녹차/현미녹차', '둥굴레차', '마테차', '메밀차', '밀크티', '보리차', '뿌리차', '생강차', '아이스티', '옥수수차', '우엉차', '잎차', '전통차', '커피', '코코아/핫초코', '허브차', '홍차']),
  ]),
  TableMajor(name: '통조림/안주', mids: [
    TableMid(name: '통조림', minors: ['가미통조림', '과일통조림', '보일드통조림', '애견식품']),
    TableMid(name: '안주', minors: ['견과류', '냉장/냉동식품', '수산물/건해산']),
  ]),
];

/// 홈 「오늘 추천」·식탁 노출 순서 (밥상 우선).
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
  '생활용품',
  '이/미용',
];

/// 홈 「오늘 추천」카드에 쓰는 대분류.
const List<String> kTodayMajorNames = [
  '면류',
  '상온HMR',
  '음료',
  '유제품',
  '과자',
  '디저트',
];

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
