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

  /// Takes the pill and fills the calendar.
  bool get isOwner => role == 'owner';

  /// Follows the owner's calendar, read-only.
  bool get isPartner => role == 'partner';

  /// False until the user picks owner or partner after first sign-in.
  bool get hasRole => isOwner || isPartner;

  User withRole(String next) =>
      User(id: id, email: email, name: name, role: next);

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      name: (json['name'] as String?) ?? '',
      role: (json['role'] as String?) ?? '',
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
    this.period = false,
  });

  final String date;
  /// Null means Em aberto (no Taken/Missed yet); entry may still hold note/heart.
  final bool? taken;
  final String notes;
  final bool heart;

  /// Logged as a period day (drives cycle and PMS predictions).
  final bool period;

  factory Entry.fromJson(Map<String, dynamic> json) {
    return Entry(
      date: json['date'] as String,
      taken: json['taken'] as bool?,
      notes: (json['notes'] as String?) ?? '',
      heart: json['heart'] as bool? ?? false,
      period: json['period'] as bool? ?? false,
    );
  }
}

/// One predicted period and the PMS days just before it (inclusive dates).
class CycleWindow {
  const CycleWindow({
    required this.periodStart,
    required this.periodEnd,
    required this.pmsStart,
    required this.pmsEnd,
  });

  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime pmsStart;
  final DateTime pmsEnd;

  static DateTime _day(Object? raw) {
    final parsed = DateTime.parse(raw as String);
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  factory CycleWindow.fromJson(Map<String, dynamic> json) => CycleWindow(
        periodStart: _day(json['period_start']),
        periodEnd: _day(json['period_end']),
        pmsStart: _day(json['pms_start']),
        pmsEnd: _day(json['pms_end']),
      );
}

/// Day kinds the calendar draws from cycle predictions.
enum CycleDayKind { none, pms, predictedPeriod }

/// Logged period starts plus the next predicted periods / PMS windows.
class CycleInfo {
  const CycleInfo({
    this.cycleLength = 28,
    this.periodLength = 5,
    this.estimated = true,
    this.periodStarts = const [],
    this.predictions = const [],
  });

  static const empty = CycleInfo();

  final int cycleLength;
  final int periodLength;

  /// True while fewer than two periods are logged (default cycle length).
  final bool estimated;
  final List<DateTime> periodStarts;
  final List<CycleWindow> predictions;

  bool get hasPredictions => predictions.isNotEmpty;

  static bool _within(DateTime day, DateTime from, DateTime to) =>
      !day.isBefore(from) && !day.isAfter(to);

  /// What [day] is in the predictions (logged period days are drawn from entries).
  CycleDayKind kindOf(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    for (final w in predictions) {
      if (_within(d, w.pmsStart, w.pmsEnd)) return CycleDayKind.pms;
      if (_within(d, w.periodStart, w.periodEnd)) {
        return CycleDayKind.predictedPeriod;
      }
    }
    return CycleDayKind.none;
  }

  /// First prediction whose period has not ended by [today].
  CycleWindow? nextWindow(DateTime today) {
    final d = DateTime(today.year, today.month, today.day);
    for (final w in predictions) {
      if (!w.periodEnd.isBefore(d)) return w;
    }
    return null;
  }

  factory CycleInfo.fromJson(Map<String, dynamic> json) => CycleInfo(
        cycleLength: json['cycle_length'] as int? ?? 28,
        periodLength: json['period_length'] as int? ?? 5,
        estimated: json['estimated'] as bool? ?? true,
        periodStarts: (json['period_starts'] as List<dynamic>? ?? const [])
            .map(CycleWindow._day)
            .toList(),
        predictions: (json['predictions'] as List<dynamic>? ?? const [])
            .map((e) => CycleWindow.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Partner notification choices; each alert has its own time (HH:MM).
class PartnerAlertPreference {
  const PartnerAlertPreference({
    this.pmsEnabled = false,
    this.pmsTime = '09:00',
    this.pillEnabled = false,
    this.pillTime = '21:00',
  });

  final bool pmsEnabled;
  final String pmsTime;
  final bool pillEnabled;
  final String pillTime;

  PartnerAlertPreference copyWith({
    bool? pmsEnabled,
    String? pmsTime,
    bool? pillEnabled,
    String? pillTime,
  }) =>
      PartnerAlertPreference(
        pmsEnabled: pmsEnabled ?? this.pmsEnabled,
        pmsTime: pmsTime ?? this.pmsTime,
        pillEnabled: pillEnabled ?? this.pillEnabled,
        pillTime: pillTime ?? this.pillTime,
      );

  Map<String, dynamic> toJson() => {
        'pms_enabled': pmsEnabled,
        'pms_time': pmsTime,
        'pill_enabled': pillEnabled,
        'pill_time': pillTime,
      };

  factory PartnerAlertPreference.fromJson(Map<String, dynamic> json) =>
      PartnerAlertPreference(
        pmsEnabled: json['pms_enabled'] as bool? ?? false,
        pmsTime: (json['pms_time'] as String?) ?? '09:00',
        pillEnabled: json['pill_enabled'] as bool? ?? false,
        pillTime: (json['pill_time'] as String?) ?? '21:00',
      );
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
