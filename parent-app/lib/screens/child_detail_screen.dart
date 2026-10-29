import 'dart:async';
import 'package:flutter/material.dart';
import '../models/child.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../theme/app_colors.dart';
import 'app_blocker_screen.dart';
import 'app_usage_report_screen.dart';
import 'browsing_history_screen.dart';
import 'camera_stream_screen.dart';
import 'communication_monitoring_screen.dart';
import 'geofences_screen.dart';
import 'location_tracking_screen.dart';
import 'notification_monitoring_screen.dart';
import 'safety_alerts_screen.dart';
import 'screen_share_screen.dart';
import 'sound_around_screen.dart';
import 'web_filter_screen.dart';

class ChildDetailScreen extends StatefulWidget {
  final Child initialChild;
  final SocketService? socketService;

  const ChildDetailScreen({
    super.key,
    required this.initialChild,
    this.socketService,
  });

  @override
  State<ChildDetailScreen> createState() => _ChildDetailScreenState();
}

class _ChildDetailScreenState extends State<ChildDetailScreen> {
  late Child _child;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _child = widget.initialChild;
    _listenToSocketEvents();
  }

  void _listenToSocketEvents() {
    widget.socketService?.onChildStatusChanged((data) {
      if (!mounted) return;
      final cid = data['childId'] as String?;
      final status = data['status'] as String?;
      final devName = data['deviceName'] as String?;
      if (cid == _child.id && status != null) {
        setState(() {
          final dev = _child.device;
          _child = Child(
            id: _child.id,
            name: _child.name,
            username: _child.username,
            device: ChildDevice(
              id: dev?.id ?? '',
              deviceName: devName ?? dev?.deviceName ?? 'Android Device',
              platform: dev?.platform ?? 'Android',
              status: status.toUpperCase(),
              lastSeen: DateTime.now(),
            ),
          );
        });
      }
    });
  }

  Future<void> _refreshChild() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final raw = await ApiService.instance.listChildren();
      final list = raw.map((e) => Child.fromJson(e as Map<String, dynamic>)).toList();
      final match = list.where((c) => c.id == _child.id);
      if (match.isNotEmpty && mounted) {
        setState(() {
          _child = match.first;
        });
      }
    } catch (_) {
      // Ignore network errors on refresh
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = _child.isOnline;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_child.name),
        actions: [
          IconButton(
            onPressed: _refreshing ? null : _refreshChild,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshChild,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Live Location & Safe Zones (Geofence) (2 Columns)
              Row(
                children: [
                  Expanded(
                    child: _MediumFeatureCard(
                      icon: Icons.location_on_rounded,
                      iconBg: AppColors.iconBgBlue,
                      iconColor: AppColors.iconBlue,
                      title: 'Live Location',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LocationTrackingScreen(
                            childId: _child.id,
                            childName: _child.name,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MediumFeatureCard(
                      icon: Icons.shield_outlined,
                      iconBg: AppColors.iconBgBlue,
                      iconColor: AppColors.iconBlue,
                      title: 'Safe Zones',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => GeofencesScreen(
                            childId: _child.id,
                            childName: _child.name,
                            socketService: widget.socketService,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Live Screen & Live Camera (2 Columns)
              Row(
                children: [
                  Expanded(
                    child: _MediumFeatureCard(
                      icon: Icons.desktop_windows_rounded,
                      iconBg: AppColors.iconBgBlue,
                      iconColor: AppColors.iconBlue,
                      title: 'Live Screen',
                      enabled: online,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ScreenShareScreen(
                            childId: _child.id,
                            childName: _child.name,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MediumFeatureCard(
                      icon: Icons.videocam_rounded,
                      iconBg: AppColors.iconBgBlue,
                      iconColor: AppColors.iconBlue,
                      title: 'Live Camera',
                      enabled: online,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CameraStreamScreen(
                            childId: _child.id,
                            childName: _child.name,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Sound Around Child (Full Width)
              _HorizontalFeatureCard(
                icon: Icons.mic_rounded,
                iconBg: AppColors.iconBgBlue,
                iconColor: AppColors.iconBlue,
                title: 'Sound Around Child',
                enabled: online,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SoundAroundScreen(
                      childId: _child.id,
                      childName: _child.name,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Section: Digital Wellbeing & Safety
              Text(
                'Digital Wellbeing & Safety',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.foreground,
                ),
              ),
              const SizedBox(height: 10),

              // 2x2 Grid: App Usage, App Blocker, Web Filter, Browsing History
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _MiniFeatureCard(
                        icon: Icons.bar_chart_rounded,
                        iconBg: AppColors.iconBgBlue,
                        iconColor: AppColors.iconBlue,
                        title: 'App Usage',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AppUsageReportScreen(
                              childId: _child.id,
                              childName: _child.name,
                              socketService: widget.socketService,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MiniFeatureCard(
                        icon: Icons.shield_outlined,
                        iconBg: AppColors.iconBgBlue,
                        iconColor: AppColors.iconBlue,
                        title: 'App Blocker',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AppBlockerScreen(
                              childId: _child.id,
                              childName: _child.name,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _MiniFeatureCard(
                        icon: Icons.language_rounded,
                        iconBg: AppColors.iconBgBlue,
                        iconColor: AppColors.iconBlue,
                        title: 'Web Filter',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => WebFilterScreen(
                              childId: _child.id,
                              childName: _child.name,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MiniFeatureCard(
                        icon: Icons.history_rounded,
                        iconBg: AppColors.iconBgBlue,
                        iconColor: AppColors.iconBlue,
                        title: 'Browsing History',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => BrowsingHistoryScreen(
                              childId: _child.id,
                              childName: _child.name,
                              socketService: widget.socketService,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Section: Communication & Alerts
              Text(
                'Communication & Alerts',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.foreground,
                ),
              ),
              const SizedBox(height: 10),

              // 2-Column: Calls & Messages + Safety Alerts
              Row(
                children: [
                  Expanded(
                    child: _MediumFeatureCard(
                      icon: Icons.phone_in_talk_rounded,
                      iconBg: AppColors.iconBgBlue,
                      iconColor: AppColors.iconBlue,
                      title: 'Calls & Messages',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CommunicationMonitoringScreen(
                            childId: _child.id,
                            childName: _child.name,
                            socketService: widget.socketService,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MediumFeatureCard(
                      icon: Icons.warning_amber_rounded,
                      iconBg: AppColors.iconBgRed,
                      iconColor: AppColors.iconRed,
                      cardBg: AppColors.cardBgRed,
                      cardBorder: AppColors.cardBorderRed,
                      chevronColor: AppColors.iconRed,
                      title: 'Safety Alerts',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SafetyAlertsScreen(
                            childId: _child.id,
                            childName: _child.name,
                            socketService: widget.socketService,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // App Notifications (Full Width)
              _HorizontalFeatureCard(
                icon: Icons.notifications_none_rounded,
                iconBg: AppColors.iconBgBlue,
                iconColor: AppColors.iconBlue,
                title: 'App Notifications',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NotificationMonitoringScreen(
                      childId: _child.id,
                      childName: _child.name,
                      socketService: widget.socketService,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediumFeatureCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final bool enabled;
  final Color? cardBg;
  final Color? cardBorder;
  final Color? chevronColor;
  final VoidCallback onTap;

  const _MediumFeatureCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    this.enabled = true,
    this.cardBg,
    this.cardBorder,
    this.chevronColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = cardBg ?? Colors.white;
    final border = cardBorder ?? AppColors.primary.withValues(alpha: 0.2);

    return Opacity(
      opacity: enabled ? 1.0 : 0.55,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: iconBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        height: 1.25,
                        color: chevronColor ?? AppColors.foreground,
                      ),
                      maxLines: 2,
                      softWrap: true,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: chevronColor ?? AppColors.mutedForeground.withValues(alpha: 0.6),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HorizontalFeatureCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final bool enabled;
  final VoidCallback onTap;

  const _HorizontalFeatureCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.55,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: iconBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                        color: AppColors.foreground,
                      ),
                      maxLines: 2,
                      softWrap: true,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.mutedForeground.withValues(alpha: 0.6),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniFeatureCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final VoidCallback onTap;

  const _MiniFeatureCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: iconColor, size: 20),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.mutedForeground.withValues(alpha: 0.6),
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    height: 1.25,
                    color: AppColors.foreground,
                  ),
                  maxLines: 2,
                  softWrap: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
