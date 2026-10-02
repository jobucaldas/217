class User {
  const User({
    required this.id,
    required this.email,
    required this.name,
    this.role = 'owner',
  });

  final String id;
  final String email;
  final String name;
  final String role;

  bool get isOwner => role != 'partner';
  bool get isPartner => role == 'partner';

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      name: (json['name'] as String?) ?? '',
      role: (json['role'] as String?) ?? 'owner',
    );
  }
}

class ShareState {
  const ShareState({
    required this.status,
    this.inviteCode = '',
    this.inviteUrl = '',
    this.partnerEmail = '',
    this.partnerName = '',
    this.ownerName = '',
    this.ownerEmail = '',
    this.canEditCalendar = true,
    this.unreadNotes = 0,
  });

  final String status;
  final String inviteCode;

  /// Web link that opens the app with this invite (`/?invite=CODE`).
  final String inviteUrl;
  final String partnerEmail;
  final String partnerName;
  final String ownerName;
  final String ownerEmail;
  final bool canEditCalendar;
  final int unreadNotes;

  bool get isNone => status == 'none' || status.isEmpty;
  bool get isOpen => status == 'open';
  bool get isActive => status == 'active';
  bool get isRevoked => status == 'revoked';

  factory ShareState.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const ShareState(status: 'none');
    }
    return ShareState(
      status: (json['status'] as String?) ?? 'none',
      inviteCode: (json['invite_code'] as String?) ?? '',
      inviteUrl: (json['invite_url'] as String?) ?? '',
      partnerEmail: (json['partner_email'] as String?) ?? '',
      partnerName: (json['partner_name'] as String?) ?? '',
      ownerName: (json['owner_name'] as String?) ?? '',
      ownerEmail: (json['owner_email'] as String?) ?? '',
      canEditCalendar: json['can_edit_calendar'] as bool? ?? true,
      unreadNotes: json['unread_notes'] as int? ?? 0,
    );
  }
}

class SessionSnapshot {
  const SessionSnapshot({this.user, this.share});

  final User? user;
  final ShareState? share;

  factory SessionSnapshot.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'];
    return SessionSnapshot(
      user: userJson == null
          ? null
          : User.fromJson(userJson as Map<String, dynamic>),
      share: ShareState.fromJson(json['share'] as Map<String, dynamic>?),
    );
  }
}

class PartnerNote {
  const PartnerNote({
    required this.id,
    required this.body,
    required this.createdAt,
    this.fromName = '',
    this.fromEmail = '',
    this.readAt,
  });

  final String id;
  final String body;
  final DateTime createdAt;
  final String fromName;
  final String fromEmail;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  factory PartnerNote.fromJson(Map<String, dynamic> json) {
    return PartnerNote(
      id: json['id'] as String,
      body: (json['body'] as String?) ?? '',
      createdAt: DateTime.tryParse((json['created_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      fromName: (json['from_name'] as String?) ?? '',
      fromEmail: (json['from_email'] as String?) ?? '',
      readAt: json['read_at'] == null
          ? null
          : DateTime.tryParse(json['read_at'] as String),
    );
  }
}

class Entry {
  const Entry({
    required this.date,
    required this.taken,
    required this.notes,
    this.heart = false,
  });

  final String date;
  /// Null means Em aberto (no Taken/Missed yet); entry may still hold note/heart.
  final bool? taken;
  final String notes;
  final bool heart;

  factory Entry.fromJson(Map<String, dynamic> json) {
    return Entry(
      date: json['date'] as String,
      taken: json['taken'] as bool?,
      notes: (json['notes'] as String?) ?? '',
      heart: json['heart'] as bool? ?? false,
    );
  }
}

class ReminderPreference {
  const ReminderPreference({
    required this.enabled,
    required this.time,
    required this.timezone,
    required this.deliverable,
  });

  final bool enabled;
  final String time;
  final String timezone;
  final bool deliverable;

  factory ReminderPreference.fromJson(Map<String, dynamic> json) {
    return ReminderPreference(
      enabled: json['enabled'] as bool? ?? false,
      time: (json['time'] as String?) ?? '09:00',
      timezone: (json['timezone'] as String?) ?? 'UTC',
      deliverable: json['deliverable'] as bool? ?? false,
    );
  }
}
