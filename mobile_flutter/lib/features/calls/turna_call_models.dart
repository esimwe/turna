import 'package:flutter/foundation.dart';

String? _turnaCallNullableString(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

enum TurnaCallType { audio, video }

enum TurnaCallStatus { ringing, accepted, declined, missed, ended, cancelled }

class TurnaCallPeer {
  TurnaCallPeer({required this.id, required this.displayName, this.avatarUrl});

  final String id;
  final String displayName;
  final String? avatarUrl;

  factory TurnaCallPeer.fromMap(Map<String, dynamic> map) {
    return TurnaCallPeer(
      id: (map['id'] ?? '').toString(),
      displayName: (map['displayName'] ?? '').toString(),
      avatarUrl: _turnaCallNullableString(map['avatarUrl']),
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'displayName': displayName, 'avatarUrl': avatarUrl};
  }
}

class TurnaCallSummary {
  TurnaCallSummary({
    required this.id,
    required this.callerId,
    required this.calleeId,
    required this.type,
    required this.status,
    required this.provider,
    required this.direction,
    required this.peer,
    required this.caller,
    required this.callee,
    this.roomName,
    this.createdAt,
    this.acceptedAt,
    this.endedAt,
  });

  final String id;
  final String callerId;
  final String calleeId;
  final TurnaCallType type;
  final TurnaCallStatus status;
  final String provider;
  final String direction;
  final String? roomName;
  final String? createdAt;
  final String? acceptedAt;
  final String? endedAt;
  final TurnaCallPeer peer;
  final TurnaCallPeer caller;
  final TurnaCallPeer callee;

  TurnaCallSummary copyWith({
    TurnaCallType? type,
    TurnaCallStatus? status,
    String? acceptedAt,
    bool clearAcceptedAt = false,
    String? endedAt,
    bool clearEndedAt = false,
  }) {
    return TurnaCallSummary(
      id: id,
      callerId: callerId,
      calleeId: calleeId,
      type: type ?? this.type,
      status: status ?? this.status,
      provider: provider,
      direction: direction,
      peer: peer,
      caller: caller,
      callee: callee,
      roomName: roomName,
      createdAt: createdAt,
      acceptedAt: clearAcceptedAt ? null : (acceptedAt ?? this.acceptedAt),
      endedAt: clearEndedAt ? null : (endedAt ?? this.endedAt),
    );
  }

  factory TurnaCallSummary.fromMap(Map<String, dynamic> map) {
    return TurnaCallSummary(
      id: (map['id'] ?? '').toString(),
      callerId: (map['callerId'] ?? '').toString(),
      calleeId: (map['calleeId'] ?? '').toString(),
      type: ((map['type'] ?? '').toString().toLowerCase() == 'video')
          ? TurnaCallType.video
          : TurnaCallType.audio,
      status: switch ((map['status'] ?? '').toString().toLowerCase()) {
        'accepted' => TurnaCallStatus.accepted,
        'declined' => TurnaCallStatus.declined,
        'missed' => TurnaCallStatus.missed,
        'ended' => TurnaCallStatus.ended,
        'cancelled' => TurnaCallStatus.cancelled,
        _ => TurnaCallStatus.ringing,
      },
      provider: (map['provider'] ?? '').toString(),
      direction: (map['direction'] ?? 'outgoing').toString(),
      roomName: _turnaCallNullableString(map['roomName']),
      createdAt: _turnaCallNullableString(map['createdAt']),
      acceptedAt: _turnaCallNullableString(map['acceptedAt']),
      endedAt: _turnaCallNullableString(map['endedAt']),
      peer: TurnaCallPeer.fromMap(
        Map<String, dynamic>.from(map['peer'] as Map? ?? const {}),
      ),
      caller: TurnaCallPeer.fromMap(
        Map<String, dynamic>.from(map['caller'] as Map? ?? const {}),
      ),
      callee: TurnaCallPeer.fromMap(
        Map<String, dynamic>.from(map['callee'] as Map? ?? const {}),
      ),
    );
  }
}

class TurnaCallHistoryItem {
  TurnaCallHistoryItem({
    required this.id,
    required this.type,
    required this.status,
    required this.direction,
    required this.peer,
    this.createdAt,
    this.acceptedAt,
    this.endedAt,
    this.durationSeconds,
  });

  final String id;
  final TurnaCallType type;
  final TurnaCallStatus status;
  final String direction;
  final String? createdAt;
  final String? acceptedAt;
  final String? endedAt;
  final int? durationSeconds;
  final TurnaCallPeer peer;

  factory TurnaCallHistoryItem.fromMap(Map<String, dynamic> map) {
    return TurnaCallHistoryItem(
      id: (map['id'] ?? '').toString(),
      type: ((map['type'] ?? '').toString().toLowerCase() == 'video')
          ? TurnaCallType.video
          : TurnaCallType.audio,
      status: switch ((map['status'] ?? '').toString().toLowerCase()) {
        'accepted' => TurnaCallStatus.accepted,
        'declined' => TurnaCallStatus.declined,
        'missed' => TurnaCallStatus.missed,
        'ended' => TurnaCallStatus.ended,
        'cancelled' => TurnaCallStatus.cancelled,
        _ => TurnaCallStatus.ringing,
      },
      direction: (map['direction'] ?? 'outgoing').toString(),
      createdAt: _turnaCallNullableString(map['createdAt']),
      acceptedAt: _turnaCallNullableString(map['acceptedAt']),
      endedAt: _turnaCallNullableString(map['endedAt']),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt(),
      peer: TurnaCallPeer.fromMap(
        Map<String, dynamic>.from(map['peer'] as Map? ?? const {}),
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'status': status.name,
      'direction': direction,
      'createdAt': createdAt,
      'acceptedAt': acceptedAt,
      'endedAt': endedAt,
      'durationSeconds': durationSeconds,
      'peer': peer.toMap(),
    };
  }
}

class TurnaCallConnectPayload {
  TurnaCallConnectPayload({
    required this.provider,
    required this.url,
    required this.roomName,
    required this.token,
    required this.callId,
    required this.type,
  });

  final String provider;
  final String url;
  final String roomName;
  final String token;
  final String callId;
  final TurnaCallType type;

  factory TurnaCallConnectPayload.fromMap(Map<String, dynamic> map) {
    return TurnaCallConnectPayload(
      provider: (map['provider'] ?? '').toString(),
      url: (map['url'] ?? '').toString(),
      roomName: (map['roomName'] ?? '').toString(),
      token: (map['token'] ?? '').toString(),
      callId: (map['callId'] ?? '').toString(),
      type: ((map['type'] ?? '').toString().toLowerCase() == 'video')
          ? TurnaCallType.video
          : TurnaCallType.audio,
    );
  }
}

class TurnaGroupCallState {
  TurnaGroupCallState({
    required this.chatId,
    required this.roomName,
    required this.type,
    required this.startedByUserId,
    this.microphonePolicy = 'EVERYONE',
    this.cameraPolicy = 'EVERYONE',
    this.startedByDisplayName,
    this.startedAt,
    this.participantCount = 0,
    this.canStart = false,
  });

  final String chatId;
  final String roomName;
  final TurnaCallType type;
  final String startedByUserId;
  final String microphonePolicy;
  final String cameraPolicy;
  final String? startedByDisplayName;
  final String? startedAt;
  final int participantCount;
  final bool canStart;

  factory TurnaGroupCallState.fromMap(Map<String, dynamic> map) {
    return TurnaGroupCallState(
      chatId: (map['chatId'] ?? '').toString(),
      roomName: (map['roomName'] ?? '').toString(),
      type: ((map['type'] ?? '').toString().toLowerCase() == 'video')
          ? TurnaCallType.video
          : TurnaCallType.audio,
      startedByUserId: (map['startedByUserId'] ?? '').toString(),
      microphonePolicy:
          _turnaCallNullableString(map['microphonePolicy']) ?? 'EVERYONE',
      cameraPolicy: _turnaCallNullableString(map['cameraPolicy']) ?? 'EVERYONE',
      startedByDisplayName: _turnaCallNullableString(
        map['startedByDisplayName'],
      ),
      startedAt: _turnaCallNullableString(map['startedAt']),
      participantCount: (map['participantCount'] as num?)?.toInt() ?? 0,
      canStart: map['canStart'] == true,
    );
  }
}

class TurnaGroupCallJoinResult {
  TurnaGroupCallJoinResult({required this.state, required this.connect});

  final TurnaGroupCallState? state;
  final TurnaCallConnectPayload connect;

  factory TurnaGroupCallJoinResult.fromMap(Map<String, dynamic> map) {
    final rawState = map['state'] as Map?;
    return TurnaGroupCallJoinResult(
      state: rawState == null
          ? null
          : TurnaGroupCallState.fromMap(Map<String, dynamic>.from(rawState)),
      connect: TurnaCallConnectPayload.fromMap(
        Map<String, dynamic>.from(map['connect'] as Map? ?? const {}),
      ),
    );
  }
}

class TurnaAcceptedCallEvent {
  TurnaAcceptedCallEvent({required this.call, required this.connect});

  final TurnaCallSummary call;
  final TurnaCallConnectPayload connect;

  factory TurnaAcceptedCallEvent.fromMap(Map<String, dynamic> map) {
    return TurnaAcceptedCallEvent(
      call: TurnaCallSummary.fromMap(
        Map<String, dynamic>.from(map['call'] as Map? ?? const {}),
      ),
      connect: TurnaCallConnectPayload.fromMap(
        Map<String, dynamic>.from(map['connect'] as Map? ?? const {}),
      ),
    );
  }
}

class TurnaIncomingCallEvent {
  TurnaIncomingCallEvent({required this.call});

  final TurnaCallSummary call;

  factory TurnaIncomingCallEvent.fromMap(Map<String, dynamic> map) {
    return TurnaIncomingCallEvent(
      call: TurnaCallSummary.fromMap(
        Map<String, dynamic>.from(map['call'] as Map? ?? const {}),
      ),
    );
  }
}

class TurnaTerminalCallEvent {
  TurnaTerminalCallEvent({required this.kind, required this.call});

  final String kind;
  final TurnaCallSummary call;

  factory TurnaTerminalCallEvent.fromMap(
    String kind,
    Map<String, dynamic> map,
  ) {
    return TurnaTerminalCallEvent(
      kind: kind,
      call: TurnaCallSummary.fromMap(
        Map<String, dynamic>.from(map['call'] as Map? ?? const {}),
      ),
    );
  }
}

class TurnaCallVideoUpgradeRequestEvent {
  TurnaCallVideoUpgradeRequestEvent({
    required this.call,
    required this.requestId,
    required this.requestedByUserId,
  });

  final TurnaCallSummary call;
  final String requestId;
  final String requestedByUserId;

  factory TurnaCallVideoUpgradeRequestEvent.fromMap(Map<String, dynamic> map) {
    return TurnaCallVideoUpgradeRequestEvent(
      call: TurnaCallSummary.fromMap(
        Map<String, dynamic>.from(map['call'] as Map? ?? const {}),
      ),
      requestId: (map['requestId'] ?? '').toString(),
      requestedByUserId: (map['requestedByUserId'] ?? '').toString(),
    );
  }
}

class TurnaCallVideoUpgradeResolutionEvent {
  TurnaCallVideoUpgradeResolutionEvent({
    required this.kind,
    required this.call,
    required this.requestId,
    required this.actedByUserId,
  });

  final String kind;
  final TurnaCallSummary call;
  final String requestId;
  final String actedByUserId;

  factory TurnaCallVideoUpgradeResolutionEvent.fromMap(
    String kind,
    Map<String, dynamic> map,
  ) {
    return TurnaCallVideoUpgradeResolutionEvent(
      kind: kind,
      call: TurnaCallSummary.fromMap(
        Map<String, dynamic>.from(map['call'] as Map? ?? const {}),
      ),
      requestId: (map['requestId'] ?? '').toString(),
      actedByUserId: (map['actedByUserId'] ?? '').toString(),
    );
  }
}

class TurnaCallCoordinator extends ChangeNotifier {
  TurnaIncomingCallEvent? _pendingIncoming;
  final Map<String, TurnaAcceptedCallEvent> _acceptedEvents = {};
  final Map<String, TurnaTerminalCallEvent> _terminalEvents = {};
  final Map<String, TurnaCallVideoUpgradeRequestEvent> _videoUpgradeRequests =
      {};
  final Map<String, TurnaCallVideoUpgradeResolutionEvent>
  _videoUpgradeResolutions = {};

  void handleIncoming(Map<String, dynamic> payload) {
    _pendingIncoming = TurnaIncomingCallEvent.fromMap(payload);
    notifyListeners();
  }

  void handleAccepted(Map<String, dynamic> payload) {
    final event = TurnaAcceptedCallEvent.fromMap(payload);
    _acceptedEvents[event.call.id] = event;
    notifyListeners();
  }

  void handleDeclined(Map<String, dynamic> payload) {
    final event = TurnaTerminalCallEvent.fromMap('declined', payload);
    _terminalEvents[event.call.id] = event;
    notifyListeners();
  }

  void handleMissed(Map<String, dynamic> payload) {
    final event = TurnaTerminalCallEvent.fromMap('missed', payload);
    _terminalEvents[event.call.id] = event;
    notifyListeners();
  }

  void handleEnded(Map<String, dynamic> payload) {
    final event = TurnaTerminalCallEvent.fromMap('ended', payload);
    _terminalEvents[event.call.id] = event;
    notifyListeners();
  }

  void handleVideoUpgradeRequested(Map<String, dynamic> payload) {
    final event = TurnaCallVideoUpgradeRequestEvent.fromMap(payload);
    _videoUpgradeRequests[event.call.id] = event;
    notifyListeners();
  }

  void handleVideoUpgradeAccepted(Map<String, dynamic> payload) {
    final event = TurnaCallVideoUpgradeResolutionEvent.fromMap(
      'accepted',
      payload,
    );
    _videoUpgradeResolutions[event.call.id] = event;
    notifyListeners();
  }

  void handleVideoUpgradeDeclined(Map<String, dynamic> payload) {
    final event = TurnaCallVideoUpgradeResolutionEvent.fromMap(
      'declined',
      payload,
    );
    _videoUpgradeResolutions[event.call.id] = event;
    notifyListeners();
  }

  TurnaIncomingCallEvent? takeIncomingCall() {
    final event = _pendingIncoming;
    _pendingIncoming = null;
    return event;
  }

  TurnaAcceptedCallEvent? consumeAccepted(String callId) {
    return _acceptedEvents.remove(callId);
  }

  TurnaTerminalCallEvent? consumeTerminal(String callId) {
    return _terminalEvents.remove(callId);
  }

  TurnaCallVideoUpgradeRequestEvent? consumeVideoUpgradeRequest(String callId) {
    return _videoUpgradeRequests.remove(callId);
  }

  TurnaCallVideoUpgradeResolutionEvent? consumeVideoUpgradeResolution(
    String callId,
  ) {
    return _videoUpgradeResolutions.remove(callId);
  }

  void clearCall(String callId) {
    if (_pendingIncoming?.call.id == callId) {
      _pendingIncoming = null;
    }
    _acceptedEvents.remove(callId);
    _terminalEvents.remove(callId);
    _videoUpgradeRequests.remove(callId);
    _videoUpgradeResolutions.remove(callId);
  }
}
