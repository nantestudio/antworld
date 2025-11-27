// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:antworld/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders main menu actions', (tester) async {
    await tester.pumpWidget(const AntWorldApp());

    expect(find.text('AntWorld'), findsOneWidget);
    expect(find.textContaining('Start New Colony'), findsOneWidget);
    expect(find.text('Continue Last Colony'), findsOneWidget);
  });
}
