/// Silent Morse data models.
/// Mirrors the Kotlin Models.kt structure.
library silentmorse_messenger.data.models;

import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────
// USER
// ─────────────────────────────────────────────

class User {
  final String id;
  final String displayName;
  final String username;
  final String phoneHash;
  final String fcmToken;
  final bool isPro;
  final MorseSettings morseSettings;
  final DateTime? createdAt;
  final DateTime? lastSeen;

  User({
    this.id = '',
    this.displayName = '',
    this.username = '',
    this.phoneHash = '',
    this.fcmToken = '',
    this.isPro = false,
    MorseSettings? morseSettings,
    this.createdAt,
    this.lastSeen,
  }) : morseSettings = morseSettings ?? MorseSettings();

  factory User.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return User(
      id: doc.id,
      displayName: data['displayName'] ?? '',
      username: data['username'] ?? '',
      phoneHash: data['phoneHash'] ?? '',
      fcmToken: data['fcmToken'] ?? '',
      isPro: data['isPro'] ?? false,
      morseSettings: MorseSettings.fromMap(data['morseSettings']),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      lastSeen: (data['lastSeen'] as Timestamp?)?.toDate(),
    );
  }
}

class MorseSettings {
  final int dotDurationMs;
  final int dashDurationMs;
  final int letterGapMs;
  final int wordGapMs;
  final VibrationIntensity vibrationIntensity;
  final ReceiveMode receiveMode;
  final SendMode sendMode;
  /// Milliseconds of silence after the last tap before auto-sending. 0 = off.
  final int autoSendDelayMs;

  MorseSettings({
    this.dotDurationMs = 200,
    this.dashDurationMs = 300,
    this.letterGapMs = 500,
    this.wordGapMs = 1200,
    this.vibrationIntensity = VibrationIntensity.medium,
    this.receiveMode = ReceiveMode.vibrate,
    this.sendMode = SendMode.text,
    this.autoSendDelayMs = 3000,
  });

  factory MorseSettings.fromMap(dynamic map) {
    if (map == null || map is! Map) return MorseSettings();
    final intensity = map['vibrationIntensity']?.toString() ?? 'MEDIUM';
    final receive = map['receiveMode']?.toString() ?? 'VIBRATE';
    final send = map['sendMode']?.toString() ?? 'TEXT';
    return MorseSettings(
      dotDurationMs: map['dotDurationMs'] ?? 200,
      dashDurationMs: map['dashDurationMs'] ?? 300,
      letterGapMs: map['letterGapMs'] ?? 1000,
      wordGapMs: map['wordGapMs'] ?? 2000,
      vibrationIntensity: VibrationIntensity.fromString(intensity),
      receiveMode: ReceiveMode.fromString(receive),
      sendMode: SendMode.fromString(send),
    );
  }

  Map<String, dynamic> toMap() => {
        'dotDurationMs': dotDurationMs,
        'dashDurationMs': dashDurationMs,
        'letterGapMs': letterGapMs,
        'wordGapMs': wordGapMs,
        'vibrationIntensity': vibrationIntensity.name,
        'receiveMode': receiveMode.name,
        'sendMode': sendMode.name,
      };
}

/// How to receive incoming messages in dark mode.
enum ReceiveMode {
  vibrate,
  text;

  static ReceiveMode fromString(String s) {
    switch (s.toUpperCase()) {
      case 'TEXT':
      case 'TEXTANDMORSE':
        return ReceiveMode.text;
      default:
        return ReceiveMode.vibrate;
    }
  }
}

/// How to send in dark mode (touch input display).
enum SendMode {
  touch,
  text;

  static SendMode fromString(String s) {
    switch (s.toUpperCase()) {
      case 'TEXT':
        return SendMode.text;
      case 'TOUCHWITHTEXT':
      case 'TOUCH_WITH_TEXT':
        return SendMode.text;
      default:
        return SendMode.touch;
    }
  }
}

enum VibrationIntensity {
  none(0),
  silent(15),
  low(80),
  medium(160),
  high(255);

  final int amplitude;
  const VibrationIntensity(this.amplitude);

