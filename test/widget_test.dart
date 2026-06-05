// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:excel_voice_reader/main.dart';

void main() {
  testWidgets('shows the Excel voice reader home screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ExcelVoiceReaderApp());

    expect(find.text('Excel Voice Reader'), findsWidgets);
    expect(find.text('Load Excel File'), findsOneWidget);
    expect(find.text('Choose an Excel workbook to begin.'), findsOneWidget);
  });
}
