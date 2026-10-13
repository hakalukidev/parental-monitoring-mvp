import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parent_app/design/form_validation.dart';
import 'package:parent_app/design/seftly_theme.dart';
import 'package:parent_app/design/seftly_widgets.dart';
import 'package:parent_app/models/app_usage_report.dart';
import 'package:parent_app/models/child.dart';
import 'package:parent_app/screens/login_screen.dart';
import 'package:parent_app/screens/register_screen.dart';
import 'package:parent_app/screens/create_child_screen.dart';
import 'package:parent_app/screens/dashboard_screen.dart';
import 'package:parent_app/screens/app_blocker_screen.dart';
import 'package:parent_app/screens/web_filter_screen.dart';
import 'package:parent_app/screens/browsing_history_screen.dart';
import 'package:parent_app/screens/geofences_screen.dart';
import 'package:parent_app/screens/app_usage_report_screen.dart';
import 'package:parent_app/services/api_service.dart';

void main() {
  final originalApi = ApiService.instance;
  setUpAll(() async {
    var sdk = File(Platform.resolvedExecutable).parent;
    while (!Directory('${sdk.path}/bin/cache/artifacts/material_fonts')
            .existsSync() &&
        sdk.parent.path != sdk.path) {
      sdk = sdk.parent;
    }
    final fonts = '${sdk.path}/bin/cache/artifacts/material_fonts';
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf'
    }.entries) {
      final font = File('$fonts/${entry.value}');
      if (!font.existsSync()) {
        throw StateError('Flutter test fonts unavailable: $font');
      }
      final loader = FontLoader(entry.key)
        ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
      await loader.load();
    }
  });
  tearDown(() {
    ApiService.instance = originalApi;
  });
  Future<void> pump(WidgetTester tester, Widget child,
      {Size size = const Size(390, 844),
      double scale = 1,
      bool dark = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: dark ? SeftlyTheme.dark() : SeftlyTheme.light(),
        builder: (context, widget) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: widget!),
        home: child));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  void mockApi(
      {bool fail = false,
      List<Map<String, dynamic>> children = const [],
      List<String>? requests}) {
    ApiService.instance = ApiService(client: MockClient((req) async {
      requests?.add(req.url.path);
      if (fail) {
        return http.Response(
            jsonEncode({'error': 'Connection unavailable'}), 503);
      }
      final path = req.url.path;
      Map<String, dynamic> body = {};
      if (path == '/api/children') {
        body = {'children': children};
      }
      if (path.endsWith('/apps')) {
        body = {'apps': [], 'isPaused': false};
      }
      if (path.endsWith('/web-rules')) {
        body = {'rules': []};
      }
      if (path.endsWith('/browsing-history')) {
        body = {'records': [], 'total': 0, 'totalPages': 0};
      }
      if (path.endsWith('/analytics')) {
        body = {
          'totalVisited': 0,
          'blockedAttempts': 0,
          'topDomains': [],
          'categoryDistribution': {}
        };
      }
      if (path.endsWith('/geofences')) {
        body = {'geofences': []};
      }
      if (path.endsWith('/geofence-events') ||
          path.endsWith('/unread-summary')) {
        body = {'events': [], 'total': 0};
      }
      if (path.endsWith('/usage/today')) {
        body = {
          'childId': 'sample-child',
          'date': '2026-10-12',
          'lastSyncedAt': null,
          'dataAvailable': false,
          'summary': {'usageAvailable': false},
          'apps': [],
          'categoryBreakdown': [],
          'hourlyUsage': []
        };
      }
      return http.Response(jsonEncode(body), 200,
          headers: {'content-type': 'application/json'});
    }));
  }

  test(
      'validation rejects malformed emails, short passwords and invalid child logins',
      () {
    expect(FormValidation.email('parent@'), isNotNull);
    expect(FormValidation.email(' parent@example.test '), isNull);
    expect(FormValidation.password('short'), isNotNull);
    expect(FormValidation.password('eight-characters'), isNull);
    expect(FormValidation.username('ab'), isNotNull);
    expect(FormValidation.username('kid_name-1'), isNull);
  });
  test('missing usage measurements and synchronization remain unknown', () {
    final report = AppUsageReport.fromJson({
      'summary': {'totalScreenTimeSeconds': 0},
      'lastSyncedAt': null
    });
    expect(report.lastSyncedAt, isNull);
    expect(report.summary.formattedScreenTime, 'Unavailable');
    expect(report.summary.formattedDowntime, 'Unavailable');
    expect(report.summary.formattedScreenOff, 'Unavailable');
    expect(UsageSummary.duration(3661), '1h 1m');
    expect(UsageSummary.duration(0), '0s');
  });
  test('a heartbeat without coordinates cannot become a fake location', () {
    final child = Child.fromJson({
      'id': 'sample',
      'name': 'Sample',
      'username': 'sample',
      'device': {
        'id': 'device',
        'status': 'ONLINE',
        'lastLocation': {'batteryLevel': 40}
      }
    });
    expect(child.device?.lastLocation, isNull);
    expect(child.device?.lastSeen, isNull);
  });
  testWidgets(
      'login validation, password visibility and account navigation work',
      (tester) async {
    await pump(tester, const LoginScreen());
    await tester.tap(find.text('Sign in to Seftly'));
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(find.byTooltip('Hide password'), findsOneWidget);
    await tester.ensureVisible(find.text('New here? Create a parent account'));
    await tester.tap(find.text('New here? Create a parent account'));
    await tester.pumpAndSettle();
    expect(find.text('Create an account'), findsOneWidget);
  });
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(800, 1024)
  ]) {
    for (final dark in [false, true]) {
      testWidgets('auth and child cards fit $size, text 2x, dark=$dark',
          (tester) async {
        for (final page in [
          const LoginScreen(),
          const RegisterScreen(),
          const CreateChildScreen()
        ]) {
          await pump(tester, page, size: size, scale: 2, dark: dark);
          expect(tester.takeException(), isNull);
        }
        await pump(
            tester,
            Scaffold(
                body: SingleChildScrollView(
                    child: ChildOverviewCard(
                        child: Child(
                            id: 'sample-child',
                            name: 'A child with a very long display name',
                            username: 'long-child-username-for-layout'),
                        statusCurrent: false))),
            size: size,
            scale: 2,
            dark: dark);
        expect(find.text('Status unverified'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('dashboard empty/error states include recovery and navigation',
      (tester) async {
    mockApi();
    await pump(tester, const DashboardScreen());
    await tester.pumpAndSettle();
    expect(find.text('Start with your first child'), findsOneWidget);
    expect(find.text('Family'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('No unread safety alerts'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    mockApi(fail: true);
    await pump(tester, const DashboardScreen());
    await tester.pumpAndSettle();
    expect(find.text('We couldn’t load your family'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('each child action uses the selected child API and route',
      (tester) async {
    final paths = <String>[];
    mockApi(children: [
      {'id': 'child-a', 'name': 'Ada', 'username': 'ada'},
      {'id': 'child-b', 'name': 'Ben', 'username': 'ben'}
    ], requests: paths);
    await pump(tester, const DashboardScreen());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Ben'), 500,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('child-toggle-child-b')));
    await tester.pumpAndSettle();
    final card = find.byType(ChildOverviewCard);
    final action = find.descendant(of: card, matching: find.text('App rules'));
    await tester.scrollUntilVisible(action,180,scrollable:find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(paths, contains('/api/children/child-b/apps'));
    expect(paths, isNot(contains('/api/children/child-a/apps')));
    await tester.pumpWidget(const SizedBox());
  });
  final pages = <String, Widget>{
    'app policies':
        const AppBlockerScreen(childId: 'sample-child', childName: 'Sample'),
    'web rules':
        const WebFilterScreen(childId: 'sample-child', childName: 'Sample'),
    'browsing filters': const BrowsingHistoryScreen(
        childId: 'sample-child', childName: 'Sample'),
    'safety zones':
        const GeofencesScreen(childId: 'sample-child', childName: 'Sample'),
    'usage report': const AppUsageReportScreen(
        childId: 'sample-child', childName: 'Sample'),
  };
  for (final entry in pages.entries) {
    testWidgets('${entry.key} renders empty data on a small dark screen',
        (tester) async {
      mockApi();
      await pump(tester, entry.value, size: const Size(320, 568), dark: true);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(find.byType(Scaffold), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('status and error semantics remain explicit', (tester) async {
    await pump(
        tester,
        const Scaffold(
            body: SeftlyStateView(
                icon: Icons.cloud_off,
                title: 'Device offline',
                message: 'Reconnect the child device.')));
    expect(find.text('Device offline'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('login branding golden', (tester) async {
    await pump(tester,
        const RepaintBoundary(key: Key('preview'), child: LoginScreen()));
    await expectLater(find.byKey(const Key('preview')),
        matchesGoldenFile('goldens/login.png'));
  });
  testWidgets('family card branding golden', (tester) async {
    await pump(
        tester,
        RepaintBoundary(
            key: const Key('preview'),
            child: Scaffold(
                body: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: ChildOverviewCard(
                        child: Child(
                            id: 'sample-child', name: 'Alex', username: 'alex'),
                        statusCurrent: false)))));
    await expectLater(find.byKey(const Key('preview')),
        matchesGoldenFile('goldens/family-card.png'));
  });
}
