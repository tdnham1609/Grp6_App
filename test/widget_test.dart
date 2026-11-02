import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deadmansswitch/app/app.dart';

void main() {
  testWidgets('Sinh Tu main navigation displays home screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MainNavigation()));

    expect(find.text('SINH TỬ'), findsOneWidget);
    expect(find.text('Bạn vẫn an toàn chứ?'), findsOneWidget);
  });
}
