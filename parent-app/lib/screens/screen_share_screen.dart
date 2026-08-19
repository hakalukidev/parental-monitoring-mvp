import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

enum _ViewState { waiting, rejected, offline, live, ended, error }

/// Parent-side live screen viewer.
/// Flow: POST /api/screen-share/request -> wait for child's `screen_share_accept`
/// over the socket -> child sends `webrtc_offer` -> we answer -> ICE exchange ->
/// remote video track renders here. Either side can stop at any time.
class ScreenShareScreen extends StatefulWidget {
  final String childId;
  final String childName;
  const ScreenShareScreen({super.key, required this.childId, required this.childName});

  @override
  State<ScreenShareScreen> createState() => _ScreenShareScreenState();
}

class _ScreenShareScreenState extends State<ScreenShareScreen> {
  final SocketService _socketService = SocketService();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  String? _sessionId;
  _ViewState _state = _ViewState.waiting;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _remoteRenderer.initialize();

    final token = await ApiService.instance.accessToken;
    if (token == null) {
      setState(() {
        _state = _ViewState.error;
        _errorMessage = 'Not authenticated';
      });
      return;
    }

    _socketService.connect(token);
    _socketService.onScreenShareAccept(_onAccept);
    _socketService.onScreenShareReject((_) => setState(() => _state = _ViewState.rejected));
    _socketService.onScreenShareStarted((_) => setState(() => _state = _ViewState.live));
    _socketService.onScreenShareStopped((_) => _teardown(notifyBackend: false));
    _socketService.onWebrtcAnswer(_onAnswer);
    _socketService.onIceCandidate(_onRemoteIceCandidate);

    try {
      final res = await ApiService.instance.requestScreenShare(widget.childId);
      _sessionId = res['sessionId'] as String;
    } catch (e) {
      setState(() {
        _state = e.toString().contains('offline') ? _ViewState.offline : _ViewState.error;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _onAccept(Map<String, dynamic> data) async {
    if (data['sessionId'] != _sessionId) return;
    await _setupPeerConnection();
  }

  Future<void> _setupPeerConnection() async {
    final iceServersRaw = await ApiService.instance.getIceServers();
    final iceServers = iceServersRaw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    _pc = await createPeerConnection({'iceServers': iceServers});

    _pc!.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'video' && event.streams.isNotEmpty) {
        _remoteRenderer.srcObject = event.streams.first;
        setState(() {});
      }
    };

    _pc!.onIceCandidate = (candidate) {
      if (_sessionId == null) return;
      _socketService.sendIceCandidate(_sessionId!, candidate.toMap());
    };

    // The child app initiates the offer once it has captured the screen
    // (see child-app ScreenCaptureService). We just wait for `webrtc_offer`.
    _socketService.socket.on('webrtc_offer', (data) async {
      final map = Map<String, dynamic>.from(data);
      if (map['sessionId'] != _sessionId) return;
      final sdpMap = Map<String, dynamic>.from(map['sdp']);
      final offer = RTCSessionDescription(sdpMap['sdp'], sdpMap['type']);
      await _pc!.setRemoteDescription(offer);

      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);

      _socketService.socket.emit('webrtc_answer', {
        'sessionId': _sessionId,
        'sdp': {'sdp': answer.sdp, 'type': answer.type},
      });
    });
  }

  Future<void> _onAnswer(Map<String, dynamic> data) async {
    // Parent typically answers rather than receives an answer in this flow,
    // but kept for symmetry if you flip offer/answer roles.
    if (_pc == null || data['sessionId'] != _sessionId) return;
    final sdpMap = Map<String, dynamic>.from(data['sdp']);
    await _pc!.setRemoteDescription(RTCSessionDescription(sdpMap['sdp'], sdpMap['type']));
  }

  Future<void> _onRemoteIceCandidate(Map<String, dynamic> data) async {
    if (_pc == null || data['sessionId'] != _sessionId) return;
    final c = Map<String, dynamic>.from(data['candidate']);
    await _pc!.addCandidate(
      RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']),
    );
  }

  Future<void> _stopSharing() async {
    if (_sessionId != null) {
      try {
        await ApiService.instance.stopScreenShare(_sessionId!);
      } catch (_) {
        // socket event below still tears down local state
      }
    }
    await _teardown(notifyBackend: false);
  }

  Future<void> _teardown({required bool notifyBackend}) async {
    await _pc?.close();
    _pc = null;
    if (mounted) setState(() => _state = _ViewState.ended);
  }

  @override
  void dispose() {
    _pc?.close();
    _remoteRenderer.dispose();
    _socketService.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("${widget.childName}'s Screen")),
      body: Center(child: _buildBody()),
      floatingActionButton: _state == _ViewState.live
          ? FloatingActionButton.extended(
              onPressed: _stopSharing,
              backgroundColor: Colors.red,
              icon: const Icon(Icons.stop),
              label: const Text('Stop Sharing'),
            )
          : null,
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _ViewState.waiting:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Waiting for child approval...'),
            SizedBox(height: 4),
            Text('Child has been notified.'),
          ],
        );
      case _ViewState.rejected:
        return const Text('Child rejected the screen-sharing request.');
      case _ViewState.offline:
        return const Text('Child device is offline.');
      case _ViewState.error:
        return Text(_errorMessage ?? 'Something went wrong.');
      case _ViewState.ended:
        return const Text('Screen sharing session ended.');
      case _ViewState.live:
        return AspectRatio(
          aspectRatio: 9 / 16,
          child: RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain),
        );
    }
  }
}
