import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parent_app/design/seftly_theme.dart';
import 'package:parent_app/screens/dashboard_screen.dart';
import 'package:parent_app/services/api_service.dart';

void main() {
  final original = ApiService.instance;
  setUpAll(() async {
    var sdk = File(Platform.resolvedExecutable).parent;
    while (!Directory('${sdk.path}/bin/cache/artifacts/material_fonts')
            .existsSync() &&
        sdk.parent.path != sdk.path) {
      sdk = sdk.parent;
    }
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf'
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(Future.value(ByteData.sublistView(File(
                '${sdk.path}/bin/cache/artifacts/material_fonts/${entry.value}')
            .readAsBytesSync())));
      await loader.load();
    }
  });
  tearDown(() => ApiService.instance = original);
  List<Map<String, dynamic>> fixtures(int count, {bool offline = false}) =>
      List.generate(
          count,
          (i) => {
                'id': 'child-$i',
                'name': i == 0
                    ? 'Alexandra Montgomery with a very long family name'
                    : 'Child ${i + 1}',
                'username': 'fixture-$i',
                'device': {
                  'id': 'device-$i',
                  'deviceName': 'QA Android ${i + 1}',
                  'platform': 'Android',
                  'status': offline || i.isOdd ? 'OFFLINE' : 'ONLINE',
                  'lastSeen': '2026-10-13T10:00:00Z'
                }
              });
  Future<void> pump(WidgetTester tester, List<Map<String, dynamic>> children,
      {Size size = const Size(390, 844),
      bool dark = false,
      double scale = 1,
      List<String>? requests}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ApiService.instance = ApiService(client: MockClient((r) async {
      requests?.add(r.url.path);
      return http.Response(
          jsonEncode(r.url.path == '/api/children'
              ? {'children': children}
              : r.url.path.endsWith('/policies')
                  ? {'policies': [], 'apps': [], 'isPaused': false}
                  : {'events': [], 'rules': []}),
          200);
    }));
    await tester.pumpWidget(MaterialApp(
        theme: dark ? SeftlyTheme.dark() : SeftlyTheme.light(),
        builder: (c, w) => MediaQuery(
            data:
                MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: w!),
        home: DashboardScreen(now: () => DateTime(2026, 10, 13, 17, 0))));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  for (final count in [1, 2, 3, 5, 10]) {
    for (final dark in [false, true]) {
      testWidgets(
          '$count compact children start collapsed and remain reachable; dark=$dark',
          (tester) async {
        await pump(tester, fixtures(count),
            size: const Size(320, 720), dark: dark, scale: 2);
        expect(find.text('My Children · $count'), findsOneWidget);
        expect(find.byType(ChildOverviewCard), findsNothing);
        await tester.scrollUntilVisible(
            find.byKey(ValueKey('child-toggle-child-${count - 1}')), 200,
            scrollable: find.byType(Scrollable).first);
        expect(find.byKey(ValueKey('child-toggle-child-${count - 1}')),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        await close(tester);
      });
    }
  }
  testWidgets(
      'Accordion expands one child, collapses on retap, and preserves selection during status refresh',
      (tester) async {
    final rows = fixtures(3);
    await pump(tester, rows);
    await tester.tap(find.byKey(const ValueKey('child-toggle-child-0')));
    await tester.pumpAndSettle();
    expect(find.text('QA Android 1'), findsOneWidget);
    rows[0]['device'] = {...rows[0]['device'] as Map, 'status': 'OFFLINE'};
    await tester.tap(find.byTooltip('Refresh family'));
    await tester.pumpAndSettle();
    expect(find.text('QA Android 1'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('child-toggle-child-1')), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('child-toggle-child-1')));
    await tester.pumpAndSettle();
    expect(find.text('QA Android 1'), findsNothing);
    expect(find.text('QA Android 2'), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const ValueKey('child-toggle-child-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('child-toggle-child-1')));
    await tester.pumpAndSettle();
    expect(find.byType(ChildOverviewCard), findsNothing);
    await close(tester);
  });
  testWidgets('Expanded app controls use the chosen child identity',
      (tester) async {
    final requests = <String>[];
    await pump(tester, fixtures(3), requests: requests);
    await tester.tap(find.byKey(const ValueKey('child-toggle-child-1')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('App rules'), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('App rules'));
    await tester.pumpAndSettle();
    expect(requests.any((p) => p.contains('/child-1/')), isTrue);
    expect(requests.any((p) => p.contains('/child-0/')), isFalse);
    await close(tester);
  });
  for (final dark in [false, true]) {
    testWidgets('Three collapsed cards dashboard golden; dark=$dark',
        (tester) async {
      await pump(tester, fixtures(3), dark: dark);
      await expectLater(
          find.byType(Scaffold).first,
          matchesGoldenFile(
              'goldens/dashboard-collapsed-${dark ? 'dark' : 'light'}.png'));
      await close(tester);
    });
    testWidgets('One expanded child dashboard golden; dark=$dark',
        (tester) async {
      await pump(tester, fixtures(3), dark: dark);
      await tester.tap(find.byKey(const ValueKey('child-toggle-child-0')));
      await tester.pumpAndSettle();
      await expectLater(
          find.byType(Scaffold).first,
          matchesGoldenFile(
              'goldens/dashboard-expanded-${dark ? 'dark' : 'light'}.png'));
      await close(tester);
    });
  }
  testWidgets('Empty family still offers creation', (tester) async {
    await pump(tester, []);
    expect(find.text('Start with your first child'), findsOneWidget);
    expect(find.text('Add a child'), findsWidgets);
    await close(tester);
  });
  testWidgets('Ten compact children fit a tablet with large text',
      (tester) async {
    await pump(tester, fixtures(10), size: const Size(800, 1024), scale: 2);
    await tester.scrollUntilVisible(find.text('Child 10'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
    await close(tester);
  });
  testWidgets('Three collapsed cards on a small screen golden', (tester) async {
    await pump(tester, fixtures(3), size: const Size(320, 720));
    await expectLater(find.byType(Scaffold).first,
        matchesGoldenFile('goldens/dashboard-small.png'));
    await close(tester);
  });
}
