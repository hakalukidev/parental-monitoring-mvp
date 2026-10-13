import 'dart:async';
import '../design/seftly_theme.dart';
import '../design/seftly_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

enum _CameraViewState {
  waiting,
  connecting,
  rejected,
  offline,
  live,
  ended,
  error
}

/// Parent-side live camera stream viewer.
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
    this.withAudio = false,
  });

  @override
  State<CameraStreamScreen> createState() => _CameraStreamScreenState();
}

class _CameraStreamScreenState extends State<CameraStreamScreen> {
  final SocketService _socketService = SocketService();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  String? _sessionId;
  bool _closing = false, _transportConnected = false;
  Timer? _requestTimeout;
  bool _matches(Map<String, dynamic> data) =>
      _sessionId != null && data["sessionId"] == _sessionId;
  _CameraViewState _state = _CameraViewState.waiting;
  String? _errorMessage;
  bool _remoteDescriptionSet = false;
  bool _isStreamReady = false;
  bool _isRendererInitialized = false;
  bool _isMuted = false;
  late bool _requestedAudio;
  late String _currentFacing;
  final List<RTCIceCandidate> _pendingIceCandidates = [];

  @override
  void initState() {
    super.initState();
    _currentFacing = widget.initialFacing;
    _requestedAudio = widget.withAudio;
    _start();
  }

