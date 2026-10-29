import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

enum _CameraViewState { waiting, rejected, offline, live, ended, error }

/// Parent-side live camera stream viewer with resilient auto-retry (up to 5 attempts).
/// Flow: POST /api/camera-stream/request -> wait for child's `camera_stream_accept`
/// over socket -> child sends `webrtc_offer` -> parent answers -> ICE exchange ->
/// remote video + audio tracks render here.
class CameraStreamScreen extends StatefulWidget {
  final String childId;
  final String childName;
  final String initialFacing;
  final bool withAudio;

  const CameraStreamScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.initialFacing = 'BACK',
    this.withAudio = true,
  });

  @override
  State<CameraStreamScreen> createState() => _CameraStreamScreenState();
}

class _CameraStreamScreenState extends State<CameraStreamScreen> {
  static const int _maxRetries = 5;

  final SocketService _socketService = SocketService();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  String? _sessionId;
  _CameraViewState _state = _CameraViewState.waiting;
  String? _errorMessage;
  bool _remoteDescriptionSet = false;
  bool _isStreamReady = false;
  bool _isRendererInitialized = false;
  bool _isMuted = false;
  bool _isUserStopped = false;
  bool _isRetrying = false;
  int _retryCount = 0;
  Timer? _connectionWatchdog;
  Timer? _retryTimer;
  late String _currentFacing;
  final List<RTCIceCandidate> _pendingIceCandidates = [];
  MediaStreamTrack? _remoteAudioTrack;

  @override
  void initState() {
    super.initState();
    _currentFacing = widget.initialFacing;
    _initAndStart();
  }

  Future<void> _initAndStart() async {
    try {
      await _remoteRenderer.initialize();
      _isRendererInitialized = true;
    } catch (_) {}

    final token = await ApiService.instance.accessToken;
    if (token == null) {
      if (mounted) {
        setState(() {
          _state = _CameraViewState.error;
          _errorMessage = 'Not authenticated';
        });
      }
      return;
    }

    _socketService.connect(token);
    _socketService.onCameraStreamAccept(_onAccept);
    _socketService.onCameraStreamReject((data) {
      final incomingSid = data['sessionId']?.toString();
      if (_sessionId != null && incomingSid != null && incomingSid != _sessionId) return;
      final reason = data['reason']?.toString();
      if (reason == 'permission_denied') {
        _connectionWatchdog?.cancel();
        if (mounted) {
          setState(() {
            _state = _CameraViewState.rejected;
            _errorMessage = 'Child device denied camera permission.';
          });
        }
      } else {
        _scheduleRetry(
          reason == 'camera_unavailable'
              ? 'Child device camera is busy or unavailable.'
              : 'Child device rejected the camera stream request.',
        );
      }
    });
    _socketService.onCameraStreamStarted((data) {
      final incomingSid = data['sessionId']?.toString();
      if (_sessionId != null && incomingSid != null && incomingSid != _sessionId) return;
      if (mounted && _isStreamReady) setState(() => _state = _CameraViewState.live);
    });
    _socketService.onCameraStreamStopped((data) {
      final incomingSid = data['sessionId']?.toString();
      if (_sessionId != null && incomingSid != null && incomingSid != _sessionId) return;
      if (_isUserStopped) {
        _teardown(notifyBackend: false);
      } else {
        _scheduleRetry('Camera stream interrupted on child device.');
      }
    });
    _socketService.onWebrtcOffer(_onOffer);
    _socketService.onIceCandidate(_onRemoteIceCandidate);

    await _startAttempt();
  }

  Future<void> _startAttempt() async {
    if (!mounted || _isUserStopped) return;

    _connectionWatchdog?.cancel();
    _remoteDescriptionSet = false;
    _isStreamReady = false;
    _pendingIceCandidates.clear();

    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;

    if (mounted) {
      setState(() {
        _state = _CameraViewState.waiting;
        _errorMessage = null;
      });
    }

    await _setupPeerConnection();

    // Start watchdog: if stream doesn't become live within 12 seconds, retry automatically
    _connectionWatchdog = Timer(const Duration(seconds: 12), () {
      if (mounted && _state != _CameraViewState.live && !_isUserStopped) {
        debugPrint('Camera connection watchdog timed out (attempt ${_retryCount + 1})');
        _scheduleRetry('Connection timed out while waiting for camera video.');
      }
    });

    try {
      final res = await ApiService.instance.requestCameraStream(
        widget.childId,
        cameraFacing: _currentFacing,
        withAudio: widget.withAudio,
      );
      _sessionId = res['sessionId'] as String;
      _socketService.joinSession(_sessionId!);
    } catch (e) {
      final isOffline = e.toString().toLowerCase().contains('offline');
      _scheduleRetry(
        e.toString(),
        isOffline: isOffline,
      );
    }
  }

