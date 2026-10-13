import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parent_app/design/seftly_theme.dart';
import 'package:parent_app/design/website_rule_editor.dart';
import 'package:parent_app/services/api_service.dart';

void main() {
  final original = ApiService.instance;
  tearDown(() => ApiService.instance = original);
  Future<void> editor(WidgetTester tester,
      {bool dark = false, double scale = 1}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: dark ? SeftlyTheme.dark() : SeftlyTheme.light(),
        builder: (_, w) => MediaQuery(
            data: MediaQueryData(
                size: const Size(390, 844),
                textScaler: TextScaler.linear(scale)),
            child: w!),
        home: const Scaffold(body: WebsiteRuleEditor(childId: 'fixture'))));
  }

  testWidgets(
      'Website preview preserves exact-path scope and enables saving only after validation',
      (tester) async {
    ApiService.instance = ApiService(client: MockClient((r) async {
      expect(r.url.path, '/api/children/fixture/web-rules/preview');
      expect(jsonDecode(r.body)['target'], 'www.example.com/Study');
      return http.Response(
          jsonEncode(
              {'ruleType': 'URL', 'target': 'https://example.com/Study'}),
          200);
    }));
    await editor(tester);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save rule'))
            .onPressed,
        isNull);
    await tester.enterText(find.byType(TextField), 'www.example.com/Study');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('https://example.com/Study'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save rule'))
            .onPressed,
        isNotNull);
    await tester.enterText(find.byType(TextField), 'example.com/other');
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save rule'))
            .onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'Invalid website shows recovery and cannot save in dark enlarged layout',
      (tester) async {
    ApiService.instance = ApiService(
        client: MockClient((r) async => http.Response(
            jsonEncode({'error': 'Use an HTTP/HTTPS website address'}), 422)));
    await editor(tester, dark: true, scale: 2);
    await tester.enterText(find.byType(TextField), 'javascript:bad');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Retry validation'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save rule'))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });
}
