import 'dart:async';
import '../design/seftly_theme.dart';
import '../design/seftly_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

enum _ViewState { waiting, connecting, rejected, offline, live, ended, error }

/// Parent-side live screen viewer.
/// Flow: POST /api/screen-share/request -> wait for child's `screen_share_accept`
/// over the socket -> child sends `webrtc_offer` -> we answer -> ICE exchange ->
/// remote video track renders here. Either side can stop at any time.
class ScreenShareScreen extends StatefulWidget {
  final String childId;
  final String childName;
  const ScreenShareScreen(
      {super.key, required this.childId, required this.childName});

  @override
  State<ScreenShareScreen> createState() => _ScreenShareScreenState();
}

class _ScreenShareScreenState extends State<ScreenShareScreen> {
  final SocketService _socketService = SocketService();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  String? _sessionId;
  bool _closing = false, _transportConnected = false;
  Timer? _requestTimeout;
  bool _matches(Map<String, dynamic> data) =>
      _sessionId != null && data["sessionId"] == _sessionId;
  _ViewState _state = _ViewState.waiting;
  String? _errorMessage;
  bool _remoteDescriptionSet = false;
  bool _isStreamReady = false;
  bool _isRendererInitialized = false;
  final List<RTCIceCandidate> _pendingIceCandidates = [];

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await _initialize();
    } catch (_) {
      await _teardown(notifyBackend: true);
      if (mounted) {
        setState(() {
          _state = _ViewState.error;
          _errorMessage = 'Unable to initialize sharing. Please try again.';
        });
      }
    }
  }

  Future<void> _initialize() async {
    await _remoteRenderer.initialize();
    _isRendererInitialized = true;
    if (!mounted || _closing) {
      await _remoteRenderer.dispose();
      return;
    }

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

    if (!await ApiService.instance.supportsExplicitMediaConsent()) {
      throw StateError(
          'The backend must be updated before approved check-ins can be requested.');
    }
    if (_closing || !mounted) {
      return;
    }
    final freshToken = await ApiService.instance.accessToken;
    _socketService.connect(freshToken ?? token,
        onAuthError: () => _teardown(notifyBackend: true));
    _socketService.onDisconnect(() => _teardown(notifyBackend: true));
    _socketService.socket.on('operation_error', (_) async {
      await _teardown(notifyBackend: true);
      if (mounted) {
        setState(() {
          _state = _ViewState.error;
          _errorMessage =
              'This session could not be authorized. Please request a new check-in.';
        });
      }
    });
    _socketService.onScreenShareAccept(_onAccept);
    _socketService.onScreenShareReject((data) {
      if (!_matches(data)) {
        return;
      }
      _teardown(notifyBackend: false);
      if (mounted) {
        setState(() => _state = _ViewState.rejected);
      }
    });
    _socketService.onScreenShareStarted((data) {
      if (!_matches(data)) {
        return;
      }
      if (mounted && _isStreamReady && _transportConnected) {
        setState(() => _state = _ViewState.live);
      }
    });
    _socketService.onScreenShareStopped((data) {
      if (_matches(data)) {
        _teardown(notifyBackend: false);
      }
    });
    _socketService.onWebrtcAnswer(_onAnswer);
    _socketService.onIceCandidate(_onRemoteIceCandidate);

    await _setupPeerConnection();
    if (_closing || !mounted) {
      return;
    }

    try {
      final res = await ApiService.instance.requestScreenShare(widget.childId);
      final id = res['sessionId'] as String;
      if (!mounted || _closing) {
        await ApiService.instance.stopScreenShare(id);
        return;
      }
      setState(() => _sessionId = id);
      _requestTimeout = Timer(const Duration(minutes: 2), () async {
        await _teardown(notifyBackend: true);
        if (mounted) {
          setState(() {
            _state = _ViewState.error;
            _errorMessage =
                'The check-in timed out. Ask your child to open Seftly and try again.';
          });
        }
      });
      _socketService.joinSession(_sessionId!);
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = e.toString().contains('offline')
              ? _ViewState.offline
              : _ViewState.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _onAccept(Map<String, dynamic> data) async {
    final incomingSid = data['sessionId']?.toString();
    if (_sessionId == null || incomingSid != _sessionId || _closing) {
      return;
    }
    if (mounted) {
      setState(() => _state = _ViewState.connecting);
    }
    if (_sessionId != null) {
      _socketService.joinSession(_sessionId!);
    }
    if (_pc == null) {
      await _setupPeerConnection();
    }
  }

  Future<void> _setupPeerConnection() async {
    if (_pc != null) {
      return;
    }
    List<Map<String, dynamic>> iceServers = [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ];
    try {
      final iceServersRaw = await ApiService.instance.getIceServers();
      if (iceServersRaw.isNotEmpty) {
        final fetched = iceServersRaw
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        iceServers = fetched;
      }
    } catch (_) {}

    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });
    if (_closing || !mounted) {
      await pc.close();
      return;
    }
    _pc = pc;

    pc.onTrack = (RTCTrackEvent event) {
      if (_closing) {
        return;
      }
      if (event.track.kind == 'video') {
        if (event.streams.isNotEmpty) {
          final stream = event.streams.first;
          if (_remoteRenderer.srcObject != stream) {
            _remoteRenderer.srcObject = stream;
          }
        } else {
          createLocalMediaStream('remote_screen_stream').then((stream) {
            if (_closing || !mounted) {
              stream.dispose();
              return;
            }
            stream.addTrack(event.track);
            _remoteRenderer.srcObject = stream;
          });
        }
        if (mounted) {
          setState(() {
            _isStreamReady = true;
            if (_transportConnected) {
              _state = _ViewState.live;
              _requestTimeout?.cancel();
            }
          });
        }
      }
    };

    pc.onConnectionState = (state) {
      if (_closing) {
        return;
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _transportConnected = true;
        if (mounted && _isStreamReady && _transportConnected) {
          setState(() {
            _state = _ViewState.live;
            _requestTimeout?.cancel();
          });
        }
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _teardown(notifyBackend: true);
      }
    };

    pc.onIceCandidate = (candidate) {
      if (_sessionId == null) {
        return;
      }
      _socketService.sendIceCandidate(_sessionId!, candidate.toMap());
    };

    // The child app initiates the offer once it has captured the screen
    _socketService.socket.on('webrtc_offer', (data) async {
      try {
        final map = Map<String, dynamic>.from(data);
        final incomingSid = map['sessionId']?.toString();
        if (_sessionId == null || incomingSid != _sessionId || _closing) {
          return;
        }

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
      } catch (e) {
        debugPrint('Video negotiation failed.');
      }
    });
  }

  Future<void> _onAnswer(Map<String, dynamic> data) async {
    if (_closing || _pc == null || !_matches(data)) {
      return;
    }
    final sdpMap = Map<String, dynamic>.from(data['sdp']);
    await _pc!.setRemoteDescription(
        RTCSessionDescription(sdpMap['sdp'], sdpMap['type']));
    _remoteDescriptionSet = true;
  }

  Future<void> _onRemoteIceCandidate(Map<String, dynamic> data) async {
    if (!_matches(data) || _closing) {
      return;
    }
    final c = Map<String, dynamic>.from(data['candidate']);
    final iceCandidate = RTCIceCandidate(
      c['candidate']?.toString(),
      c['sdpMid']?.toString(),
      c['sdpMLineIndex'] is int
          ? c['sdpMLineIndex'] as int
          : int.tryParse(c['sdpMLineIndex']?.toString() ?? '0') ?? 0,
    );

    if (_pc != null && _remoteDescriptionSet) {
      await _pc!.addCandidate(iceCandidate);
    } else {
      _pendingIceCandidates.add(iceCandidate);
    }
  }

  Future<void> _stopSharing() => _teardown(notifyBackend: true);

  Future<void> _teardown({required bool notifyBackend}) async {
    if (_closing) {
      return;
    }
    _closing = true;
    _requestTimeout?.cancel();
    final id = _sessionId;
    if (notifyBackend && id != null) {
      if (_socketService.isConnected) {
        _socketService.socket.emit('screen_share_stopped', {'sessionId': id});
      }
      unawaited(ApiService.instance.stopScreenShare(id).catchError((_) {}));
    }
    if (mounted) {
      setState(() {
        _isStreamReady = false;
        _state = _ViewState.ended;
      });
    }
    _remoteDescriptionSet = false;
    _transportConnected = false;
    _pendingIceCandidates.clear();
    final stream = _remoteRenderer.srcObject;
    _remoteRenderer.srcObject = null;
    final pc = _pc;
    _pc = null;
    await pc?.close();
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
    }
  }

  @override
  void dispose() {
    _requestTimeout?.cancel();
    if (!_closing && _sessionId != null) {
      if (_socketService.isConnected) {
        _socketService.socket
            .emit('screen_share_stopped', {'sessionId': _sessionId});
      }
      unawaited(
          ApiService.instance.stopScreenShare(_sessionId!).catchError((_) {}));
    }
    _closing = true;
    _isStreamReady = false;
    _remoteDescriptionSet = false;
    _pendingIceCandidates.clear();
    try {
      _remoteRenderer.srcObject = null;
    } catch (_) {}
    try {
      _remoteRenderer.dispose();
    } catch (_) {}
    try {
      _pc?.close();
    } catch (_) {}
    _pc = null;
    try {
      _socketService.disconnect();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SeftlyScaffold(
      title: 'A shared view',
      subtitle:
          'Android requires fresh screen-sharing consent for each session. You can stop at any time.',
      icon: Icons.screen_share_outlined,
      appBar: AppBar(title: Text("${widget.childName}'s Screen")),
      body: Center(child: _buildBody()),
      floatingActionButton: _sessionId != null && !_closing
          ? FloatingActionButton.extended(
              onPressed: _stopSharing,
              backgroundColor: context.colors.error,
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
            Text('Android screen-sharing permission required'),
            SizedBox(height: 4),
            Text('Android asks what to share for every session.'),
          ],
        );
      case _ViewState.connecting:
        return const Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Approval received. Connecting video…'),
        ]);
      case _ViewState.rejected:
        return const SeftlyStateView(
            icon: Icons.shield_outlined,
            title: 'Request declined',
            message: 'Screen sharing was not approved on the child device.');
      case _ViewState.offline:
        return const SeftlyStateView(
            icon: Icons.cloud_off_outlined,
            title: 'Device offline',
            message: 'Reconnect Seftly Child before requesting a check-in.');
      case _ViewState.error:
        return SeftlyStateView(
            icon: Icons.error_outline_rounded,
            title: 'Check-in unavailable',
            message: _errorMessage ?? 'Please request a new session.',
            error: true);
      case _ViewState.ended:
        return const SeftlyStateView(
            icon: Icons.check_circle_outline,
            title: 'Sharing stopped',
            message: 'The screen-sharing session has ended.');
      case _ViewState.live:
        if (!_isStreamReady ||
            !_isRendererInitialized ||
            _remoteRenderer.srcObject == null) {
          return const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Connecting video stream...'),
            ],
          );
        }
        return AspectRatio(
          aspectRatio: 9 / 16,
          child: RTCVideoView(
            _remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
            filterQuality: FilterQuality.medium,
          ),
        );
    }
  }
}
