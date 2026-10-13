import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parent_app/design/seftly_theme.dart';
import 'package:parent_app/screens/communication_history_screen.dart';
import 'package:parent_app/services/api_service.dart';

void main() {
  final original = ApiService.instance;
  tearDown(() => ApiService.instance = original);
  Future<void> pump(WidgetTester tester, String kind,
      {bool dark = false, double scale = 1}) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: dark ? SeftlyTheme.dark() : SeftlyTheme.light(),
        builder: (c, w) => MediaQuery(
            data:
                MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: w!),
        home: CommunicationHistoryScreen(
            childId: 'selected-child',
            childName: 'Synthetic Child',
            kind: kind)));
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> configuration(
          {bool available = true, String access = 'GRANTED'}) =>
      {
        'available': available,
        'online': false,
        'policy': {
          'fullCommunicationHistoryEnabled': true,
          'callsEnabled': true,
          'smsEnabled': true,
          'messageBodiesEnabled': true
        },
        'capabilities': {
          'callLogAccess': access,
          'smsAccess': access,
          'queuedRecords': 2,
          'droppedRecords': 0
        }
      };
  for (final dark in [false, true]) {
    testWidgets(
        'Messages preserve authorized text, suppress withheld payloads and handle narrow large text; dark=$dark',
        (tester) async {
      ApiService.instance = ApiService(client: MockClient((request) async {
        expect(request.url.path, contains('selected-child'));
        final data = request.url.path.contains('/policy/')
            ? configuration()
            : request.url.path.endsWith('/stats')
                ? {'daily': [], 'weekly': [], 'timeZone': 'Asia/Dhaka'}
                : {
                    'records': [
                      {
                        'id': '1',
                        'transport': 'SMS',
                        'direction': 'INCOMING',
                        'eventAt': '2026-10-13T08:00:00Z',
                        'contentStatus': 'AVAILABLE',
                        'details': {
                          'address': '+15550101234',
                          'body': 'School project is ready',
                          'read': false,
                          'sourceId': '12'
                        }
                      },
                      {
                        'id': '2',
                        'transport': 'SMS',
                        'direction': 'INCOMING',
                        'eventAt': '2026-10-13T08:00:01Z',
                        'contentStatus': 'WITHHELD_SECURITY',
                        'details': {
                          'address': 'QA',
                          'body': 'OTP must remain hidden',
                          'sourceId': '13'
                        }
                      }
                    ],
                    'total': 2
                  };
        return http.Response(jsonEncode(data), 200);
      }));
      await pump(tester, 'SMS', dark: dark, scale: 2);
      await tester.scrollUntilVisible(find.text('School project is ready'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('School project is ready'), findsOneWidget);
      await tester.scrollUntilVisible(
          find.text('Content withheld for security'), 250,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('OTP must remain hidden'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'Missing duration stays unknown and search is scoped to selected child',
      (tester) async {
    final requests = <Uri>[];
    ApiService.instance = ApiService(client: MockClient((r) async {
      requests.add(r.url);
      return http.Response(
          jsonEncode(r.url.path.contains('/policy/')
              ? configuration()
              : r.url.path.endsWith('/stats')
                  ? {'daily': [], 'weekly': []}
                  : {
                      'records': [
                        {
                          'id': '1',
                          'transport': 'CALL',
                          'direction': 'MISSED',
                          'eventAt': '2026-10-13T08:00:00Z',
                          'details': {
                            'phoneNumber': '+15550101234',
                            'sourceId': '1'
                          }
                        }
                      ],
                      'total': 1
                    }),
          200);
    }));
    await pump(tester, 'CALL');
    await tester.scrollUntilVisible(find.text('Duration not reported'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Duration 0 seconds'), findsNothing);
    await tester.scrollUntilVisible(find.byType(TextField), -250,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.byType(TextField), '15550101234');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(
        requests.where((u) =>
            u.queryParameters['search'] == '15550101234' &&
            u.path.endsWith('/CALL')),
        isNotEmpty);
  });
  testWidgets('Revoked Android access remains explicit with historical records',
      (tester) async {
    ApiService.instance = ApiService(
        client: MockClient((r) async => http.Response(
            jsonEncode(r.url.path.contains('/policy/')
                ? configuration(access: 'DENIED_OR_RESTRICTED')
                : {'records': [], 'daily': [], 'weekly': []}),
            200)));
    await pump(tester, 'SMS');
    expect(find.text('Android access unavailable'), findsOneWidget);
    expect(find.text('Android access: DENIED_OR_RESTRICTED'), findsOneWidget);
  });
}
