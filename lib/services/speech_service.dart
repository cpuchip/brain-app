import 'dart:async';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Speech-to-text and text-to-speech service for voice capture and readback.
class SpeechService {
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _sttAvailable = false;
  bool _isListening = false;
  bool _isSpeaking = false;

  void Function(String text, bool isFinal)? onResult;
  void Function(bool listening)? onListeningChanged;
  void Function(String error)? onError;

  bool get isAvailable => _sttAvailable;
  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;

  /// Initialize both STT and TTS. Call once on app start.
  Future<void> init() async {
    // Speech-to-text
    _sttAvailable = await _stt.initialize(
      onError: (error) {
        _isListening = false;
        onListeningChanged?.call(false);
        onError?.call(error.errorMsg);
      },
      onStatus: (status) {
        final listening = status == 'listening';
        if (_isListening != listening) {
          _isListening = listening;
          onListeningChanged?.call(listening);
        }
      },
    );

    // Text-to-speech
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setCompletionHandler(() {
      _isSpeaking = false;
    });
  }

  /// Start listening for speech input.
  Future<void> startListening() async {
    if (!_sttAvailable) {
      onError?.call('Speech recognition not available');
      return;
    }
    if (_isListening) return;

    // Stop TTS if playing
    if (_isSpeaking) {
      await stopSpeaking();
    }

    _isListening = true;
    onListeningChanged?.call(true);

    await _stt.listen(
      onResult: (SpeechRecognitionResult result) {
        onResult?.call(
          result.recognizedWords,
          result.finalResult,
        );
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  /// Stop listening.
  Future<void> stopListening() async {
    if (!_isListening) return;
    await _stt.stop();
    _isListening = false;
    onListeningChanged?.call(false);
  }

  /// Toggle listening on/off.
  Future<void> toggleListening() async {
    if (_isListening) {
      await stopListening();
    } else {
      await startListening();
    }
  }

  /// Speak text aloud (for reading back classification results).
  Future<void> speak(String text) async {
    _isSpeaking = true;
    await _tts.speak(text);
  }

  /// Stop speaking.
  Future<void> stopSpeaking() async {
    _isSpeaking = false;
    await _tts.stop();
  }

  /// Clean up resources.
  void dispose() {
    _stt.stop();
    _tts.stop();
  }
}