  Future<void> _start() async {
    try {
      await _initialize();
    } catch (_) {
      await _teardown(notifyBackend: true);
      if (mounted) {
        setState(() {
          _state = _CameraViewState.error;
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
          _state = _CameraViewState.error;
          _errorMessage = 'Not authenticated';
        });
      }
      return;
    }

    if (!await ApiService.instance.supportsExplicitMediaConsent()) {
      throw StateError(
          'The backend must be updated before approved check-ins can be requested.');
    }
    if (!mounted || _closing) {
      return;
    }
    final proceed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => SafeArea(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Camera check-in',
                              style: Theme.of(ctx).textTheme.titleLarge),
                          const SizedBox(height: 12),
                          const Text(
                              'Choose what to request. The child device will ask for approval before anything is shared.'),
                          const SizedBox(height: 20),
                          DropdownButtonFormField<String>(
                              initialValue: _currentFacing,
                              decoration: const InputDecoration(
                                  labelText: 'Requested camera'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'BACK', child: Text('Back camera')),
                                DropdownMenuItem(
                                    value: 'FRONT', child: Text('Front camera'))
                              ],
                              onChanged: (value) => update(
                                  () => _currentFacing = value ?? 'BACK')),
                          SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Include microphone audio'),
                              value: _requestedAudio,
                              onChanged: (value) =>
                                  update(() => _requestedAudio = value)),
                          const SizedBox(height: 16),
                          FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Send check-in request')),
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel')),
                        ])))));
    if (proceed != true || !mounted) {
      await _teardown(notifyBackend: false);
      return;
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
          _state = _CameraViewState.error;
          _errorMessage =
              'This session could not be authorized. Please request a new check-in.';
        });
      }
    });
    _socketService.onCameraStreamAccept(_onAccept);
    _socketService.onCameraStreamReject((data) {
      if (!_matches(data)) {
        return;
      }
      _teardown(notifyBackend: false);
      final reason = data['reason']?.toString();
      if (mounted) {
        setState(() {
          _state = _CameraViewState.rejected;
          _errorMessage = reason == 'permission_denied'
              ? 'Child device denied camera permission.'
              : reason == 'camera_unavailable'
                  ? 'Child device camera is unavailable or in use by another app.'
                  : 'Child device rejected the camera stream request.';
        });
      }
    });
    _socketService.onCameraStreamStarted((data) {
      if (!_matches(data)) {
        return;
      }
      if (mounted && _isStreamReady && _transportConnected) {
        setState(() => _state = _CameraViewState.live);
      }
    });
    _socketService.onCameraStreamStopped((data) {
      if (_matches(data)) {
        _teardown(notifyBackend: false);
      }
    });
    _socketService.onWebrtcOffer(_onOffer);
    _socketService.onIceCandidate(_onRemoteIceCandidate);

    await _setupPeerConnection();
    if (_closing || !mounted) {
      return;
    }

    try {
      final res = await ApiService.instance.requestCameraStream(
        widget.childId,
        cameraFacing: _currentFacing,
        withAudio: _requestedAudio,
      );
      final id = res['sessionId'] as String;
      if (!mounted || _closing) {
        await ApiService.instance.stopCameraStream(id);
        return;
      }
      setState(() => _sessionId = id);
      _requestTimeout = Timer(const Duration(minutes: 2), () async {
        await _teardown(notifyBackend: true);
        if (mounted) {
          setState(() {
            _state = _CameraViewState.error;
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
              ? _CameraViewState.offline
              : _CameraViewState.error;
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
      setState(() => _state = _CameraViewState.connecting);
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
          createLocalMediaStream('remote_camera_stream').then((stream) {
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
              _state = _CameraViewState.live;
              _requestTimeout?.cancel();
            }
          });
        }
      } else if (event.track.kind == 'audio') {
        if (_remoteRenderer.srcObject != null) {
          _remoteRenderer.srcObject!.addTrack(event.track);
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
            _state = _CameraViewState.live;
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
  }

  Future<void> _onOffer(Map<String, dynamic> data) async {
    try {
      final incomingSid = data['sessionId']?.toString();
      if (_closing || _sessionId == null || incomingSid != _sessionId) {
        return;
      }

      if (_pc == null) {
        await _setupPeerConnection();
      }

      final sdpMap = Map<String, dynamic>.from(data['sdp']);
      final offer = RTCSessionDescription(sdpMap['sdp'], sdpMap['type']);
      await _pc!.setRemoteDescription(offer);
      _remoteDescriptionSet = true;

      for (final candidate in _pendingIceCandidates) {
        await _pc!.addCandidate(candidate);
      }
      _pendingIceCandidates.clear();

      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);

      if (_sessionId != null) {
        _socketService.sendWebrtcAnswer(_sessionId!, {
          'sdp': answer.sdp,
          'type': answer.type,
        });
      }
    } catch (e) {
      debugPrint('Video negotiation failed.');
    }
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

  void _switchCamera() {
    if (_sessionId == null) {
      return;
    }
    final nextFacing = _currentFacing == 'BACK' ? 'FRONT' : 'BACK';
    _socketService.switchCamera(_sessionId!, cameraFacing: nextFacing);
    setState(() {
      _currentFacing = nextFacing;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Requested $nextFacing camera'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    if (_remoteRenderer.srcObject != null) {
      for (final track in _remoteRenderer.srcObject!.getAudioTracks()) {
        track.enabled = !_isMuted;
      }
    }
  }

  Future<void> _stopStream() => _teardown(notifyBackend: true);

  Future<void> _teardown({required bool notifyBackend}) async {
    if (_closing) {
      return;
    }
    _closing = true;
    _requestTimeout?.cancel();
    final id = _sessionId;
    if (notifyBackend && id != null) {
      if (_socketService.isConnected) {
        _socketService.socket.emit('camera_stream_stopped', {'sessionId': id});
      }
      unawaited(ApiService.instance.stopCameraStream(id).catchError((_) {}));
    }
    if (mounted) {
      setState(() {
        _isStreamReady = false;
        _state = _CameraViewState.ended;
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
            .emit('camera_stream_stopped', {'sessionId': _sessionId});
      }
      unawaited(
          ApiService.instance.stopCameraStream(_sessionId!).catchError((_) {}));
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
      title: 'Check in together',
      subtitle:
          'The child device must approve each camera and microphone session.',
      icon: Icons.videocam_outlined,
      backgroundColor: context.colors.surface,
      appBar: AppBar(
        title: Text("${widget.childName}'s Camera"),
        backgroundColor: context.colors.surface,
        foregroundColor: context.colors.onSurface,
        actions: [
          if (_sessionId != null && !_closing)
            IconButton(
              tooltip: 'Stop Camera',
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: _stopStream,
            ),
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
      bottomNavigationBar: _sessionId != null && !_closing
          ? SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _state == _CameraViewState.live
                          ? _switchCamera
                          : null,
                      icon: const Icon(Icons.flip_camera_android),
                      label: Text('Requested lens: $_currentFacing'),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: context.colors.error),
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
        return const Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Waiting for approval on the child device'),
          SizedBox(height: 4),
          Text('Camera and microphone stay off until approved.'),
        ]);
      case _CameraViewState.connecting:
        return const Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Approval received. Connecting video…'),
        ]);
      case _CameraViewState.rejected:
        return SeftlyStateView(
            icon: Icons.videocam_off_outlined,
            title: 'Request declined',
            message: _errorMessage ??
                'Camera sharing was not approved on the child device.');
      case _CameraViewState.offline:
        return const SeftlyStateView(
            icon: Icons.cloud_off_outlined,
            title: 'Device offline',
            message: 'Reconnect Seftly Child before requesting a check-in.');
      case _CameraViewState.error:
        return SeftlyStateView(
            icon: Icons.error_outline_rounded,
            title: 'Check-in unavailable',
            message: _errorMessage ?? 'Please request a new session.',
            error: true);
      case _CameraViewState.ended:
        return const SeftlyStateView(
            icon: Icons.check_circle_outline,
            title: 'Camera stopped',
            message: 'The camera-sharing session has ended.');
      case _CameraViewState.live:
        if (!_isStreamReady ||
            !_isRendererInitialized ||
            _remoteRenderer.srcObject == null) {
          return const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Receiving camera frames...'),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: context.colors.error.withAlpha(217),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fiber_manual_record,
                        color: Colors.white, size: 12),
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
