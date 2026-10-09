import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/bill.dart';
import '../services/bill_http.dart';
import '../services/eon_api.dart';
import '../services/hidroelectrica_api.dart';

/// Cere utilizatorului codul de verificare trimis de E.ON. Întoarce `null`
/// dacă utilizatorul renunță.
typedef MfaCodePrompt = Future<String?> Function(EonMfaRequired challenge);

/// Facturile de utilități ale profilului activ. Facturile stau într-o cutie
/// Hive per profil; datele de logare la furnizori stau în stocarea securizată
/// a sistemului (Keychain / Keystore), nu în Hive.
class BillsProvider extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();

  Box? _billsBox;
  Box? _metaBox;
  String? _profileId;

  List<Bill> _bills = [];
  final Map<BillProvider, String> _usernames = {};
  final Map<BillProvider, String> _errors = {};
  final Set<String> _hidden = {};
  bool _refreshing = false;

  bool get refreshing => _refreshing;
  bool get hasAnyAccount => _usernames.isNotEmpty;
  bool isConnected(BillProvider p) => _usernames.containsKey(p);
  String? usernameFor(BillProvider p) => _usernames[p];
  String? errorFor(BillProvider p) => _errors[p];

  DateTime? lastUpdated(BillProvider p) {
    final v = _metaBox?.get('updated_${p.name}');
    return v is String ? DateTime.tryParse(v) : null;
  }

  Iterable<Bill> get _active => _bills.where(
    (b) =>
        !b.archived && !_hidden.contains(_locKey(b.provider, b.contractCode)),
  );

  static String _locKey(BillProvider p, String code) => '${p.name}|$code';

  /// Locurile de consum cunoscute ale unui furnizor, ca (cod, adresă).
  List<(String, String)> locationsFor(BillProvider p) {
    final raw = _metaBox?.get('locations_${p.name}');
    final map = raw is Map ? raw : const {};
    final list = [for (final e in map.entries) ('${e.key}', '${e.value}')];
    list.sort((a, b) => a.$2.compareTo(b.$2));
    return list;
  }

  bool isLocationVisible(BillProvider p, String code) =>
      !_hidden.contains(_locKey(p, code));

  bool get hasHiddenLocations => _hidden.isNotEmpty;

  /// Stabilește exact ce locuri de consum rămân ascunse (chei din
  /// [locationKey]). O mulțime goală le afișează pe toate.
  Future<void> setHiddenLocations(Set<String> hidden) async {
    _hidden
      ..clear()
      ..addAll(hidden);
    await _metaBox?.put('hidden_locations', _hidden.toList());
    notifyListeners();
  }

  Set<String> get hiddenLocations => Set.of(_hidden);

  static String locationKey(BillProvider p, String code) => _locKey(p, code);

  Set<String> _skipFor(BillProvider p) => {
    for (final key in _hidden)
      if (key.startsWith('${p.name}|')) key.substring(p.name.length + 1),
  };

  /// Facturile salvate în istoric, cele mai recent achitate primele — doar
  /// ale adreselor alese pentru afișare, la fel ca lista de facturi.
  List<Bill> get archivedBills {
    final list = _bills
        .where(
          (b) =>
              b.archived &&
              !_hidden.contains(_locKey(b.provider, b.contractCode)),
        )
        .toList();
    list.sort(
      (a, b) => (b.paidAt ?? b.fetchedAt).compareTo(a.paidAt ?? a.fetchedAt),
    );
    return list;
  }

  /// Facturile unui furnizor: întâi cele nebifate, apoi după scadență.
  List<Bill> billsFor(BillProvider p) {
    final list = _active.where((b) => b.provider == p).toList();
    list.sort((a, b) {
      if (a.paid != b.paid) return a.paid ? 1 : -1;
      final ad = a.dueDate ?? DateTime(9999);
      final bd = b.dueDate ?? DateTime(9999);
      return ad.compareTo(bd);
    });
    return list;
  }

  double _sum(Iterable<Bill> bills) => bills.fold(0, (s, b) => s + b.balance);

  /// Totalul facturilor nebifate și încă neachitate la furnizor
  /// (opțional, doar ale unui furnizor).
  double unpaidTotal([BillProvider? p]) => _sum(
    _active.where(
      (b) => !b.paid && b.openAtProvider && (p == null || b.provider == p),
    ),
  );

  /// Pentru fiecare loc de consum al unui furnizor, data de emitere a
  /// ultimei facturi salvate în istoric: de acolo încolo se afișează toate
  /// facturile, nu doar cele neachitate.
  Map<String, DateTime> _sinceFor(BillProvider p) {
    final since = <String, DateTime>{};
    for (final b in _bills.where((b) => b.archived && b.provider == p)) {
      final date = b.issueDate ?? b.dueDate;
      if (date == null) continue;
      final current = since[b.contractCode];
      if (current == null || date.isAfter(current)) {
        since[b.contractCode] = date;
      }
    }
    return since;
  }

  /// Totalul facturilor bifate (opțional, doar ale unui furnizor).
  double paidTotal([BillProvider? p]) =>
      _sum(_active.where((b) => b.paid && (p == null || b.provider == p)));

  int get paidCount => _active.where((b) => b.paid).length;

  String _credKey(BillProvider p) => 'bills_${_profileId}_${p.name}';
  String get _eonSessionKey => 'bills_${_profileId}_eon_session';

  Future<void> loadProfile(String profileId) async {
    if (_profileId == profileId) return;
    await _billsBox?.close();
    await _metaBox?.close();
    _billsBox = await Hive.openBox('bills_$profileId');
    _metaBox = await Hive.openBox('bills_meta_$profileId');
    _profileId = profileId;
    _bills = _billsBox!.values.map((m) => Bill.fromMap(Map.from(m))).toList();
    _hidden
      ..clear()
      ..addAll(
        (_metaBox!.get('hidden_locations') as List? ?? []).map((e) => '$e'),
      );
    _usernames.clear();
    _errors.clear();
    for (final p in BillProvider.values) {
      final creds = await _readCreds(p);
      if (creds != null) _usernames[p] = creds.$1;
    }
    notifyListeners();
  }

  Future<(String, String)?> _readCreds(BillProvider p) async {
    try {
      final raw = await _storage.read(key: _credKey(p));
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map;
      return ('${map['u']}', '${map['p']}');
    } catch (_) {
      return null;
    }
  }

  /// Parola salvată pentru un furnizor, pentru precompletarea formularului.
  Future<String?> passwordFor(BillProvider p) async =>
      (await _readCreds(p))?.$2;

  Future<void> saveAccount(
    BillProvider p,
    String username,
    String password,
  ) async {
    await _storage.write(
      key: _credKey(p),
      value: jsonEncode({'u': username.trim(), 'p': password}),
    );
    if (p == BillProvider.eon) await _storage.delete(key: _eonSessionKey);
    _usernames[p] = username.trim();
    _errors.remove(p);
    notifyListeners();
  }

  /// Deconectează furnizorul și șterge facturile lui nebifate.
  Future<void> removeAccount(BillProvider p) async {
    await _storage.delete(key: _credKey(p));
    if (p == BillProvider.eon) await _storage.delete(key: _eonSessionKey);
    _usernames.remove(p);
    _errors.remove(p);
    final gone = _bills.where((b) => b.provider == p && !b.paid).toList();
    for (final b in gone) {
      _bills.remove(b);
      await _billsBox?.delete(b.id);
    }
    await _metaBox?.delete('updated_${p.name}');
    await _metaBox?.delete('locations_${p.name}');
    _hidden.removeWhere((k) => k.startsWith('${p.name}|'));
    await _metaBox?.put('hidden_locations', _hidden.toList());
    notifyListeners();
  }

  /// Actualizează facturile de la toți furnizorii conectați. Erorile sunt
  /// reținute per furnizor (vezi [errorFor]) — un furnizor căzut nu îl
  /// blochează pe celălalt.
  Future<void> refresh({required MfaCodePrompt askMfaCode}) async {
    if (_refreshing || _profileId == null) return;
    _refreshing = true;
    _errors.clear();
    notifyListeners();
    try {
      for (final p in BillProvider.values) {
        final creds = await _readCreds(p);
        if (creds == null) continue;
        try {
          final fetched = p == BillProvider.hidroelectrica
              ? await _fetchHidro(creds)
              : await _fetchEon(creds, askMfaCode);
          if (fetched == null) {
            _errors[p] = 'Actualizare anulată: lipsește codul de verificare.';
            continue;
          }
          await _merge(p, fetched.$1);
          if (fetched.$2.isNotEmpty) {
            await _metaBox?.put('locations_${p.name}', fetched.$2);
          }
          await _metaBox?.put(
            'updated_${p.name}',
            DateTime.now().toIso8601String(),
          );
        } on BillFetchException catch (e) {
          _errors[p] = e.message;
        } catch (_) {
          _errors[p] =
              '${billProviderLabel(p)}: răspuns neașteptat de la furnizor.';
        }
        notifyListeners();
      }
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  Future<(List<Bill>, Map<String, String>)> _fetchHidro(
    (String, String) creds,
  ) async {
    final api = HidroelectricaApi();
    try {
      await api.login(creds.$1, creds.$2);
      final bills = await api.fetchOpenBills(
        since: _sinceFor(BillProvider.hidroelectrica),
        skip: _skipFor(BillProvider.hidroelectrica),
      );
      return (bills, api.locations);
    } finally {
      api.close();
    }
  }

  /// Deschide o sesiune E.ON (cea salvată, sau logare cu cod de verificare
  /// dacă e cazul), rulează [action] și salvează sesiunea. Întoarce `null`
  /// dacă utilizatorul renunță la introducerea codului.
  Future<T?> _withEon<T>(
    (String, String) creds,
    MfaCodePrompt askMfaCode,
    Future<T> Function(EonApi api) action,
  ) async {
    final api = EonApi();
    try {
      try {
        final raw = await _storage.read(key: _eonSessionKey);
        if (raw != null) {
          api.restoreSession(Map<String, dynamic>.from(jsonDecode(raw) as Map));
        }
      } catch (_) {
        // Sesiune salvată coruptă: se face logare completă.
      }
      T result;
      try {
        result = await action(api);
      } on EonMfaRequired catch (challenge) {
        final code = await askMfaCode(challenge);
        if (code == null || code.trim().isEmpty) return null;
        await api.completeMfa(challenge.uuid, code);
        result = await action(api);
      }
      final session = api.exportSession();
      if (session != null) {
        await _storage.write(key: _eonSessionKey, value: jsonEncode(session));
      }
      return result;
    } finally {
      api.close();
    }
  }

  Future<(List<Bill>, Map<String, String>)?> _fetchEon(
    (String, String) creds,
    MfaCodePrompt askMfaCode,
  ) {
    final since = _sinceFor(BillProvider.eon);
    final skip = _skipFor(BillProvider.eon);
    return _withEon(creds, askMfaCode, (api) async {
      final bills = await api.fetchOpenBills(
        creds.$1,
        creds.$2,
        since: since,
        skip: skip,
      );
      return (bills, api.locations);
    });
  }

  /// Descarcă PDF-ul unei facturi de la furnizor. Aruncă
  /// [BillFetchException] cu un mesaj afișabil dacă nu se poate.
  Future<Uint8List> fetchPdf(
    Bill bill, {
    required MfaCodePrompt askMfaCode,
  }) async {
    final creds = await _readCreds(bill.provider);
    final name = billProviderLabel(bill.provider);
    if (creds == null) {
      throw BillFetchException('Contul $name nu mai este conectat.');
    }
    Uint8List? pdf;
    if (bill.provider == BillProvider.hidroelectrica) {
      // Hidroelectrica oferă doar PDF-ul facturii curente a locului de
      // consum; pentru una mai veche s-ar deschide alt document.
      final issued = bill.issueDate;
      final hasNewer = _bills.any(
        (b) =>
            b.provider == bill.provider &&
            b.contractCode == bill.contractCode &&
            b.id != bill.id &&
            issued != null &&
            (b.issueDate?.isAfter(issued) ?? false),
      );
      if (hasNewer) {
        throw BillFetchException(
          'Hidroelectrica oferă doar PDF-ul celei mai recente facturi.',
        );
      }
      final api = HidroelectricaApi();
      try {
        await api.login(creds.$1, creds.$2);
        pdf = await api.fetchCurrentBillPdf(bill.contractCode);
      } finally {
        api.close();
      }
    } else {
      if (bill.invoiceNumber.isEmpty) {
        throw BillFetchException('Factura nu are număr, nu poate fi deschisă.');
      }
      pdf = await _withEon<Uint8List?>(
        creds,
        askMfaCode,
        (api) => api.fetchInvoicePdf(bill.invoiceNumber, creds.$1, creds.$2),
      );
    }
    if (pdf == null) {
      throw BillFetchException('$name nu a oferit PDF-ul acestei facturi.');
    }
    return pdf;
  }

  Future<void> _merge(BillProvider p, List<Bill> fetched) async {
    final fetchedIds = <String>{};
    for (final f in fetched) {
      fetchedIds.add(f.id);
      final existing = _bills.where((b) => b.id == f.id).firstOrNull;
      if (existing == null) {
        _bills.add(f);
        await _billsBox?.put(f.id, f.toMap());
      } else if (!existing.archived) {
        existing
          ..amount = f.amount
          ..balance = f.balance
          ..address = f.address
          ..issueDate = f.issueDate ?? existing.issueDate
          ..dueDate = f.dueDate ?? existing.dueDate
          ..indexFrom = f.indexFrom ?? existing.indexFrom
          ..indexTo = f.indexTo ?? existing.indexTo
          ..readingType = f.readingType.isEmpty
              ? existing.readingType
              : f.readingType
          ..indexPeriod = f.indexPeriod.isEmpty
              ? existing.indexPeriod
              : f.indexPeriod
          ..fetchedAt = f.fetchedAt
          ..openAtProvider = f.openAtProvider;
        await _billsBox?.put(existing.id, existing.toMap());
      }
    }
    // Facturile care nu mai apar la furnizor ca neachitate rămân în listă,
    // marcate ca achitate la furnizor, până sunt bifate și salvate în istoric.
    for (final b in _bills.where(
      (b) =>
          b.provider == p &&
          !b.archived &&
          b.openAtProvider &&
          !_hidden.contains(_locKey(b.provider, b.contractCode)) &&
          !fetchedIds.contains(b.id),
    )) {
      b.openAtProvider = false;
      await _billsBox?.put(b.id, b.toMap());
    }
  }

  Future<void> setPaid(Bill bill, bool paid) async {
    bill
      ..paid = paid
      ..paidAt = paid ? DateTime.now() : null;
    await _billsBox?.put(bill.id, bill.toMap());
    notifyListeners();
  }

  /// Bifează sau debifează toate facturile unui furnizor.
  Future<void> setSectionPaid(BillProvider p, bool paid) async {
    final now = DateTime.now();
    for (final b in _active.where((b) => b.provider == p && b.paid != paid)) {
      b
        ..paid = paid
        ..paidAt = paid ? now : null;
      await _billsBox?.put(b.id, b.toMap());
    }
    notifyListeners();
  }

  /// Șterge din listă toate facturile bifate (fără a le salva în istoric).
  Future<void> removePaid() async {
    final gone = _active.where((b) => b.paid).toList();
    for (final b in gone) {
      _bills.remove(b);
      await _billsBox?.delete(b.id);
    }
    notifyListeners();
  }

  /// Mută facturile bifate în istoric. Data achitării este data salvării
  /// în istoric, nu cea la care a fost pusă bifa.
  Future<void> archivePaid() async {
    final now = DateTime.now();
    for (final b in _active.where((b) => b.paid).toList()) {
      b
        ..archived = true
        ..paidAt = now;
      await _billsBox?.put(b.id, b.toMap());
    }
    notifyListeners();
  }

  /// Întoarce o factură din istoric în lista de facturi, nebifată (ca și
  /// cum nu ar fi fost achitată).
  Future<void> restoreFromHistory(Bill bill) async {
    bill
      ..archived = false
      ..paid = false
      ..paidAt = null;
    await _billsBox?.put(bill.id, bill.toMap());
    notifyListeners();
  }

  Future<void> deleteFromHistory(Bill bill) async {
    _bills.remove(bill);
    await _billsBox?.delete(bill.id);
    notifyListeners();
  }
}
