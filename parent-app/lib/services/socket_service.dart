import 'package:socket_io_client/socket_io_client.dart' as io;
import 'app_config.dart';

/// Wraps the Socket.IO connection used for presence + WebRTC signaling.
class SocketService {
  io.Socket? _socket;

  void connect(String accessToken, {void Function()? onAuthError}) {
    _socket = io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': accessToken})
          .disableAutoConnect()
          .build(),
    );
    _socket!.onConnectError((err) {
      if (err.toString().toLowerCase().contains('unauthorized') ||
          err.toString().toLowerCase().contains('token')) {
        onAuthError?.call();
      }
    });
    _socket!.connect();
  }

  void updateTokenAndReconnect(String newToken, {void Function()? onAuthError}) {
    disconnect();
    connect(newToken, onAuthError: onAuthError);
  }

  io.Socket get socket {
    if (_socket == null) throw StateError('Socket not connected. Call connect() first.');
    return _socket!;
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }

  void onChildStatusChanged(void Function(Map<String, dynamic>) cb) {
    socket.on('child_status_changed', (data) => cb(Map<String, dynamic>.from(data)));
  }

  void onChildLocationUpdate(void Function(Map<String, dynamic>) cb) {
    socket.on('child_location_update', (data) => cb(Map<String, dynamic>.from(data)));
  }

  void off(String event) {
    _socket?.off(event);
  }

  void onScreenShareAccept(void Function(Map<String, dynamic>) cb) {
    socket.on('screen_share_accept', (data) => cb(Map<String, dynamic>.from(data)));
  }

  void onScreenShareReject(void Function(Map<String, dynamic>) cb) {
    socket.on('screen_share_reject', (data) => cb(Map<String, dynamic>.from(data)));
  }

  void onScreenShareStarted(void Function(Map<String, dynamic>) cb) {
    socket.on('screen_share_started', (data) => cb(Map<String, dynamic>.from(data)));
  }

  void onScreenShareStopped(void Function(Map<String, dynamic>) cb) {
    socket.on('screen_share_stopped', (data) => cb(Map<String, dynamic>.from(data)));
  }

  void onCameraStreamAccept(void Function(Map<String, dynamic>) cb) {
    socket.on('camera_stream_accept', (data) => cb(Map<String, dynamic>.from(data)));
  }

  void onCameraStreamReject(void Function(Map<String, dynamic>) cb) {
    socket.on('camera_stream_reject', (data) => cb(Map<String, dynamic>.from(data)));
  }

  void onCameraStreamStarted(void Function(Map<String, dynamic>) cb) {
    socket.on('camera_stream_started', (data) => cb(Map<String, dynamic>.from(data)));
  }

  void onCameraStreamStopped(void Function(Map<String, dynamic>) cb) {
    socket.on('camera_stream_stopped', (data) => cb(Map<String, dynamic>.from(data)));
  }

  void switchCamera(String sessionId, {String? cameraFacing}) {
    socket.emit('camera_stream_switch_camera', {
      'sessionId': sessionId,
      if (cameraFacing != null) 'cameraFacing': cameraFacing,
    });
  }

  void onWebrtcAnswer(void Function(Map<String, dynamic>) cb) {
    socket.on('webrtc_answer', (data) => cb(Map<String, dynamic>.from(data)));
  }

  void onIceCandidate(void Function(Map<String, dynamic>) cb) {
    socket.on('ice_candidate', (data) => cb(Map<String, dynamic>.from(data)));
  }

  void sendIceCandidate(String sessionId, Map<String, dynamic> candidate) {
    socket.emit('ice_candidate', {'sessionId': sessionId, 'candidate': candidate});
  }

  void joinSession(String sessionId) {
    socket.emit('join_session', {'sessionId': sessionId});
  }

  // ==========================================
  // App Blocker & Unblock Requests
  // ==========================================

  void onUnblockRequest(void Function(Map<String, dynamic>) cb) {
    socket.on('unblock_request', (data) => cb(Map<String, dynamic>.from(data)));
  }

  void sendUnblockResponse({
    required String requestId,
    required String childId,
    required String packageName,
    required bool approved,
    int temporaryDurationMinutes = 15,
  }) {
    socket.emit('unblock_response', {
      'requestId': requestId,
      'childId': childId,
      'packageName': packageName,
      'approved': approved,
      'temporaryDurationMinutes': temporaryDurationMinutes,
    });
  }

  void toggleInstantLockdown({
    required String childId,
    required bool isPaused,
  }) {
    socket.emit('instant_lockdown_toggle', {
      'childId': childId,
      'isPaused': isPaused,
    });
  }

  // ==========================================
  // Browsing History & Alerts
  // ==========================================

  void onNewBrowsingActivity(void Function(Map<String, dynamic>) cb) {
    socket.on('new_browsing_activity', (data) => cb(Map<String, dynamic>.from(data)));
  }

  void onSuspiciousWebAlert(void Function(Map<String, dynamic>) cb) {
    socket.on('suspicious_web_alert', (data) => cb(Map<String, dynamic>.from(data)));
  }
}
