import 'package:flutter_test/flutter_test.dart';
import 'package:test1/main.dart';

void main() {
  testWidgets('NurseNet app loads splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const NurseNetApp());
    expect(find.text('NurseNet'), findsOneWidget);
  });
}
