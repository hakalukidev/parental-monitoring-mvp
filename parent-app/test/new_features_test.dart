import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parent_app/design/seftly_theme.dart';
import 'package:parent_app/design/family_date_time.dart';
import 'package:parent_app/screens/activity_history_screen.dart';
import 'package:parent_app/screens/sound_around_screen.dart';
import 'package:parent_app/services/api_service.dart';
import 'package:parent_app/services/app_info.dart';

void main() {
  final original = ApiService.instance;
  tearDown(() => ApiService.instance = original);
  Future<void> pump(WidgetTester tester, Widget page,
      {bool dark = false, double scale = 1}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: dark ? SeftlyTheme.dark() : SeftlyTheme.light(),
        builder: (c, w) => MediaQuery(
            data:
                MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: w!),
        home: page));
    await tester.pumpAndSettle();
  }

  for (final kind in ['CALL', 'SMS', 'NOTIFICATION', 'SAFETY']) {
    for (final dark in [false, true]) {
      testWidgets(
          '$kind shows disabled, offline, empty and unknown access honestly; dark=$dark',
          (tester) async {
        ApiService.instance = ApiService(client: MockClient((r) async {
          expect(r.url.path, contains('selected-child'));
          final body = r.url.path.contains('/policy/')
              ? {
                  'policy': {'monitoredPackages': [], 'retentionDays': 30},
                  'features': {
                    'notifications': false,
                    'callSms': false,
                    'safety': false
                  },
                  'capabilities': null,
                  'online': false
                }
              : {'records': [], 'nextCursor': null, 'total': 0};
          return http.Response(jsonEncode(body), 200);
        }));
        await pump(
            tester,
            ActivityHistoryScreen(
                childId: 'selected-child',
                childName: 'Selected Child',
                kind: kind),
            dark: dark,
            scale: 2);
        expect(find.text('Feature unavailable on this server'), findsOneWidget);
        expect(find.textContaining('Device access: UNKNOWN'), findsOneWidget);
        await tester.scrollUntilVisible(
            find.text('No activity reported for this selection.'), 200,
            scrollable: find.byType(Scrollable).first);
        expect(find.text('No activity reported for this selection.'),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('Activity errors include a real retry action', (tester) async {
    ApiService.instance = ApiService(
        client: MockClient((r) async =>
            http.Response(jsonEncode({'error': 'Network unavailable'}), 503)));
    await pump(
        tester,
        const ActivityHistoryScreen(
            childId: 'fixture', childName: 'Fixture', kind: 'CALL'));
    expect(find.text('Activity unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
  testWidgets(
      'Denied permission and actual masked call metadata are rendered without fabricated identifiers',
      (tester) async {
    ApiService.instance = ApiService(
        client: MockClient((r) async => http.Response(
            jsonEncode(r.url.path.contains('/policy/')
                ? {
                    'policy': {'callsEnabled': true},
                    'features': {'callSms': true},
                    'capabilities': {'callLogAccess': 'DENIED_OR_RESTRICTED'},
                    'online': true
                  }
                : {
                    'records': [
                      {
                        '_id': 'fixture',
                        'direction': 'MISSED',
                        'maskedIdentifier': '****1234',
                        'eventAt': '2026-10-12T22:00:00Z',
                        'durationSeconds': 0
                      }
                    ],
                    'nextCursor': null
                  }),
            200)));
    await pump(
        tester,
        const ActivityHistoryScreen(
            childId: 'fixture', childName: 'Fixture', kind: 'CALL'));
    expect(find.text('Device permission or model unavailable'), findsOneWidget);
    expect(find.textContaining('****1234'), findsOneWidget);
    expect(find.textContaining('Duration 0 seconds'), findsOneWidget);
  });
  testWidgets(
      'Audio starts idle and disabled server cannot show fake live or invoke capture',
      (tester) async {
    ApiService.instance = ApiService(
        client: MockClient((r) async => http.Response(
            jsonEncode({
              'features': {'audioCheckIn': false}
            }),
            200)));
    await pump(tester,
        const SoundAroundScreen(childId: 'fixture', childName: 'Fixture'));
    expect(find.text('Ready to request a check-in'), findsOneWidget);
    await tester.tap(find.text('Request audio check-in'));
    await tester.pumpAndSettle();
    expect(find.text('Check-in unavailable'), findsOneWidget);
    expect(find.text('Live audio received'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  test(
      'Calendar labels follow local dates across midnight, not elapsed 24-hour buckets',
      () {
    final now = DateTime(2026, 3, 9, 0, 5);
    expect(FamilyDateTime.dayLabel(DateTime(2026, 3, 8, 23, 55), now: now),
        'Yesterday');
    expect(
        FamilyDateTime.dayLabel(DateTime(2026, 3, 9, 0, 1), now: now), 'Today');
    expect(FamilyDateTime.format(null), 'Not reported');
    expect(
        FamilyDateTime.format(DateTime.utc(2026, 10, 13, 0),
            pattern: 'y-MM-dd HH:mm'),
        isNotEmpty);
  });
  testWidgets('Installed app version comes from Android metadata',
      (tester) async {
    const channel = MethodChannel('seftly/app_info');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel, (call) async => {'version': '1.2.0', 'build': 3});
    expect(await AppInfo.installedVersion(), '1.2.0 · build 3');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
