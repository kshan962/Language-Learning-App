class AccountToken {
  final String email;
  final String uid;
  final String token;
  final DateTime createdAt;

  AccountToken({
    required this.email,
    required this.uid,
    required this.token,
    required this.createdAt,
  });

  factory AccountToken.fromJson(Map<String, dynamic> json) {
    return AccountToken(
      email: json['email'] ?? '',
      uid: json['uid'] ?? '',
      token: json['token'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'uid': uid,
      'token': token,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
