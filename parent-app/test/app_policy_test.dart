import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/models/app_policy.dart';

void main() {
  group('AppPolicy and WebBlockRule Models Test', () {
    test('InstalledAppInfo JSON serialization and deserialization', () {
      final json = {
        'packageName': 'com.roblox.client',
        'appName': 'Roblox',
        'category': 'GAME',
        'status': 'TIME_LIMITED',
        'dailyLimitMinutes': 45,
        'schedules': [
          {
            'daysOfWeek': [1, 2, 3, 4, 5],
            'startTime': '18:00',
            'endTime': '20:00',
          }
        ],
        'isSystemWhitelisted': false,
      };

      final app = InstalledAppInfo.fromJson(json);
      expect(app.packageName, 'com.roblox.client');
      expect(app.appName, 'Roblox');
      expect(app.category, 'GAME');
      expect(app.status, 'TIME_LIMITED');
      expect(app.dailyLimitMinutes, 45);
      expect(app.schedules.length, 1);
      expect(app.schedules.first.startTime, '18:00');
      expect(app.schedules.first.endTime, '20:00');

      final policyJson = app.toPolicyJson();
      expect(policyJson['status'], 'TIME_LIMITED');
      expect(policyJson['dailyLimitMinutes'], 45);
    });

    test('WebBlockRule JSON parsing', () {
      final json = {
        '_id': 'rule_123',
        'ruleType': 'DOMAIN',
        'target': 'gambling-site.com',
        'action': 'BLOCK',
        'isEnabled': true,
      };

      final rule = WebBlockRule.fromJson(json);
      expect(rule.id, 'rule_123');
      expect(rule.ruleType, 'DOMAIN');
      expect(rule.target, 'gambling-site.com');
      expect(rule.action, 'BLOCK');
      expect(rule.isEnabled, true);
    });

    test('BrowsingHistoryRecord and Analytics parsing', () {
      final historyJson = {
        '_id': 'rec_456',
        'url': 'https://kids.nationalgeographic.com',
        'domain': 'kids.nationalgeographic.com',
        'title': 'National Geographic Kids',
        'browser': 'CHROME',
        'isIncognito': false,
        'category': 'EDUCATION',
        'isBlockedAttempt': false,
        'visitedAt': '2026-09-11T12:00:00.000Z',
      };

      final record = BrowsingHistoryRecord.fromJson(historyJson);
      expect(record.domain, 'kids.nationalgeographic.com');
      expect(record.browser, 'CHROME');
      expect(record.category, 'EDUCATION');
      expect(record.isBlockedAttempt, false);

      final analyticsJson = {
        'totalVisited': 48,
        'blockedAttempts': 3,
        'topDomains': [
          {'domain': 'youtube.com', 'count': 20, 'percentage': 42},
          {'domain': 'roblox.com', 'count': 10, 'percentage': 21},
        ],
        'categoryDistribution': {
          'EDUCATION': 15,
          'GAMING': 10,
        },
      };

      final analytics = BrowsingAnalytics.fromJson(analyticsJson);
      expect(analytics.totalVisited, 48);
      expect(analytics.blockedAttempts, 3);
      expect(analytics.topDomains.length, 2);
      expect(analytics.topDomains.first.domain, 'youtube.com');
    });

    test('UnblockRequest parsing', () {
      final reqJson = {
        'requestId': 'req_789',
        'childId': 'child_1',
        'childName': 'Alex',
        'packageName': 'com.roblox.client',
        'appName': 'Roblox',
        'reason': 'Need 15 min for homework',
        'requestedAt': '2026-09-11T14:30:00.000Z',
      };

      final req = UnblockRequest.fromJson(reqJson);
      expect(req.childName, 'Alex');
      expect(req.appName, 'Roblox');
      expect(req.reason, 'Need 15 min for homework');
    });
  });
}
