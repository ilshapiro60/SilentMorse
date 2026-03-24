import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';

const _keyVibrationIntensity = 'vibration_intensity';
const _keyReceiveMode = 'receive_mode';
const _keySendMode = 'send_mode';
const _keySenderDisplayName = 'sender_display_name';
const _keyAutoSendDelayMs = 'auto_send_delay_ms';

/// Provides MorseSettings with user preferences (receive, send, vibration).
class MorseSettingsService extends ChangeNotifier {
  MorseSettingsService() {
    _load();
  }

  VibrationIntensity _vibrationIntensity = VibrationIntensity.medium;
  VibrationIntensity get vibrationIntensity => _vibrationIntensity;

  ReceiveMode _receiveMode = ReceiveMode.vibrate;
  ReceiveMode get receiveMode => _receiveMode;

  SendMode _sendMode = SendMode.text;
  SendMode get sendMode => _sendMode;

  String _senderDisplayName = '';
  String get senderDisplayName => _senderDisplayName;

  int _autoSendDelayMs = 3000;
  int get autoSendDelayMs => _autoSendDelayMs;

  MorseSettings get settings => MorseSettings(
    vibrationIntensity: _vibrationIntensity,
    receiveMode: _receiveMode,
    sendMode: _sendMode,
    autoSendDelayMs: _autoSendDelayMs,
  );

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIntensity = prefs.getString(_keyVibrationIntensity);
    final savedReceive = prefs.getString(_keyReceiveMode);
    final savedSend = prefs.getString(_keySendMode);
    final savedSenderName = prefs.getString(_keySenderDisplayName);
    var changed = false;
    if (savedIntensity != null) {
      _vibrationIntensity = VibrationIntensity.fromString(savedIntensity);
      changed = true;
    }
    if (savedReceive != null) {
      _receiveMode = ReceiveMode.fromString(savedReceive);
      changed = true;
    }
    if (savedSend != null) {
      _sendMode = SendMode.fromString(savedSend);
      changed = true;
    }
    if (savedSenderName != null) {
      _senderDisplayName = savedSenderName;
      changed = true;
    }
    final savedAutoSend = prefs.getInt(_keyAutoSendDelayMs);
    if (savedAutoSend != null) {
      _autoSendDelayMs = savedAutoSend;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  Future<void> setVibrationIntensity(VibrationIntensity intensity) async {
    if (_vibrationIntensity == intensity) return;
    _vibrationIntensity = intensity;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyVibrationIntensity, intensity.name);
    notifyListeners();
  }

  Future<void> setReceiveMode(ReceiveMode mode) async {
    if (_receiveMode == mode) return;
    _receiveMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyReceiveMode, mode.name);
    notifyListeners();
  }

  Future<void> setSendMode(SendMode mode) async {
    if (_sendMode == mode) return;
    _sendMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySendMode, mode.name);
    notifyListeners();
  }

  Future<void> setAutoSendDelayMs(int ms) async {
    if (_autoSendDelayMs == ms) return;
    _autoSendDelayMs = ms;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyAutoSendDelayMs, ms);
    notifyListeners();
  }

  Future<void> setSenderDisplayName(String name) async {
    final trimmed = name.trim();
    if (_senderDisplayName == trimmed) return;
    _senderDisplayName = trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySenderDisplayName, trimmed);
    notifyListeners();
  }
}
