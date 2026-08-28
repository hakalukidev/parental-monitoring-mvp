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
  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _pendingIceCandidates = [];

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _remoteRenderer.initialize();

    final token = await ApiService.instance.accessToken;
    if (token == null) {
      if (mounted) {
        setState(() {
          _state = _ViewState.error;
          _errorMessage = 'Not authenticated';
        });
      }
      return;
    }

    _socketService.connect(token);
    _socketService.onScreenShareAccept(_onAccept);
    _socketService.onScreenShareReject((_) {
      if (mounted) setState(() => _state = _ViewState.rejected);
    });
    _socketService.onScreenShareStarted((_) {
      if (mounted) setState(() => _state = _ViewState.live);
    });
    _socketService.onScreenShareStopped((_) => _teardown(notifyBackend: false));
    _socketService.onWebrtcAnswer(_onAnswer);
    _socketService.onIceCandidate(_onRemoteIceCandidate);

    await _setupPeerConnection();

    try {
      final res = await ApiService.instance.requestScreenShare(widget.childId);
      _sessionId = res['sessionId'] as String;
      _socketService.joinSession(_sessionId!);
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = e.toString().contains('offline') ? _ViewState.offline : _ViewState.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _onAccept(Map<String, dynamic> data) async {
    final incomingSid = data['sessionId']?.toString();
    if (_sessionId != null && incomingSid != _sessionId) return;
    _sessionId ??= incomingSid;
    if (_sessionId != null) {
      _socketService.joinSession(_sessionId!);
    }
    if (_pc == null) {
      await _setupPeerConnection();
    }
  }

  Future<void> _setupPeerConnection() async {
    if (_pc != null) return;
    List<Map<String, dynamic>> iceServers = [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ];
    try {
      final iceServersRaw = await ApiService.instance.getIceServers();
      if (iceServersRaw.isNotEmpty) {
        iceServers = iceServersRaw
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}

    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });
    _pc = pc;

    pc.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'video') {
        if (event.streams.isNotEmpty) {
          _remoteRenderer.srcObject = event.streams.first;
        }
        if (mounted) setState(() => _state = _ViewState.live);
      }
    };

    pc.onAddStream = (MediaStream stream) {
      _remoteRenderer.srcObject = stream;
      if (mounted) setState(() => _state = _ViewState.live);
    };

    pc.onIceCandidate = (candidate) {
      if (_sessionId == null) return;
      _socketService.sendIceCandidate(_sessionId!, candidate.toMap());
    };

    // The child app initiates the offer once it has captured the screen
    _socketService.socket.on('webrtc_offer', (data) async {
      try {
        final map = Map<String, dynamic>.from(data);
        final incomingSid = map['sessionId']?.toString();
        if (_sessionId != null && incomingSid != _sessionId) return;
        _sessionId ??= incomingSid;

        if (_pc == null) {
          await _setupPeerConnection();
        }

        final sdpMap = Map<String, dynamic>.from(map['sdp']);
        final offer = RTCSessionDescription(sdpMap['sdp'], sdpMap['type']);
        await _pc!.setRemoteDescription(offer);
        _remoteDescriptionSet = true;

        // Drain queued remote ICE candidates
        for (final candidate in _pendingIceCandidates) {
          await _pc!.addCandidate(candidate);
        }
        _pendingIceCandidates.clear();

        final answer = await _pc!.createAnswer();
        await _pc!.setLocalDescription(answer);

        _socketService.socket.emit('webrtc_answer', {
          'sessionId': _sessionId,
          'sdp': {'sdp': answer.sdp, 'type': answer.type},
        });

        if (mounted) {
          setState(() => _state = _ViewState.live);
        }
      } catch (e) {
        debugPrint('Error handling webrtc_offer: $e');
      }
    });
  }

  Future<void> _onAnswer(Map<String, dynamic> data) async {
    if (_pc == null || (_sessionId != null && data['sessionId'] != _sessionId)) return;
    final sdpMap = Map<String, dynamic>.from(data['sdp']);
    await _pc!.setRemoteDescription(RTCSessionDescription(sdpMap['sdp'], sdpMap['type']));
    _remoteDescriptionSet = true;
  }

  Future<void> _onRemoteIceCandidate(Map<String, dynamic> data) async {
    if (_sessionId != null && data['sessionId'] != _sessionId) return;
    final c = Map<String, dynamic>.from(data['candidate']);
    final iceCandidate = RTCIceCandidate(
      c['candidate']?.toString(),
      c['sdpMid']?.toString(),
      c['sdpMLineIndex'] is int ? c['sdpMLineIndex'] as int : int.tryParse(c['sdpMLineIndex']?.toString() ?? '0') ?? 0,
    );

    if (_pc != null && _remoteDescriptionSet) {
      await _pc!.addCandidate(iceCandidate);
    } else {
      _pendingIceCandidates.add(iceCandidate);
    }
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
    _remoteDescriptionSet = false;
    _pendingIceCandidates.clear();
    await _pc?.close();
    _pc = null;
    if (mounted) setState(() => _state = _ViewState.ended);
  }

  @override
  void dispose() {
    _remoteDescriptionSet = false;
    _pendingIceCandidates.clear();
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
