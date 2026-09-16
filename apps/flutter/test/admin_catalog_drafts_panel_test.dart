import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/theme/app_theme.dart';
import 'package:shopping_mall/features/admin/admin_screen.dart';

IntakeDraftModel _draft({
  required String id,
  required String kind,
  String title = '떡갈비',
  String manufacturer = '매일',
}) {
  return IntakeDraftModel(
    id: id,
    kind: kind,
    status: 'pending',
    sellerId: 's1',
    shopName: '입점마트',
    title: title,
    category: '축산가공',
    priceCredits: 4800,
    stock: 10,
    manufacturer: manufacturer,
    optionLabel: '500g',
  );
}

void main() {
  testWidgets('admin catalog queue shows attach and promote actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String attached = '';
    String promoted = '';

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.web(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminCatalogDraftsPanel(
              drafts: [
                _draft(id: 'offer-1', kind: 'offer', title: '백산수', manufacturer: '농심'),
                _draft(id: 'card-1', kind: 'card'),
              ],
              pageLocked: false,
              isRowBusy: (_) => false,
              onAttach: (draft) => attached = draft.id,
              onPromote: (draft) => promoted = draft.id,
            ),
          ),
        ),
      ),
    );

    expect(find.text('카드 검수 큐 2건'), findsOneWidget);
    expect(find.textContaining('오퍼 초안'), findsOneWidget);
    expect(find.textContaining('카드 초안'), findsOneWidget);
    expect(find.text('승인'), findsOneWidget);
    expect(find.text('기존 카드에 붙이기'), findsOneWidget);
    expect(find.text('카드로 승격'), findsOneWidget);

    await tester.tap(find.text('승인'));
    await tester.pump();
    expect(attached, 'offer-1');

    await tester.tap(find.text('카드로 승격'));
    await tester.pump();
    expect(promoted, 'card-1');
  });

  testWidgets('empty catalog queue explains there are no drafts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.web(),
        home: const Scaffold(
          body: AdminCatalogDraftsPanel(
            drafts: [],
            pageLocked: false,
            isRowBusy: _neverBusy,
            onAttach: _noopDraft,
            onPromote: _noopDraft,
          ),
        ),
      ),
    );

    expect(find.text('대기 중인 오퍼·카드 초안이 없습니다.'), findsOneWidget);
  });
}

bool _neverBusy(String id) => false;

void _noopDraft(IntakeDraftModel draft) {}
