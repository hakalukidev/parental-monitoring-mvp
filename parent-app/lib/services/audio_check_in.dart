import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'api_service.dart';
import 'socket_service.dart';

enum AudioCheckInState {
  idle,
  requesting,
  authorizing,
  connecting,
  live,
  ended,
  rejected,
  error
}

class AudioCheckIn extends ChangeNotifier {
  final String childId;
  AudioCheckIn(this.childId);
  AudioCheckInState state = AudioCheckInState.idle;
  String? error;
  String quality = 'Not measured';
  Duration duration = Duration.zero;
  bool speaker = true;
  double volume = 1;
  final _socket = SocketService();
  var _renderer = RTCVideoRenderer();
  RTCPeerConnection? _peer;
  MediaStream? _remote;
  MediaStreamTrack? _audio;
  String? _id;
  bool _closing = false,
      _disposed = false,
      _connected = false,
      _remoteDescription = false,
      _rendererReady = false;
  int _generation = 0;
  final _elapsed = Stopwatch();
  final _freshness = Stopwatch();
  num _lastPackets = 0;
  int _lastReceive = 0;
  final List<RTCIceCandidate> _ice = [];
  Timer? _timeout, _stats;
  bool get running => [
        AudioCheckInState.requesting,
        AudioCheckInState.authorizing,
        AudioCheckInState.connecting,
        AudioCheckInState.live
      ].contains(state);
  void _update() {
    if (!_disposed) notifyListeners();
  }

  bool _matches(dynamic data) =>
      !_closing && _id != null && data is Map && data['sessionId'] == _id;
  Future<void> request() async {
    if (running || _disposed) return;
    _closing = false;
    final generation = ++_generation;
    _elapsed.reset();
    _freshness.reset();
    _freshness.start();
    _lastPackets = 0;
    _lastReceive = 0;
    error = null;
    quality = 'Not measured';
    duration = Duration.zero;
    state = AudioCheckInState.requesting;
    _update();
    try {
      final config = await ApiService.instance.getServerConfig();
      if (_closing || _disposed || generation != _generation) return;
      if ((config['features'] as Map?)?['audioCheckIn'] != true) {
        throw StateError('Audio check-in is unavailable on this server.');
      }
      final token = await ApiService.instance.accessToken;
      if (token == null) {
        throw StateError('Sign in again to request a check-in.');
      }
      if (_closing || _disposed || generation != _generation) return;
      final renderer = _renderer;
      await renderer.initialize();
      if (_closing || _disposed || generation != _generation) {
        await renderer.dispose();
        return;
      }
      _rendererReady = true;
      final peer = await createPeerConnection({
        'iceServers': config['iceServers'] ?? [],
        'sdpSemantics': 'unified-plan'
      });
      if (_closing || _disposed || generation != _generation) {
        await peer.close();
        return;
      }
      _peer = peer;
      _peer!.onConnectionState = (status) {
        if (_closing || generation != _generation) return;
        _connected =
            status == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
        if ([
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
              RTCPeerConnectionState.RTCPeerConnectionStateFailed,
              RTCPeerConnectionState.RTCPeerConnectionStateClosed
            ].contains(status) &&
            !_closing) {
          unawaited(
              _fail('The audio connection ended. Request a new check-in.'));
        }
      };
      _peer!.onTrack = (event) {
        if (_closing ||
            generation != _generation ||
            event.track.kind != 'audio') {
          return;
        }
        _audio = event.track;
        unawaited(setSpeaker(true));
        if (event.streams.isNotEmpty) {
          _remote = event.streams.first;
          _renderer.srcObject = _remote;
        }
      };
      _peer!.onIceCandidate = (candidate) {
        if (!_closing && generation == _generation && _id != null) {
          _socket.sendIceCandidate(_id!, candidate.toMap());
        }
      };
      _socket.connect(token, onAuthError: () {
        if (!_closing && generation == _generation) {
          unawaited(_fail(
              'Your session expired. Sign in and request another check-in.'));
        }
      });
      _socket.onDisconnect(() {
        if (!_closing && generation == _generation) {
          unawaited(
              _fail('Connection lost. The microphone session has stopped.'));
        }
      });
      for (final event in [
        'audio_session_accept',
        'audio_session_reject',
        'audio_session_stopped'
      ]) {
        _socket.socket.on(event, (data) {
          if (generation != _generation || !_matches(data)) return;
          if (event == 'audio_session_accept') {
            state = AudioCheckInState.connecting;
            _update();
          } else if (event == 'audio_session_reject') {
            unawaited(_end(
                AudioCheckInState.rejected,
                'The device could not activate its microphone. Review device permissions and try again.',
                false));
          } else {
            unawaited(_end(AudioCheckInState.ended, null, false));
          }
        });
      }
      _socket.socket.on('operation_error', (_) {
        if (!_closing && generation == _generation) {
          unawaited(_fail('This audio session could not be authorized.'));
        }
      });
      _socket.onWebrtcOffer((data) async {
        if (generation != _generation || !_matches(data)) return;
        try {
          final sdp = data['sdp'] as Map;
          await peer.setRemoteDescription(RTCSessionDescription(
              sdp['sdp'] as String, sdp['type'] as String));
          if (_closing || generation != _generation) return;
          _remoteDescription = true;
          final pending = List<RTCIceCandidate>.of(_ice);
          _ice.clear();
          for (final candidate in pending) {
            await peer.addCandidate(candidate);
            if (_closing || generation != _generation) return;
          }
          final answer = await peer.createAnswer();
          if (_closing || generation != _generation) return;
          await peer.setLocalDescription(answer);
          if (!_closing && generation == _generation && _id != null) {
            _socket.sendWebrtcAnswer(_id!, answer.toMap());
          }
        } catch (_) {
          if (!_closing && generation == _generation) {
            await _fail('Audio negotiation failed. Please try again.');
          }
        }
      });
      _socket.onIceCandidate((data) async {
        if (generation != _generation || !_matches(data)) return;
        final c = data['candidate'] as Map;
        final candidate = RTCIceCandidate(c['candidate'] as String?,
            c['sdpMid'] as String?, c['sdpMLineIndex'] as int?);
        try {
          if (_remoteDescription) {
            await peer.addCandidate(candidate);
          } else {
            _ice.add(candidate);
          }
        } catch (_) {
          if (!_closing && generation == _generation) {
            await _fail(
                'The audio network connection could not be established.');
          }
        }
      });
      final connected = Completer<void>();
      if (_socket.isConnected) {
        connected.complete();
      } else {
        _socket.onConnect(() {
          if (!connected.isCompleted) connected.complete();
        });
      }
      await connected.future.timeout(const Duration(seconds: 12));
      if (_closing || generation != _generation) return;
      final result = await ApiService.instance.requestAudioSession(childId);
      final id = result['sessionId'] as String;
      if (_closing || _disposed || generation != _generation) {
        await ApiService.instance.stopAudioSession(id);
        return;
      }
      _id = id;
      state = AudioCheckInState.authorizing;
      _update();
      _timeout = Timer(
          const Duration(minutes: 2),
          () => unawaited(_fail(
              'The check-in timed out. Open Seftly on the child device and try again.')));
      _stats = Timer.periodic(
          const Duration(seconds: 1), (_) => unawaited(_measure(generation)));
    } catch (e) {
      if (!_closing && !_disposed && generation == _generation) {
        await _fail(e.toString());
      }
    }
  }

