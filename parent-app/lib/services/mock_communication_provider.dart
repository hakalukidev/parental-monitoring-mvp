import '../models/child_call_entry.dart';
import '../models/child_sms_entry.dart';
import '../models/communication_capability.dart';
import '../models/safety_alert_entry.dart';

class MockCommunicationProvider {
  static CommunicationCapability getMockCapabilities() {
    return const CommunicationCapability(
      callsStatus: CapabilityStatus.available,
      smsMetadataStatus: CapabilityStatus.available,
      smsContentStatus: CapabilityStatus.available,
    );
  }

  static List<ChildCallEntry> getMockCalls() {
    final now = DateTime.now();
    return [
      ChildCallEntry(
        id: 'mock_call_1',
        phoneNumber: '+8801700-000001',
        contactName: 'Mom',
        direction: CallDirection.incoming,
        durationSeconds: 145, // 2m 25s
        timestamp: now.subtract(const Duration(minutes: 25)),
      ),
      ChildCallEntry(
        id: 'mock_call_2',
        phoneNumber: '+8801800-000002',
        contactName: 'School Bus Driver',
        direction: CallDirection.outgoing,
        durationSeconds: 42,
        timestamp: now.subtract(const Duration(hours: 2, minutes: 10)),
      ),
      ChildCallEntry(
        id: 'mock_call_3',
        phoneNumber: '+8801900-000003',
        contactName: null,
        direction: CallDirection.missed,
        durationSeconds: 0,
        timestamp: now.subtract(const Duration(hours: 5, minutes: 40)),
      ),
      ChildCallEntry(
        id: 'mock_call_4',
        phoneNumber: '+8801600-000004',
        contactName: 'Unknown Caller',
        direction: CallDirection.rejected,
        durationSeconds: 0,
        timestamp: now.subtract(const Duration(days: 1, hours: 3)),
      ),
      ChildCallEntry(
        id: 'mock_call_5',
        phoneNumber: '+8801700-000001',
        contactName: 'Mom',
        direction: CallDirection.outgoing,
        durationSeconds: 320, // 5m 20s
        timestamp: now.subtract(const Duration(days: 1, hours: 6)),
      ),
    ];
  }

  static List<ChildSmsEntry> getMockSms() {
    final now = DateTime.now();
    return [
      ChildSmsEntry(
        id: 'mock_sms_1',
        phoneNumber: '+8801700-000001',
        contactName: 'Mom',
        direction: SmsDirection.incoming,
        body: 'Have you finished your homework? Call me when you get home.',
        hasBody: true,
        timestamp: now.subtract(const Duration(minutes: 18)),
      ),
      ChildSmsEntry(
        id: 'mock_sms_2',
        phoneNumber: '+8801700-000001',
        contactName: 'Mom',
        direction: SmsDirection.outgoing,
        body: "Yes, I am heading to the library with Alex now.",
        hasBody: true,
        timestamp: now.subtract(const Duration(minutes: 15)),
      ),
      ChildSmsEntry(
        id: 'mock_sms_3',
        phoneNumber: '+8801500-000005',
        contactName: 'School Notification',
        direction: SmsDirection.incoming,
        body: 'Notice: Parent-Teacher meeting is scheduled for this Thursday.',
        hasBody: true,
        timestamp: now.subtract(const Duration(hours: 4, minutes: 30)),
      ),
      ChildSmsEntry(
        id: 'mock_sms_4',
        phoneNumber: '+8801999-000009',
        contactName: null,
        direction: SmsDirection.incoming,
        body: null,
        hasBody: false,
        timestamp: now.subtract(const Duration(days: 2)),
      ),
    ];
  }

  static List<SafetyAlertEntry> getMockSafetyAlerts() {
    final now = DateTime.now();
    return [
      SafetyAlertEntry(
        id: 'mock_alert_1',
        alertType: 'EXPLICIT_SCREEN_CONTENT',
        packageName: 'com.android.chrome',
        appName: 'Chrome Browser',
        confidenceScore: 0.94,
        severity: SafetySeverity.critical,
        isAcknowledged: false,
        timestamp: now.subtract(const Duration(minutes: 12)),
      ),
      SafetyAlertEntry(
        id: 'mock_alert_2',
        alertType: 'EXPLICIT_PHOTO_SAVED',
        packageName: 'com.sec.android.gallery3d',
        appName: 'Samsung Gallery',
        confidenceScore: 0.86,
        severity: SafetySeverity.high,
        isAcknowledged: false,
        timestamp: now.subtract(const Duration(hours: 1, minutes: 45)),
      ),
      SafetyAlertEntry(
        id: 'mock_alert_3',
        alertType: 'ADULT_CONTENT_DETECTED',
        packageName: 'com.google.android.youtube',
        appName: 'YouTube',
        confidenceScore: 0.76,
        severity: SafetySeverity.medium,
        isAcknowledged: true,
        acknowledgedAt: now.subtract(const Duration(hours: 3)),
        timestamp: now.subtract(const Duration(hours: 3, minutes: 15)),
      ),
      SafetyAlertEntry(
        id: 'mock_alert_4',
        alertType: 'EXPLICIT_SCREEN_CONTENT',
        packageName: 'com.instagram.android',
        appName: 'Instagram',
        confidenceScore: 0.91,
        severity: SafetySeverity.critical,
        isAcknowledged: true,
        acknowledgedAt: now.subtract(const Duration(days: 1)),
        timestamp: now.subtract(const Duration(days: 1, hours: 2)),
      ),
    ];
  }
}