  static VibrationIntensity fromString(String s) {
    switch (s.toUpperCase()) {
      case 'NONE':
        return VibrationIntensity.none;
      case 'SILENT':
        return VibrationIntensity.silent;
      case 'LOW':
        return VibrationIntensity.low;
      case 'HIGH':
        return VibrationIntensity.high;
      default:
        return VibrationIntensity.medium;
    }
  }
}

// ─────────────────────────────────────────────
// CONTACT
// ─────────────────────────────────────────────

class Contact {
  final String id;
  final String userId;
  final String displayName;
  final String username;
  final String nickname;
  final DateTime? addedAt;

  Contact({
    this.id = '',
    this.userId = '',
    this.displayName = '',
    this.username = '',
    this.nickname = '',
    this.addedAt,
  });

  factory Contact.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Contact(
      id: doc.id,
      userId: data['userId'] ?? '',
      displayName: data['displayName'] ?? '',
      username: data['username'] ?? '',
      nickname: data['nickname'] ?? '',
      addedAt: (data['addedAt'] as Timestamp?)?.toDate(),
    );
  }
}

// ─────────────────────────────────────────────
// CHAT
// ─────────────────────────────────────────────

enum ChatStatus {
  pending,
  active,
  declined;

  static ChatStatus fromString(String? s) {
    switch (s?.toUpperCase()) {
      case 'PENDING':
        return ChatStatus.pending;
      case 'DECLINED':
        return ChatStatus.declined;
      default:
        // Null/missing field means the chat pre-dates the status feature → treat as active.
        return ChatStatus.active;
    }
  }
}

class Chat {
  final String id;
  final List<String> participants;
  final String name;
  final String lastMessage;
  final String lastMessageBy;
  final DateTime? lastMessageAt;
  final DateTime? createdAt;
  final ChatStatus status;
  final String requesterId;

  Chat({
    this.id = '',
    this.participants = const [],
    this.name = '',
    this.lastMessage = '',
    this.lastMessageBy = '',
    this.lastMessageAt,
    this.createdAt,
    this.status = ChatStatus.active,
    this.requesterId = '',
  });

  bool get isGroup => participants.length > 2;
  bool get isPending => status == ChatStatus.pending;
  bool get isActive => status == ChatStatus.active;

  String otherParticipant(String myUserId) =>
      participants.where((id) => id != myUserId).firstOrNull ?? '';

  factory Chat.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final participantsList = data['participants'];
    return Chat(
      id: doc.id,
      participants: participantsList is List
          ? List<String>.from(participantsList.map((e) => e.toString()))
          : [],
      name: data['name'] ?? '',
      lastMessage: data['lastMessage'] ?? '',
      lastMessageBy: data['lastMessageBy'] ?? '',
      lastMessageAt: (data['lastMessageAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      status: ChatStatus.fromString(data['status'] as String?),
      requesterId: data['requesterId'] ?? '',
    );
  }
}

// ─────────────────────────────────────────────
// MESSAGE
// ─────────────────────────────────────────────

class Message {
  final String id;
  final String senderId;
  final String senderDisplayName;
  final String text;
  final String morse;
  final InputMode inputMode;
  final DateTime? sentAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  Message({
    this.id = '',
    this.senderId = '',
    this.senderDisplayName = '',
    this.text = '',
    this.morse = '',
    this.inputMode = InputMode.typed,
    this.sentAt,
    this.deliveredAt,
    this.readAt,
  });

  bool get isDelivered => deliveredAt != null;
  bool get isRead => readAt != null;

  factory Message.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final mode = data['inputMode']?.toString() ?? 'TYPED';
    return Message(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      senderDisplayName: data['senderDisplayName'] ?? '',
      text: data['text'] ?? '',
      morse: data['morse'] ?? '',
      inputMode: mode == 'TAPPED' ? InputMode.tapped : InputMode.typed,
      sentAt: (data['sentAt'] as Timestamp?)?.toDate(),
      deliveredAt: (data['deliveredAt'] as Timestamp?)?.toDate(),
      readAt: (data['readAt'] as Timestamp?)?.toDate(),
    );
  }
}

enum InputMode { typed, tapped }

// ─────────────────────────────────────────────
// HAPTIC PULSE
// ─────────────────────────────────────────────

class HapticPulse {
  final int durationMs;
  final bool isOn;

  HapticPulse(this.durationMs, this.isOn);
}