  Future<void> _measure(int generation) async {
    if (_closing || _peer == null || !_connected || _audio == null) return;
    try {
      final stats = await _peer!.getStats(_audio);
      if (_closing || generation != _generation) return;
      for (final report in stats) {
        final values = report.values;
        final kind = values['kind'] ?? values['mediaType'];
        final packets = num.tryParse('${values['packetsReceived']}') ?? 0;
        if (report.type == 'inbound-rtp' && kind == 'audio' && packets > 0) {
          _timeout?.cancel();
          if (packets != _lastPackets) {
            _lastPackets = packets;
            _lastReceive = _freshness.elapsedMilliseconds;
          }
          if (_freshness.elapsedMilliseconds - _lastReceive > 15000) {
            await _fail('Audio stopped arriving. Request a new check-in.');
            return;
          }
          if (!_elapsed.isRunning) _elapsed.start();
          state = AudioCheckInState.live;
          duration = _elapsed.elapsed;
          final lost = num.tryParse('${values['packetsLost']}') ?? 0;
          final loss = lost / (packets + lost);
          quality = loss > .1
              ? 'Poor · packet loss'
              : loss > .03
                  ? 'Fair'
                  : 'Good';
          _update();
        }
      }
    } catch (_) {
      /* Leave quality unavailable until actual receive statistics exist. */
    }
  }

  Future<void> setSpeaker(bool value) async {
    try {
      await Helper.setSpeakerphoneOn(value);
      speaker = value;
    } catch (_) {
      error = 'The audio output route could not be changed.';
    }
    _update();
  }

  Future<void> setVolume(double value) async {
    try {
      if (_audio != null) await Helper.setVolume(value, _audio!);
      volume = value;
    } catch (_) {
      error = 'The playback volume could not be changed.';
    }
    _update();
  }

  Future<void> stop() => _end(AudioCheckInState.ended, null, true);
  Future<void> _fail(String message) =>
      _end(AudioCheckInState.error, message, true);
  Future<void> _end(
      AudioCheckInState next, String? message, bool notify) async {
    if (_closing) return;
    _closing = true;
    _generation++;
    _elapsed.stop();
    _freshness.stop();
    _timeout?.cancel();
    _stats?.cancel();
    final id = _id;
    _id = null;
    if (notify && id != null && _socket.isConnected) {
      _socket.socket.emit('audio_session_stopped', {'sessionId': id});
    }
    try {
      await _audio?.stop();
    } catch (_) {}
    _audio = null;
    try {
      await _peer?.close();
    } catch (_) {}
    _peer = null;
    if (_rendererReady) {
      _renderer.srcObject = null;
    }
    try {
      await _remote?.dispose();
    } catch (_) {}
    _remote = null;
    if (_rendererReady) {
      try {
        await _renderer.dispose();
      } catch (_) {}
    }
    _rendererReady = false;
    _renderer = RTCVideoRenderer();
    _socket.disconnect();
    _ice.clear();
    _remoteDescription = false;
    _connected = false;
    state = next;
    error = message;
    _update();
    if (notify && id != null) {
      try {
        await ApiService.instance.stopAudioSession(id);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}