  void _scheduleRetry(String errorReason, {bool isOffline = false}) {
    if (!mounted || _isUserStopped || _isRetrying) return;
    _connectionWatchdog?.cancel();

    if (_retryCount < _maxRetries - 1) {
      _isRetrying = true;
      _retryCount++;
      debugPrint('Retrying camera stream (attempt ${_retryCount + 1} of $_maxRetries)... Reason: $errorReason');

      if (_sessionId != null) {
        final oldSid = _sessionId!;
        _sessionId = null;
        ApiService.instance.stopCameraStream(oldSid).catchError((_) {});
      }

      if (mounted) {
        setState(() {
          _state = _CameraViewState.waiting;
          _errorMessage = null;
        });
      }

      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(milliseconds: 1800), () {
        _isRetrying = false;
        if (mounted && !_isUserStopped) {
          _startAttempt();
        }
      });
    } else {
      // Exhausted all 5 attempts
      _isRetrying = false;
      if (mounted) {
        setState(() {
          _state = isOffline ? _CameraViewState.offline : _CameraViewState.error;
          _errorMessage = errorReason;
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
    final fallbackTurnServers = [
      {
        'urls': [
          'turn:openrelay.metered.ca:80',
          'turn:openrelay.metered.ca:443',
          'turns:openrelay.metered.ca:443',
          'turn:openrelay.metered.ca:80?transport=tcp',
          'turn:openrelay.metered.ca:443?transport=tcp',
        ],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ];
    List<Map<String, dynamic>> iceServers = [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      ...fallbackTurnServers,
    ];
    try {
      final iceServersRaw = await ApiService.instance
          .getIceServers()
          .timeout(const Duration(seconds: 2));
      if (iceServersRaw.isNotEmpty) {
        final fetched = iceServersRaw
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final hasTurn = fetched.any((s) {
          final u = s['urls'];
          if (u is String) return u.startsWith('turn:') || u.startsWith('turns:');
          if (u is List) return u.any((x) => x.toString().startsWith('turn:') || x.toString().startsWith('turns:'));
          return false;
        });
        iceServers = hasTurn ? fetched : [...fetched, ...fallbackTurnServers];
      }
    } catch (_) {}

    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });
    _pc = pc;

    try {
      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
      if (widget.withAudio) {
        await pc.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
      }
    } catch (_) {}

    pc.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'video') {
        if (event.streams.isNotEmpty) {
          final stream = event.streams.first;
          if (_remoteRenderer.srcObject != stream) {
            _remoteRenderer.srcObject = stream;
          }
        } else {
          createLocalMediaStream('remote_camera_stream').then((stream) {
            stream.addTrack(event.track);
            _remoteRenderer.srcObject = stream;
          });
        }
        _connectionWatchdog?.cancel();
        _retryCount = 0; // Reset retry counter on successful live stream!
        if (mounted) {
          setState(() {
            _isStreamReady = true;
            _state = _CameraViewState.live;
          });
        }
      } else if (event.track.kind == 'audio') {
        _remoteAudioTrack = event.track;
        _remoteAudioTrack?.enabled = !_isMuted;
        try {
          Helper.setSpeakerphoneOn(true);
        } catch (_) {}
      }
    };

    pc.onConnectionState = (state) {
      debugPrint('WebRTC Connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _connectionWatchdog?.cancel();
        _retryCount = 0;
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        if (mounted && !_isUserStopped) {
          _scheduleRetry('Camera WebRTC connection lost.');
        }
      }
    };

    pc.onIceConnectionState = (state) {
      debugPrint('WebRTC ICE Connection state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _connectionWatchdog?.cancel();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        if (mounted && !_isUserStopped) {
          _scheduleRetry('Camera ICE negotiation failed.');
        }
      }
    };

