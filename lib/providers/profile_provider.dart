import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/profile.dart';

/// Gestionează profilurile (persoanele) care pot folosi aplicația pe acest
/// dispozitiv. Fiecare profil are propriul PIN și propriile date (conturi,
/// tranzacții) complet separate — vezi [MoneyProvider.loadProfile].
class ProfileProvider extends ChangeNotifier {
  late Box _profilesBox;
  late Box _metaBox;
  final _uuid = const Uuid();

  List<Profile> _profiles = [];
  String? _activeProfileId;
  bool _isUnlocked = false;

  List<Profile> get profiles => List.unmodifiable(_profiles);
  String? get activeProfileId => _activeProfileId;
  bool get isUnlocked => _isUnlocked;

  Profile? get activeProfile {
    final id = _activeProfileId;
    if (id == null) return null;
    try {
      return _profiles.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  Profile? byId(String id) {
    try {
      return _profiles.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> init() async {
    await Hive.initFlutter();
    _profilesBox = await Hive.openBox('profiles');
    _metaBox = await Hive.openBox('app_meta');
    _profiles = _profilesBox.values.map((m) => Profile.fromMap(Map.from(m))).toList();
    _activeProfileId = _metaBox.get('activeProfileId') as String?;
    if (_activeProfileId != null && byId(_activeProfileId!) == null) {
      _activeProfileId = null;
    }
    notifyListeners();
  }

  String _hash(String value) =>
      sha256.convert(utf8.encode('portofel_salt::${value.trim().toLowerCase()}')).toString();

  Future<Profile> createProfile({required String name, required String pin}) async {
    final profile = Profile(
      id: _uuid.v4(),
      name: name,
      pinHash: _hash(pin),
    );
    _profiles.add(profile);
    await _profilesBox.put(profile.id, profile.toMap());
    notifyListeners();
    return profile;
  }

  Future<void> setSecurityAnswer(String profileId, String answer) async {
    final profile = byId(profileId);
    if (profile == null) return;
    profile.securityAnswerHash = _hash(answer);
    await _profilesBox.put(profile.id, profile.toMap());
    notifyListeners();
  }

  bool hasSecurityAnswer(String profileId) => byId(profileId)?.securityAnswerHash != null;

  bool verifyPin(String profileId, String pin) {
    final profile = byId(profileId);
    if (profile == null) return false;
    return profile.pinHash == _hash(pin);
  }

  bool verifySecurityAnswer(String profileId, String answer) {
    final profile = byId(profileId);
    if (profile?.securityAnswerHash == null) return false;
    return profile!.securityAnswerHash == _hash(answer);
  }

  Future<void> setPin(String profileId, String pin) async {
    final profile = byId(profileId);
    if (profile == null) return;
    profile.pinHash = _hash(pin);
    await _profilesBox.put(profile.id, profile.toMap());
    notifyListeners();
  }

  Future<void> renameProfile(String profileId, String name) async {
    final profile = byId(profileId);
    if (profile == null) return;
    profile.name = name;
    await _profilesBox.put(profile.id, profile.toMap());
    notifyListeners();
  }

  Future<void> setBiometricEnabled(String profileId, bool enabled) async {
    final profile = byId(profileId);
    if (profile == null) return;
    profile.biometricEnabled = enabled;
    await _profilesBox.put(profile.id, profile.toMap());
    notifyListeners();
  }

  /// Resetează PIN-ul unui profil (folosit după recuperare cu succes prin
  /// întrebarea de securitate) — nu atinge datele financiare ale profilului.
  Future<void> resetPinAfterRecovery(String profileId, String newPin) async {
    final profile = byId(profileId);
    if (profile == null) return;
    profile.pinHash = _hash(newPin);
    await _profilesBox.put(profile.id, profile.toMap());
    notifyListeners();
  }

  Future<void> setActiveProfile(String? id) async {
    _activeProfileId = id;
    if (id == null) {
      await _metaBox.delete('activeProfileId');
    } else {
      await _metaBox.put('activeProfileId', id);
    }
    notifyListeners();
  }

  void unlock() {
    _isUnlocked = true;
    notifyListeners();
  }

  /// Re-blochează aplicația păstrând profilul curent selectat (cere doar
  /// PIN-ul din nou la următoarea deschidere a ecranului de blocare).
  void lock() {
    _isUnlocked = false;
    notifyListeners();
  }

  /// Delogare completă: revine la selectorul de profiluri.
  Future<void> logout() async {
    _isUnlocked = false;
    await setActiveProfile(null);
  }

  // ---- Preferințe globale (indiferent de profil) ----

  ThemeMode get themeMode {
    final stored = _metaBox.get('themeMode') as String?;
    return switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _metaBox.put('themeMode', mode.name);
    notifyListeners();
  }
}
