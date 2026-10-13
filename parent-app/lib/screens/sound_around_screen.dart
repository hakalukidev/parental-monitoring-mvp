import 'package:flutter/material.dart';
import '../design/seftly_widgets.dart';
import '../services/audio_check_in.dart';
import '../services/api_service.dart';
import '../design/family_date_time.dart';

class SoundAroundScreen extends StatefulWidget {
  final String childId, childName;
  const SoundAroundScreen(
      {super.key, required this.childId, required this.childName});
  @override
  State<SoundAroundScreen> createState() => _SoundAroundScreenState();
}

class _SoundAroundScreenState extends State<SoundAroundScreen> {
  late final AudioCheckIn _session;
  String _lastCompleted = 'Not reported';
  @override
  void initState() {
    super.initState();
    _session = AudioCheckIn(widget.childId);
    _loadLastCompleted();
  }

  Future<void> _loadLastCompleted() async {
    try {
      final policy =
          await ApiService.instance.getActivityPolicy(widget.childId);
      if (mounted) {
        setState(() => _lastCompleted = FamilyDateTime.parse(
            ((policy['lastCheckIns'] as Map?)?['audio'] as Map?)?['endedAt']));
      }
    } catch (_) {
      /* An unavailable history must not invent a last successful date. */
    }
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _session,
      builder: (context, _) => SeftlyScaffold(
            title: 'Sound check-in',
            subtitle: 'A live audio-only check-in with ${widget.childName}.',
            icon: Icons.hearing_rounded,
            body: ListView(padding: const EdgeInsets.all(24), children: [
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(
                                _session.state == AudioCheckInState.live
                                    ? Icons.graphic_eq
                                    : Icons.mic_none_rounded,
                                size: 64),
                            const SizedBox(height: 16),
                            Text(
                                switch (_session.state) {
                                  AudioCheckInState.idle =>
                                    'Ready to request a check-in',
                                  AudioCheckInState.requesting =>
                                    'Sending request',
                                  AudioCheckInState.authorizing =>
                                    'Connecting to the child device',
                                  AudioCheckInState.connecting =>
                                    'Connecting audio',
                                  AudioCheckInState.live =>
                                    'Live audio received',
                                  AudioCheckInState.rejected =>
                                    'Microphone activation declined or unavailable',
                                  AudioCheckInState.ended => 'Check-in ended',
                                  AudioCheckInState.error =>
                                    'Check-in unavailable'
                                },
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 12),
                            Text('Last completed check-in: $_lastCompleted'),
                            TextButton(
                                onPressed: _loadLastCompleted,
                                child: const Text('Refresh check-in history')),
                            const Text(
                                'Parent requests reuse granted microphone permission. Android may require Seftly to be in the foreground or a system permission dialog. Capture has a visible indicator and Stop; audio is not saved by Seftly.'),
                            if (_session.error != null)
                              Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(_session.error!,
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error))),
                            if (_session.state == AudioCheckInState.live) ...[
                              const SizedBox(height: 16),
                              Text(
                                  'Duration ${_session.duration.inMinutes}:${(_session.duration.inSeconds % 60).toString().padLeft(2, '0')} · Connection ${_session.quality}'),
                              SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Speaker output'),
                                  value: _session.speaker,
                                  onChanged: (v) => _session.setSpeaker(v)),
                              const Text('Playback volume'),
                              Slider(
                                  value: _session.volume,
                                  onChanged: (v) => _session.setVolume(v)),
                            ],
                            const SizedBox(height: 20),
                            if (_session.running)
                              FilledButton.icon(
                                  onPressed: _session.stop,
                                  icon: const Icon(Icons.stop),
                                  label: const Text('Stop check-in'))
                            else
                              FilledButton.icon(
                                  onPressed: _session.request,
                                  icon: const Icon(Icons.mic),
                                  label: Text(
                                      _session.state == AudioCheckInState.idle
                                          ? 'Request audio check-in'
                                          : 'Request a new check-in')),
                          ]))),
            ]),
          ));
}
