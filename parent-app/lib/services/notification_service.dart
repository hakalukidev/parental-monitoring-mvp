import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:latlong2/latlong.dart';
import '../screens/location_tracking_screen.dart';

/// Central Notification Service managing OS-level Heads-Up Notifications
/// and Deep-Linking into History Trail Mode upon notification click.
class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  GlobalKey<NavigatorState>? _navigatorKey;
  bool _isInitialized = false;

  // Track notified event IDs in memory to avoid duplicate alerts in the same session
  final Set<String> _notifiedEventIds = {};

  Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    if (_isInitialized) return;
    _navigatorKey = navigatorKey;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    await _createNotificationChannels();
    await requestPermissions();
    _isInitialized = true;
  }

  Future<void> requestPermissions() async {
    final androidImpl = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.requestNotificationsPermission();
    }
  }

  Future<void> _createNotificationChannels() async {
    const androidChannel = AndroidNotificationChannel(
      'geofence_alerts_channel',
      'Safety Boundary Alerts',
      description: 'Instant alerts when child enters or leaves boundaries',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      showBadge: true,
    );

    final androidImpl = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(androidChannel);
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    final payloadString = response.payload;
    if (payloadString == null || payloadString.isEmpty) return;

    try {
      final data = jsonDecode(payloadString) as Map<String, dynamic>;
      final type = data['type'] as String?;

      if (type == 'GEOFENCE_ALERT') {
        final childId = data['childId'] as String?;
        final childName = data['childName'] as String? ?? 'Child';
        final lat = (data['latitude'] as num?)?.toDouble();
        final lon = (data['longitude'] as num?)?.toDouble();
        final tsStr = data['timestamp'] as String?;
        final geofenceId = data['geofenceId'] as String?;

        if (childId != null) {
          final timestamp = tsStr != null ? DateTime.tryParse(tsStr) : null;
          final focusLocation = (lat != null && lon != null) ? LatLng(lat, lon) : null;

          _navigatorKey?.currentState?.push(
            MaterialPageRoute(
              builder: (_) => LocationTrackingScreen(
                childId: childId,
                childName: childName,
                initialTrackingMode: MapTrackingMode.historyTrail,
                focusTimestamp: timestamp,
                focusLocation: focusLocation,
                highlightGeofenceId: geofenceId,
                breachType: data['eventType'] as String?,
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error routing notification tap: $e');
    }
  }

  Future<void> showGeofenceAlertNotification({
    required String eventId,
    required String childId,
    required String childName,
    required String geofenceId,
    required String geofenceName,
    required String eventType, // EXIT | ENTRY
    required String zoneType,  // SAFE_ZONE | RESTRICTED_ZONE
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    String? title,
    String? body,
  }) async {
    // Avoid re-alerting if this exact event has already been displayed
    if (_notifiedEventIds.contains(eventId)) return;
    _notifiedEventIds.add(eventId);

    final isExit = eventType == 'EXIT';
    final isSafeZone = zoneType == 'SAFE_ZONE';

    final notifTitle = title ??
        (isSafeZone
            ? (isExit ? '🚨 Safe Zone Left: $geofenceName' : '✅ Safe Zone Reached: $geofenceName')
            : (isExit ? '🛡️ Restricted Area Exited: $geofenceName' : '⚠️ Restricted Area Entered: $geofenceName'));

    final actionText = isExit ? 'left' : 'entered';
    final notifBody = body ?? '$childName $actionText $geofenceName. Tap to view route trail.';

    final payload = jsonEncode({
      'type': 'GEOFENCE_ALERT',
      'eventId': eventId,
      'childId': childId,
      'childName': childName,
      'geofenceId': geofenceId,
      'geofenceName': geofenceName,
      'eventType': eventType,
      'zoneType': zoneType,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
    });

    final notificationId = (eventId.isNotEmpty ? eventId.hashCode : timestamp.millisecondsSinceEpoch) & 0x7FFFFFFF;

    const androidDetails = AndroidNotificationDetails(
      'geofence_alerts_channel',
      'Safety Boundary Alerts',
      channelDescription: 'Instant alerts when child enters or leaves boundaries',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'Safety Boundary Alert',
      icon: '@mipmap/ic_launcher',
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(''),
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true, presentBadge: true),
    );

    await _notificationsPlugin.show(
      notificationId,
      notifTitle,
      notifBody,
      notificationDetails,
      payload: payload,
    );
  }
}
