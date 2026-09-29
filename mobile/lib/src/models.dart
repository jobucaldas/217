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
