class User {
  const User({required this.id, required this.email, required this.name});

  final String id;
  final String email;
  final String name;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      name: (json['name'] as String?) ?? '',
    );
  }
}

class Entry {
  const Entry({
    required this.date,
    required this.taken,
    required this.notes,
  });

  final String date;
  final bool taken;
  final String notes;

  factory Entry.fromJson(Map<String, dynamic> json) {
    return Entry(
      date: json['date'] as String,
      taken: json['taken'] as bool? ?? false,
      notes: (json['notes'] as String?) ?? '',
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

class AuthConfig {
  const AuthConfig({required this.authkit, required this.password});

  final bool authkit;
  final bool password;

  factory AuthConfig.fromJson(Map<String, dynamic> json) {
    return AuthConfig(
      authkit: json['authkit'] as bool? ?? false,
      password: json['password'] as bool? ?? false,
    );
  }
}
