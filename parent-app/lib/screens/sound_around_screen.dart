import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

enum _AudioViewState { connecting, waitingForChild, live, ended, error }

/// Dedicated Sound Around Child (Live Ambient Audio Monitor).
/// Connects to child device's microphone via WebRTC without opening camera.
class SoundAroundScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const SoundAroundScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<SoundAroundScreen> createState() => _SoundAroundScreenState();
}

class _SoundAroundScreenState extends State<SoundAroundScreen>
    with SingleTickerProviderStateMixin {
  static const int _maxRetries = 5;

  final SocketService _socketService = SocketService();
  final RTCVideoRenderer _audioRenderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  String? _sessionId;
  _AudioViewState _state = _AudioViewState.connecting;
  String? _errorMessage;
  bool _remoteDescriptionSet = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isUserStopped = false;
  bool _isRetrying = false;
  int _retryCount = 0;
  Timer? _connectionWatchdog;
  Timer? _retryTimer;
  MediaStreamTrack? _remoteAudioTrack;
  final List<RTCIceCandidate> _pendingIceCandidates = [];

  // Stopwatch / Duration timer
  Timer? _durationTimer;
  int _secondsElapsed = 0;

  // Animation for pulsing audio waves
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _initAndStart();
  }

  Future<void> _initAndStart() async {
    try {
      await _audioRenderer.initialize();
    } catch (e) {
      debugPrint('Renderer init error: $e');
    }

    final token = await ApiService.instance.accessToken;
    if (token == null) {
      if (mounted) {
        setState(() {
          _state = _AudioViewState.error;
          _errorMessage = 'Authentication expired. Please log in again.';
        });
      }
      return;
    }

    _socketService.connect(token);
    _socketService.onAudioStreamAccept(_onAccept);
    _socketService.onAudioStreamReject((data) {
      final incomingSid = data['sessionId']?.toString();
      if (_sessionId != null && incomingSid != null && incomingSid != _sessionId) return;
      final reason = data['reason']?.toString();
      if (reason == 'permission_denied') {
        _connectionWatchdog?.cancel();
        if (mounted) {
          setState(() {
            _state = _AudioViewState.error;
            _errorMessage = 'Child device denied microphone permission.';
          });
        }
      } else {
        _scheduleRetry(
          reason == 'microphone_unavailable'
              ? 'Child device microphone is currently in use or unavailable.'
              : 'Child device declined the ambient audio stream.',
        );
      }
    });

    _socketService.onAudioStreamStarted((data) {
      final incomingSid = data['sessionId']?.toString();
      if (_sessionId != null && incomingSid != null && incomingSid != _sessionId) return;
      _connectionWatchdog?.cancel();
      _retryCount = 0;
      if (mounted) {
        setState(() {
          _state = _AudioViewState.live;
        });
        _startTimer();
      }
    });

    _socketService.onAudioStreamStopped((data) {
      final incomingSid = data['sessionId']?.toString();
      if (_sessionId != null && incomingSid != null && incomingSid != _sessionId) return;
      if (_isUserStopped) {
        _teardown(notifyBackend: false);
      } else {
        _scheduleRetry('Ambient audio stream interrupted on child device.');
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
    _pendingIceCandidates.clear();

    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;

    if (mounted) {
      setState(() {
        _state = _AudioViewState.connecting;
        _errorMessage = null;
      });
    }

    await _setupPeerConnection();

    // Start 12-second watchdog timer for audio connection
    _connectionWatchdog = Timer(const Duration(seconds: 12), () {
      if (mounted && _state != _AudioViewState.live && !_isUserStopped) {
        debugPrint('Audio connection watchdog timed out (attempt ${_retryCount + 1})');
        _scheduleRetry('Connection timed out while waiting for child microphone.');
      }
    });

    try {
      final res = await ApiService.instance.requestAudioStream(widget.childId);
      _sessionId = res['sessionId'] as String;
      _socketService.joinSession(_sessionId!);
      if (mounted && _state != _AudioViewState.live) {
        setState(() {
          _state = _AudioViewState.waitingForChild;
        });
      }
    } catch (e) {
      final msg = e.toString().contains('offline')
          ? '${widget.childName}\'s device is currently offline.'
          : 'Failed to start sound monitoring: $e';
      _scheduleRetry(msg);
    }
  }

  void _scheduleRetry(String errorReason) {
    if (!mounted || _isUserStopped || _isRetrying) return;
    _connectionWatchdog?.cancel();
    _durationTimer?.cancel();

    if (_retryCount < _maxRetries - 1) {
      _isRetrying = true;
      _retryCount++;
      debugPrint('Retrying audio stream (attempt ${_retryCount + 1} of $_maxRetries)... Reason: $errorReason');

      if (_sessionId != null) {
        final oldSid = _sessionId!;
        _sessionId = null;
        ApiService.instance.stopAudioStream(oldSid).catchError((_) {});
      }

      if (mounted) {
        setState(() {
          _state = _AudioViewState.connecting;
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
      _isRetrying = false;
      if (mounted) {
        setState(() {
          _state = _AudioViewState.error;
          _errorMessage = errorReason;
        });
      }
    }
  }

  void _startTimer() {
    if (_durationTimer?.isActive == true) return;
    _secondsElapsed = 0;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _secondsElapsed++;
        });
      }
    });
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

    // Explicitly declare audio receiver transceiver for Unified Plan WebRTC
    try {
      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
    } catch (_) {}

    pc.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'audio') {
        _remoteAudioTrack = event.track;
        _remoteAudioTrack?.enabled = !_isMuted;
        if (event.streams.isNotEmpty) {
          final stream = event.streams.first;
          _audioRenderer.srcObject = stream;
        } else {
          createLocalMediaStream('remote_ambient_audio').then((stream) {
            stream.addTrack(event.track);
            _audioRenderer.srcObject = stream;
          });
        }
        try {
          Helper.setSpeakerphoneOn(_isSpeakerOn);
        } catch (_) {}

        _connectionWatchdog?.cancel();
        _retryCount = 0;

        if (mounted) {
          setState(() {
            _state = _AudioViewState.live;
          });
          _startTimer();
        }
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
          _scheduleRetry('Audio WebRTC connection lost.');
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
          _scheduleRetry('Audio ICE negotiation failed.');
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
      debugPrint('Error handling audio webrtc_offer: $e');
      _scheduleRetry('Error negotiating audio stream.');
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

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    _remoteAudioTrack?.enabled = !_isMuted;
    if (_audioRenderer.srcObject != null) {
      for (final track in _audioRenderer.srcObject!.getAudioTracks()) {
        track.enabled = !_isMuted;
      }
    }
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
    try {
      Helper.setSpeakerphoneOn(_isSpeakerOn);
    } catch (_) {}
  }

  Future<void> _stopStream() async {
    _isUserStopped = true;
    _connectionWatchdog?.cancel();
    _retryTimer?.cancel();
    if (_sessionId != null) {
      try {
        await ApiService.instance.stopAudioStream(_sessionId!);
      } catch (_) {}
    }
    await _teardown(notifyBackend: false);
  }

  Future<void> _teardown({required bool notifyBackend}) async {
    _connectionWatchdog?.cancel();
    _retryTimer?.cancel();
    _durationTimer?.cancel();
    if (mounted) {
      setState(() {
        _state = _AudioViewState.ended;
      });
    }
    _remoteDescriptionSet = false;
    _pendingIceCandidates.clear();
    _remoteAudioTrack = null;
    try {
      _audioRenderer.srcObject = null;
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
    _durationTimer?.cancel();
    _animController.dispose();
    _pendingIceCandidates.clear();
    try {
      _audioRenderer.srcObject = null;
      _audioRenderer.dispose();
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

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Slate 900
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sound Around Child',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Text(
              widget.childName,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_state == _AudioViewState.live) ...[
            IconButton(
              icon: Icon(_isSpeakerOn ? Icons.volume_up : Icons.phone_in_talk),
              tooltip: _isSpeakerOn ? 'Switch to Earpiece' : 'Switch to Speaker',
              onPressed: _toggleSpeaker,
            ),
            IconButton(
              icon: Icon(_isMuted ? Icons.mic_off : Icons.mic),
              tooltip: _isMuted ? 'Unmute Audio' : 'Mute Audio',
              onPressed: _toggleMute,
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              // Status chip header
              _buildStatusHeader(),
              const Spacer(),

              // Central Visualizer
              _buildCentralVisualizer(),

              const SizedBox(height: 24),

              // Duration Timer
              if (_state == _AudioViewState.live)
                Text(
                  _formatDuration(_secondsElapsed),
                  style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 2,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),

              const SizedBox(height: 12),

              // Description / Subtitle
              _buildStatusSubtitle(),

              const Spacer(),

              // Action buttons at bottom
              _buildBottomControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusHeader() {
    Color bg;
    Color dotColor;
    String label;

    switch (_state) {
      case _AudioViewState.connecting:
        bg = Colors.amber.withOpacity(0.15);
        dotColor = Colors.amber;
        label = _retryCount > 0
            ? 'RECONNECTING (${_retryCount + 1}/$_maxRetries)...'
            : 'CONNECTING...';
        break;
      case _AudioViewState.waitingForChild:
        bg = Colors.blue.withOpacity(0.15);
        dotColor = Colors.lightBlueAccent;
        label = _retryCount > 0
            ? 'RETRYING (${_retryCount + 1}/$_maxRetries)...'
            : 'WAITING FOR CHILD DEVICE';
        break;
      case _AudioViewState.live:
        if (_isMuted) {
          bg = Colors.orange.withOpacity(0.15);
          dotColor = Colors.orange;
          label = 'AUDIO MUTED';
        } else {
          bg = Colors.green.withOpacity(0.15);
          dotColor = Colors.greenAccent;
          label = 'LIVE SURROUNDINGS';
        }
        break;
      case _AudioViewState.ended:
        bg = Colors.grey.withOpacity(0.15);
        dotColor = Colors.grey;
        label = 'SESSION ENDED';
        break;
      case _AudioViewState.error:
        bg = Colors.red.withOpacity(0.15);
        dotColor = Colors.redAccent;
        label = 'CONNECTION FAILED';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dotColor.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
              color: dotColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCentralVisualizer() {
    final isLive = _state == _AudioViewState.live;

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final animVal = _animController.value;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Outermost Ripple
            if (isLive)
              Container(
                width: 220 + (animVal * 60),
                height: 220 + (animVal * 60),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.cyanAccent.withOpacity((1 - animVal) * 0.35),
                    width: 2,
                  ),
                ),
              ),

            // Middle Ripple
            if (isLive)
              Container(
                width: 170 + (animVal * 40),
                height: 170 + (animVal * 40),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.cyan.withOpacity((1 - animVal) * 0.08),
                  border: Border.all(
                    color: Colors.cyan.withOpacity((1 - animVal) * 0.5),
                    width: 1.5,
                  ),
                ),
              ),

            // Inner Core Circle
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: isLive
                      ? [const Color(0xFF06B6D4), const Color(0xFF3B82F6)]
                      : _state == _AudioViewState.error
                          ? [Colors.red.shade700, Colors.red.shade900]
                          : [const Color(0xFF334155), const Color(0xFF1E293B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isLive ? const Color(0xFF06B6D4) : Colors.black)
                        .withOpacity(0.35),
                    blurRadius: 30,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  _state == _AudioViewState.error
                      ? Icons.error_outline
                      : _state == _AudioViewState.ended
                          ? Icons.mic_off
                          : (_isMuted ? Icons.volume_off : Icons.mic),
                  size: 54,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusSubtitle() {
    if (_state == _AudioViewState.live) {
      return Text(
        _isMuted
            ? 'Playback muted. Tap speaker icon to listen.'
            : 'Streaming microphone audio in high fidelity (Opus).',
        style: const TextStyle(fontSize: 14, color: Colors.white70),
        textAlign: TextAlign.center,
      );
    }
    if (_state == _AudioViewState.waitingForChild) {
      return const Text(
        'Notifying child device background service...\nMicrophone will activate without camera.',
        style: TextStyle(fontSize: 14, color: Colors.white70),
        textAlign: TextAlign.center,
      );
    }
    if (_state == _AudioViewState.connecting) {
      return const Text(
        'Establishing encrypted WebRTC audio session...',
        style: TextStyle(fontSize: 14, color: Colors.white70),
        textAlign: TextAlign.center,
      );
    }
    if (_state == _AudioViewState.error) {
      return Text(
        _errorMessage ?? 'An error occurred while connecting to microphone stream.',
        style: const TextStyle(fontSize: 14, color: Colors.redAccent),
        textAlign: TextAlign.center,
      );
    }
    return const Text(
      'Ambient audio session has ended.',
      style: TextStyle(fontSize: 14, color: Colors.white60),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildBottomControls() {
    if (_state == _AudioViewState.live || _state == _AudioViewState.waitingForChild) {
      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Mute/Unmute Toggle
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: _isMuted ? Colors.amber.shade900.withOpacity(0.4) : const Color(0xFF1E293B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _toggleMute,
                icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up),
                label: Text(_isMuted ? 'Unmute' : 'Mute'),
              ),
              const SizedBox(width: 16),
              // Speaker / Earpiece Toggle
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _toggleSpeaker,
                icon: Icon(_isSpeakerOn ? Icons.speaker : Icons.phone_in_talk),
                label: Text(_isSpeakerOn ? 'Speaker' : 'Earpiece'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444), // Red 500
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
              ),
              onPressed: _stopStream,
              icon: const Icon(Icons.call_end),
              label: const Text(
                'Stop Listening',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      );
    }

    if (_state == _AudioViewState.error || _state == _AudioViewState.ended) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white30),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to Dashboard'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF06B6D4),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                _retryCount = 0;
                _isRetrying = false;
                _startAttempt();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}
