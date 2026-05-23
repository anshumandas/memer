import 'package:flutter_test/flutter_test.dart';

import 'package:memer/app.dart';

void main() {
  testWidgets('App boots to the home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MemeMakerApp());
    await tester.pumpAndSettle();

    expect(find.text('Meme Maker'), findsWidgets);
  });
}
