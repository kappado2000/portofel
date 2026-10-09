import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/bill.dart';
import '../services/bill_http.dart';
import '../services/eon_api.dart';
import '../services/hidroelectrica_api.dart';

/// Cere utilizatorului codul de verificare trimis de E.ON pentru contul
/// [username]. Întoarce `null` dacă utilizatorul renunță.
typedef MfaCodePrompt = Future<String?> Function(
  EonMfaRequired challenge,
  String username,
);

/// Un cont de furnizor conectat. Parola nu se ține în memorie; se citește
/// din stocarea securizată doar când e nevoie.
class BillAccount {
  final String id;
  final BillProvider provider;
  final String username;

  const BillAccount(this.id, this.provider, this.username);
}

/// Facturile de utilități ale profilului activ. Facturile stau într-o cutie
/// Hive per profil; datele de logare la furnizori stau în stocarea securizată
/// a sistemului (Keychain / Keystore), nu în Hive.
class BillsProvider extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();

  Box? _billsBox;
  Box? _metaBox;
  String? _profileId;

  List<Bill> _bills = [];
  List<BillAccount> _accounts = [];
  final Map<String, String> _errors = {};
  final Set<String> _hidden = {};
  bool _refreshing = false;

  bool get refreshing => _refreshing;
  bool get hasAnyAccount => _accounts.isNotEmpty;
  List<BillAccount> get accounts => List.unmodifiable(_accounts);
  List<BillAccount> accountsFor(BillProvider p) =>
      _accounts.where((a) => a.provider == p).toList();
  bool isConnected(BillProvider p) => _accounts.any((a) => a.provider == p);

  /// Erorile ultimei actualizări pentru conturile unui furnizor. Când are
  /// mai multe conturi, fiecare mesaj începe cu utilizatorul contului.
  List<String> errorsFor(BillProvider p) {
    final list = accountsFor(p);
    return [
      for (final a in list)
        if (_errors[a.id] case final e?)
          list.length > 1 ? '${a.username}: $e' : e,
    ];
  }

  /// Momentul de când toate conturile furnizorului sunt la zi (cea mai
  /// veche actualizare dintre ele), sau `null` dacă vreunul nu a fost
  /// actualizat niciodată.
  DateTime? lastUpdated(BillProvider p) {
    DateTime? oldest;
    for (final a in accountsFor(p)) {
      final v = _metaBox?.get('updated_${a.id}');
      final d = v is String ? DateTime.tryParse(v) : null;
      if (d == null) return null;
      if (oldest == null || d.isBefore(oldest)) oldest = d;
    }
    return oldest;
  }

  Iterable<Bill> get _active => _bills.where(
    (b) =>
        !b.archived && !_hidden.contains(_locKey(b.provider, b.contractCode)),
  );

  static String _locKey(BillProvider p, String code) => '${p.name}|$code';

  /// Locurile de consum cunoscute ale unui furnizor, din toate conturile
  /// lui, ca (cod, adresă).
  List<(String, String)> locationsFor(BillProvider p) {
    final merged = <String, String>{};
    for (final a in accountsFor(p)) {
      final raw = _metaBox?.get('locations_${a.id}');
      if (raw is Map) raw.forEach((k, v) => merged['$k'] = '$v');
    }
    final list = [for (final e in merged.entries) (e.key, e.value)];
    list.sort((a, b) => a.$2.compareTo(b.$2));
    return list;
  }

  /// Adresele alese pentru afișare ale unui furnizor, ca (cod, adresă):
  /// cele cunoscute de la furnizor plus cele care apar doar pe facturi.
  List<(String, String)> visibleLocationsFor(BillProvider p) {
    final list = locationsFor(p)
        .where((l) => isLocationVisible(p, l.$1))
        .toList();
    final known = {for (final l in list) l.$1};
    for (final b in _active.where((b) => b.provider == p)) {
      if (known.add(b.contractCode)) list.add((b.contractCode, b.address));
    }
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

  /// Facturile se cer „emise după” această dată, deci cu o zi înainte de
  /// [startDate], ca ziua aleasă să fie inclusă.
  DateTime get _sinceDefault {
    final d = startDate;
    return DateTime(d.year, d.month, d.day).subtract(const Duration(days: 1));
  }

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

  double _sum(Iterable<Bill> bills) => bills.fold(0, (s, b) => s + b.amount);

  /// Data de la care se afișează facturile emise, pentru adresele care nu
  /// au încă nimic în istoric. Implicit, cu 60 de zile înainte de prima
  /// folosire.
  DateTime get startDate {
    final v = _metaBox?.get('start_date');
    return (v is String ? DateTime.tryParse(v) : null) ??
        DateTime.now().subtract(const Duration(days: 60));
  }

  Future<void> setStartDate(DateTime date) async {
    await _metaBox?.put('start_date', date.toIso8601String());
    notifyListeners();
  }

  /// Facturile restante la furnizor (neplătite acolo, cu scadența
  /// depășită), inclusiv cele bifate sau deja trecute în istoric.
  List<Bill> get overdueBills => _bills
      .where(
        (b) =>
            b.isOverdue &&
            !_hidden.contains(_locKey(b.provider, b.contractCode)),
      )
      .toList();

  /// Totalul facturilor nebifate (opțional, doar ale unui furnizor),
  /// indiferent dacă sunt sau nu plătite la furnizor.
  double unpaidTotal([BillProvider? p]) =>
      _sum(_active.where((b) => !b.paid && (p == null || b.provider == p)));

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

  String get _accountsKey => 'bills_${_profileId}_accounts';
  String _sessionKey(String accountId) =>
      'bills_${_profileId}_eon_session_$accountId';

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
    if (_metaBox!.get('start_date') == null) {
      await _metaBox!.put('start_date', startDate.toIso8601String());
    }
    _errors.clear();
    await _migrateSingleAccounts();
    _accounts = [
      for (final m in await _readAccounts())
        BillAccount('${m['id']}', _providerOf(m), '${m['u']}'),
    ];
    // Facturile salvate înainte de conturile multiple nu au cont: îl primesc
    // pe primul al furnizorului lor.
    for (final b in _bills.where((b) => b.accountId.isEmpty)) {
      final account = accountsFor(b.provider).firstOrNull;
      if (account == null) continue;
      b.accountId = account.id;
      await _billsBox!.put(b.id, b.toMap());
    }
    notifyListeners();
  }

  static BillProvider _providerOf(Map m) => BillProvider.values.firstWhere(
    (p) => p.name == m['provider'],
    orElse: () => BillProvider.hidroelectrica,
  );

  /// Conturile salvate, cu tot cu parolă: `{id, provider, u, p}`.
  Future<List<Map<String, dynamic>>> _readAccounts() async {
    try {
      final raw = await _storage.read(key: _accountsKey);
      if (raw == null) return [];
      return [
        for (final m in jsonDecode(raw) as List)
          Map<String, dynamic>.from(m as Map),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeAccounts(List<Map<String, dynamic>> list) =>
      _storage.write(key: _accountsKey, value: jsonEncode(list));

  /// Trece datele din vechea formă (un singur cont per furnizor) în lista
  /// de conturi. Rulează o singură dată.
  Future<void> _migrateSingleAccounts() async {
    if (await _storage.read(key: _accountsKey) != null) return;
    final list = <Map<String, dynamic>>[];
    for (final p in BillProvider.values) {
      final oldKey = 'bills_${_profileId}_${p.name}';
      try {
        final raw = await _storage.read(key: oldKey);
        if (raw == null) continue;
        final map = jsonDecode(raw) as Map;
        final id = 'main_${p.name}';
        list.add({'id': id, 'provider': p.name, 'u': map['u'], 'p': map['p']});
        for (final key in const ['locations', 'updated']) {
          final value = _metaBox!.get('${key}_${p.name}');
          if (value != null) await _metaBox!.put('${key}_$id', value);
        }
        if (p == BillProvider.eon) {
          final oldSession = 'bills_${_profileId}_eon_session';
          final session = await _storage.read(key: oldSession);
          if (session != null) {
            await _storage.write(key: _sessionKey(id), value: session);
            await _storage.delete(key: oldSession);
          }
        }
        await _storage.delete(key: oldKey);
      } catch (_) {
        // Date vechi ilizibile: contul se reintroduce manual.
      }
    }
    if (list.isNotEmpty) await _writeAccounts(list);
  }

  Future<(String, String)?> _readCreds(String accountId) async {
    final m = (await _readAccounts())
        .where((m) => m['id'] == accountId)
        .firstOrNull;
    return m == null ? null : ('${m['u']}', '${m['p']}');
  }

  /// Parola salvată a unui cont, pentru precompletarea formularului.
  Future<String?> passwordFor(String accountId) async =>
      (await _readCreds(accountId))?.$2;

  /// Adaugă un cont nou sau, cu [id], îl modifică pe cel existent.
  Future<void> saveAccount({
    String? id,
    required BillProvider provider,
    required String username,
    required String password,
  }) async {
    final list = await _readAccounts();
    final accountId = id ?? const Uuid().v4();
    final entry = {
      'id': accountId,
      'provider': provider.name,
      'u': username.trim(),
      'p': password,
    };
    final index = list.indexWhere((m) => m['id'] == accountId);
    index < 0 ? list.add(entry) : list[index] = entry;
    await _writeAccounts(list);
    await _storage.delete(key: _sessionKey(accountId));
    final account = BillAccount(accountId, provider, username.trim());
    final at = _accounts.indexWhere((a) => a.id == accountId);
    at < 0 ? _accounts.add(account) : _accounts[at] = account;
    _errors.remove(accountId);
    notifyListeners();
  }

  /// Deconectează un cont și șterge facturile lui nebifate. Cele bifate și
  /// cele din istoric rămân.
  Future<void> removeAccount(String accountId) async {
    final list = await _readAccounts()
      ..removeWhere((m) => m['id'] == accountId);
    await _writeAccounts(list);
    await _storage.delete(key: _sessionKey(accountId));
    _accounts.removeWhere((a) => a.id == accountId);
    _errors.remove(accountId);
    final gone = _bills
        .where((b) => b.accountId == accountId && !b.paid && !b.archived)
        .toList();
    for (final b in gone) {
      _bills.remove(b);
      await _billsBox?.delete(b.id);
    }
    await _metaBox?.delete('updated_$accountId');
    await _metaBox?.delete('locations_$accountId');
    notifyListeners();
  }

  /// Actualizează facturile din toate conturile conectate. Erorile sunt
  /// reținute per cont (vezi [errorsFor]) — un cont căzut nu le blochează
  /// pe celelalte.
  Future<void> refresh({required MfaCodePrompt askMfaCode}) async {
    if (_refreshing || _profileId == null) return;
    _refreshing = true;
    _errors.clear();
    notifyListeners();
    try {
      for (final account in List.of(_accounts)) {
        final creds = await _readCreds(account.id);
        if (creds == null) continue;
        final p = account.provider;
        try {
          final fetched = p == BillProvider.hidroelectrica
              ? await _fetchHidro(creds)
              : await _fetchEon(account.id, creds, askMfaCode);
          if (fetched == null) {
            _errors[account.id] =
                'Actualizare anulată: lipsește codul de verificare.';
            continue;
          }
          await _merge(account, fetched.$1);
          if (fetched.$2.isNotEmpty) {
            await _metaBox?.put('locations_${account.id}', fetched.$2);
          }
          await _metaBox?.put(
            'updated_${account.id}',
            DateTime.now().toIso8601String(),
          );
        } on BillFetchException catch (e) {
          _errors[account.id] = e.message;
        } catch (_) {
          _errors[account.id] =
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
        sinceDefault: _sinceDefault,
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
    String accountId,
    (String, String) creds,
    MfaCodePrompt askMfaCode,
    Future<T> Function(EonApi api) action,
  ) async {
    final api = EonApi();
    try {
      try {
        final raw = await _storage.read(key: _sessionKey(accountId));
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
        final code = await askMfaCode(challenge, creds.$1);
        if (code == null || code.trim().isEmpty) return null;
        await api.completeMfa(challenge.uuid, code);
        result = await action(api);
      }
      final session = api.exportSession();
      if (session != null) {
        await _storage.write(
          key: _sessionKey(accountId),
          value: jsonEncode(session),
        );
      }
      return result;
    } finally {
      api.close();
    }
  }

  Future<(List<Bill>, Map<String, String>)?> _fetchEon(
    String accountId,
    (String, String) creds,
    MfaCodePrompt askMfaCode,
  ) {
    final since = _sinceFor(BillProvider.eon);
    final skip = _skipFor(BillProvider.eon);
    return _withEon(accountId, creds, askMfaCode, (api) async {
      final bills = await api.fetchOpenBills(
        creds.$1,
        creds.$2,
        since: since,
        sinceDefault: _sinceDefault,
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
    final account =
        _accounts.where((a) => a.id == bill.accountId).firstOrNull ??
        accountsFor(bill.provider).firstOrNull;
    final creds = account == null ? null : await _readCreds(account.id);
    final name = billProviderLabel(bill.provider);
    if (account == null || creds == null) {
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
        account.id,
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

  Future<void> _merge(BillAccount account, List<Bill> fetched) async {
    final fetchedIds = <String>{};
    for (final f in fetched) {
      f.accountId = account.id;
      fetchedIds.add(f.id);
      final existing = _bills.where((b) => b.id == f.id).firstOrNull;
      if (existing == null) {
        _bills.add(f);
        await _billsBox?.put(f.id, f.toMap());
      } else {
        // Plata reală la furnizor se urmărește și pentru facturile din
        // istoric, ca o restanță să nu treacă neobservată.
        existing
          ..accountId = account.id
          ..balance = f.balance
          ..openAtProvider = f.openAtProvider
          ..fetchedAt = f.fetchedAt;
        if (!existing.archived) {
          existing
            ..invoiceNumber = f.invoiceNumber
            ..amount = f.amount
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
                : f.indexPeriod;
        }
        await _billsBox?.put(existing.id, existing.toMap());
      }
    }
    // Facturile care nu mai apar la furnizor ca neachitate rămân în listă,
    // marcate ca plătite la furnizor.
    for (final b in _bills.where(
      (b) =>
          b.accountId == account.id &&
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
