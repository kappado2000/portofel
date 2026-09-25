class Profile {
  final String id;
  String name;
  String pinHash;
  String? securityAnswerHash;
  bool biometricEnabled;

  Profile({
    required this.id,
    required this.name,
    required this.pinHash,
    this.securityAnswerHash,
    this.biometricEnabled = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'pinHash': pinHash,
        'securityAnswerHash': securityAnswerHash,
        'biometricEnabled': biometricEnabled,
      };

  factory Profile.fromMap(Map map) => Profile(
        id: map['id'] as String,
        name: map['name'] as String,
        pinHash: map['pinHash'] as String,
        securityAnswerHash: map['securityAnswerHash'] as String?,
        biometricEnabled: map['biometricEnabled'] as bool? ?? false,
      );
}
