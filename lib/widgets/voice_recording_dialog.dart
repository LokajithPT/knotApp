import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/note.dart';
import '../config/app_config.dart';

class VoiceRecordingDialog extends StatefulWidget {
  final String filePath;
  final String noteName;
  final VoidCallback onComplete;

  const VoiceRecordingDialog({
    super.key,
    required this.filePath,
    required this.noteName,
    required this.onComplete,
  });

  @override
  State<VoiceRecordingDialog> createState() => _VoiceRecordingDialogState();
}

class _VoiceRecordingDialogState extends State<VoiceRecordingDialog> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isPaused = false;
  int _recordingSeconds = 0;
  List<double> _amplitudes = [];
  StreamSubscription? _amplitudeSubscription;

  @override
  void initState() {
    super.initState();
    _startRecording();
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (mounted) Navigator.pop(context);
      return;
    }
    
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: widget.filePath);
    setState(() => _isRecording = true);
    _updateTimer();
    _startAmplitudeTracking();
  }

  void _updateTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (_isRecording && !_isPaused && mounted) {
        setState(() => _recordingSeconds++);
        _updateTimer();
      }
    });
  }

  void _startAmplitudeTracking() {
    _amplitudeSubscription = Stream.periodic(const Duration(milliseconds: 100)).listen((_) async {
      if (_isRecording && !_isPaused) {
        final amp = await _recorder.getAmplitude();
        final db = amp.current;
        final normalized = ((db + 60) / 60).clamp(0.0, 1.0);
        if (mounted) {
          setState(() => _amplitudes.add(normalized));
        }
      }
    });
  }

  Future<void> _saveWaveform() async {
    final waveformPath = widget.filePath.replaceAll('.m4a', '.waveform');
    final file = File(waveformPath);
    final data = _amplitudes.map((a) => a.toString()).join(',');
    await file.writeAsString(data);
  }

  Future<void> _stopRecording() async {
    await _recorder.stop();
    setState(() => _isRecording = false);
    await _amplitudeSubscription?.cancel();
  }

  void _saveAndClose() async {
    await _stopRecording();
    await _saveWaveform();
    if (mounted) {
      Navigator.pop(context);
      widget.onComplete();
    }
  }

  void _cancel() async {
    await _stopRecording();
    if (await File(widget.filePath).exists()) {
      await File(widget.filePath).delete();
    }
    if (mounted) Navigator.pop(context);
  }

  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _amplitudeSubscription?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1a1a2e),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.noteName, style: const TextStyle(color: Color(0xFF00ff88))),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0a0a0f),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  _isRecording ? Icons.mic : Icons.stop,
                  color: _isRecording ? Colors.red : Colors.grey,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  _isRecording ? _formatTime(_recordingSeconds) : 'Recording stopped',
                  style: TextStyle(
                    color: _isRecording ? Colors.white : Colors.grey,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isRecording ? 'Recording...' : 'Tap to stop',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                onPressed: _cancel,
                child: const Text('Cancel', style: TextStyle(color: Colors.red)),
              ),
              ElevatedButton(
                onPressed: _isRecording ? _stopRecording : _saveAndClose,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00ff88),
                  foregroundColor: const Color(0xFF0a0a0f),
                ),
                child: Text(_isRecording ? 'Stop' : 'Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