    pc.onIceCandidate = (candidate) {
      if (_sessionId == null) return;
      _socketService.sendIceCandidate(_sessionId!, candidate.toMap());
    };
  }

  Future<void> _onOffer(Map<String, dynamic> data) async {
    try {
      final incomingSid = data['sessionId']?.toString();
      if (_sessionId != null && incomingSid != _sessionId) return;
      _sessionId ??= incomingSid;

      if (_pc == null) {
        await _setupPeerConnection();
      }

      final sdpMap = Map<String, dynamic>.from(data['sdp']);
      final offer = RTCSessionDescription(sdpMap['sdp'], sdpMap['type']);
      await _pc!.setRemoteDescription(offer);
      _remoteDescriptionSet = true;

      // Copy and clear list first to prevent ConcurrentModificationError
      final pending = List<RTCIceCandidate>.from(_pendingIceCandidates);
      _pendingIceCandidates.clear();
      for (final candidate in pending) {
        try {
          await _pc?.addCandidate(candidate);
        } catch (_) {}
      }

      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);

      if (_sessionId != null) {
        _socketService.sendWebrtcAnswer(_sessionId!, {
          'sdp': answer.sdp,
          'type': answer.type,
        });
      }
    } catch (e) {
      debugPrint('Error handling camera webrtc_offer: $e');
      _scheduleRetry('Error negotiating video stream.');
    }
  }

  Future<void> _onRemoteIceCandidate(Map<String, dynamic> data) async {
    if (_sessionId != null && data['sessionId'] != _sessionId) return;
    final c = Map<String, dynamic>.from(data['candidate']);
    final iceCandidate = RTCIceCandidate(
      c['candidate']?.toString(),
      c['sdpMid']?.toString(),
      c['sdpMLineIndex'] is int
          ? c['sdpMLineIndex'] as int
          : int.tryParse(c['sdpMLineIndex']?.toString() ?? '0') ?? 0,
    );

    if (_pc != null && _remoteDescriptionSet) {
      try {
        await _pc!.addCandidate(iceCandidate);
      } catch (_) {}
    } else {
      _pendingIceCandidates.add(iceCandidate);
    }
  }

  void _switchCamera() {
    if (_sessionId == null) return;
    final nextFacing = _currentFacing == 'BACK' ? 'FRONT' : 'BACK';
    _socketService.switchCamera(_sessionId!, cameraFacing: nextFacing);
    setState(() {
      _currentFacing = nextFacing;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Switched to $nextFacing camera'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    _remoteAudioTrack?.enabled = !_isMuted;
    if (_remoteRenderer.srcObject != null) {
      for (final track in _remoteRenderer.srcObject!.getAudioTracks()) {
        track.enabled = !_isMuted;
      }
    }
  }

  Future<void> _stopStream() async {
    _isUserStopped = true;
    _connectionWatchdog?.cancel();
    _retryTimer?.cancel();
    if (_sessionId != null) {
      try {
        await ApiService.instance.stopCameraStream(_sessionId!);
      } catch (_) {}
    }
    await _teardown(notifyBackend: false);
  }

  Future<void> _teardown({required bool notifyBackend}) async {
    _connectionWatchdog?.cancel();
    _retryTimer?.cancel();
    if (mounted) {
      setState(() {
        _isStreamReady = false;
        _state = _CameraViewState.ended;
      });
    }
    _remoteDescriptionSet = false;
    _pendingIceCandidates.clear();
    _remoteAudioTrack = null;
    try {
      _remoteRenderer.srcObject = null;
    } catch (_) {}
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
  }

  @override
  void dispose() {
    _isUserStopped = true;
    _connectionWatchdog?.cancel();
    _retryTimer?.cancel();
    _isStreamReady = false;
    _remoteDescriptionSet = false;
    _pendingIceCandidates.clear();
    _remoteAudioTrack = null;
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
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(
        title: Text("${widget.childName}'s Camera"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_state == _CameraViewState.live) ...[
            IconButton(
              icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up),
              tooltip: _isMuted ? 'Unmute' : 'Mute',
              onPressed: _toggleMute,
            ),
            IconButton(
              icon: const Icon(Icons.flip_camera_android),
              tooltip: 'Switch Camera ($_currentFacing)',
              onPressed: _switchCamera,
            ),
          ],
        ],
      ),
      body: Center(child: _buildBody()),
      bottomNavigationBar: _state == _CameraViewState.live
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _switchCamera,
                      icon: const Icon(Icons.flip_camera_android),
                      label: Text('Facing: $_currentFacing'),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: _stopStream,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop Camera'),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _CameraViewState.waiting:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              _retryCount > 0
                  ? 'Reconnecting to child camera (Attempt ${_retryCount + 1} of $_maxRetries)...'
                  : 'Connecting to child camera...',
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              _retryCount > 0
                  ? 'Recovering video stream automatically.'
                  : 'Initializing stream on device.',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        );
      case _CameraViewState.rejected:
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off, size: 64, color: Colors.amber),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? 'Camera stream was rejected.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  _retryCount = 0;
                  _isRetrying = false;
                  _startAttempt();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        );
      case _CameraViewState.offline:
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Child device is currently offline.',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  _retryCount = 0;
                  _isRetrying = false;
                  _startAttempt();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        );
      case _CameraViewState.error:
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? 'Something went wrong.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  _retryCount = 0;
                  _isRetrying = false;
                  _startAttempt();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        );
      case _CameraViewState.ended:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.white60),
            SizedBox(height: 16),
            Text(
              'Camera stream session ended.',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        );
      case _CameraViewState.live:
        if (!_isStreamReady || !_isRendererInitialized || _remoteRenderer.srcObject == null) {
          return const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                'Receiving camera frames...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            RTCVideoView(
              _remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              filterQuality: FilterQuality.medium,
            ),
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(217),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fiber_manual_record, color: Colors.white, size: 12),
                    SizedBox(width: 4),
                    Text(
                      'LIVE CAMERA',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
    }
  }
}
