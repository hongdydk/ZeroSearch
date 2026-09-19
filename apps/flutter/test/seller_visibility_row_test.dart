import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_mall/features/seller/seller_visibility_row.dart';

void main() {
  testWidgets('visibility row shows 공개 when on and 비공개 when off', (tester) async {
    var isPublic = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SellerVisibilityRow(
              isPublic: isPublic,
              onChanged: (value) => setState(() => isPublic = value),
            ),
          ),
        ),
      ),
    );

    expect(find.text('가시성'), findsOneWidget);
    expect(find.text('공개'), findsOneWidget);
    expect(find.text('비공개'), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(find.text('비공개'), findsOneWidget);
    expect(find.text('공개'), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });
}
