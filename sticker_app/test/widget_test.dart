// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:sticker_app/main.dart';
import 'package:sticker_app/services/storage_service.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    final storage = StorageService();
    await tester.pumpWidget(MyApp(storage: storage));
    await tester.pumpAndSettle();

    expect(find.text('表情包管理'), findsOneWidget);
  });
}
