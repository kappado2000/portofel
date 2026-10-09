import '../models/bill.dart';
import 'bill_http.dart';

/// Preia facturile din contul Electrica Furnizare (MyElectrica), prin API-ul
/// folosit de portalul lor web.
class ElectricaApi {
  static const _base = 'https://api.myelectrica.ro/api';
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36';

  final JsonHttp _http = JsonHttp();
  String? _token;

  /// Locurile de consum ale contului (NLC → adresă), cunoscute după
  /// [fetchOpenBills].
  final Map<String, String> locations = {};

  Future<void> login(String email, String password) async {
    final resp = await _http.send(
      'POST',
      '$_base/login',
      headers: const {
        'Accept': 'application/json, text/plain, */*',
        'User-Agent': _userAgent,
      },
      body: {'email': email, 'parola': password},
    );
    final token = resp.map['app_token'];
    if (resp.status != 200 || resp.map['error'] != false || token == null) {
      throw BillFetchException(
        'Electrica: autentificare eșuată. Verifică emailul și parola.',
      );
    }
    _token = '$token';
  }

  Future<JsonResponse> _get(String path) => _http.send(
    'GET',
    '$_base$path',
    headers: {
      'Accept': 'application/json',
      'Authorization': 'Bearer $_token',
      'User-Agent': _userAgent,
    },
  );

  /// Întoarce facturile neplătite și, în plus, toate facturile emise după
  /// data din [since] a locului de consum (sau după [sinceDefault]).
  /// Locurile de consum din [skip] sunt ignorate. Apelează [login] înainte.
  Future<List<Bill>> fetchOpenBills({
    Map<String, DateTime> since = const {},
    DateTime? sinceDefault,
    Set<String> skip = const {},
  }) async {
    final hierarchyResp = await _get('/account-data-hierarchy');
    if (hierarchyResp.status != 200) {
      throw BillFetchException(
        'Electrica: nu am putut citi locurile de consum '
        '(cod ${hierarchyResp.status}).',
      );
    }
    final clients = hierarchyResp.map['details'];
    final bills = <Bill>[];
    final seen = <String>{};
    final now = DateTime.now();
    String day(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    for (final client in clients is List ? clients.whereType<Map>() : <Map>[]) {
      final clientCode = '${client['ClientCode'] ?? ''}'.trim();
      if (clientCode.isEmpty) continue;

      // Contract → loc de consum, pentru a lega fiecare factură de o adresă.
      final nlcByContract = <String, String>{};
      final contracts = client['to_ContContract'];
      for (final contract
          in contracts is List ? contracts.whereType<Map>() : <Map>[]) {
        final account = '${contract['ContractAccount'] ?? ''}'.trim();
        final locs = contract['to_LocConsum'];
        for (final loc in locs is List ? locs.whereType<Map>() : <Map>[]) {
          final nlc = '${loc['IdLocConsum'] ?? ''}'.trim();
          if (nlc.isEmpty) continue;
          locations[nlc] = _address(loc);
          nlcByContract.putIfAbsent(account, () => nlc);
        }
      }
      if (nlcByContract.isEmpty) continue;

      final start = now.subtract(const Duration(days: 365));
      final invResp = await _get(
        '/client-code-invoices/$clientCode/${day(start)}/${day(now)}/false',
      );
      if (invResp.status != 200) {
        throw BillFetchException(
          'Electrica: nu am putut citi facturile (cod ${invResp.status}).',
        );
      }
      for (final inv in _list(invResp.body)) {
        final direct = '${inv['nlcField'] ?? inv['NLC'] ?? inv['Nlc'] ?? ''}'
            .trim();
        final account =
            '${inv['ContractAccount'] ?? inv['ContractAcccount'] ?? ''}'.trim();
        final nlc = locations.containsKey(direct)
            ? direct
            : nlcByContract[account] ?? nlcByContract.values.first;
        if (skip.contains(nlc)) continue;

        final amount = parseAmount(
          inv['TotalAmount'] ??
              inv['InvoiceAmount'] ??
              inv['AmountDue'] ??
              inv['Amount'] ??
              inv['PaidValue'],
        );
        final status = '${inv['InvoiceStatus'] ?? inv['Status'] ?? ''}'
            .trim()
            .toLowerCase();
        final unpaidRaw = inv['UnpaidValue'];
        final unpaid = unpaidRaw != null && '$unpaidRaw'.isNotEmpty
            ? parseAmount(unpaidRaw)
            : (const {'achitat', 'platita', 'plătită', 'paid'}.contains(status)
                  ? 0.0
                  : amount);
        final issued = parseBillDate(inv['IssueDate']);
        final from = since[nlc] ?? sinceDefault;
        final recent = from != null && issued != null && issued.isAfter(from);
        if (amount <= 0 || (unpaid <= 0 && !recent)) continue;

        final number =
            '${inv['InvoiceNumber'] ?? inv['FiscalNumber'] ?? inv['DocumentNumber'] ?? inv['InvoiceId'] ?? ''}'
                .trim();
        final id = Bill.buildId(
          BillProvider.electrica,
          nlc,
          number.isEmpty ? '${inv['IssueDate'] ?? ''}' : number,
        );
        if (!seen.add(id)) continue;
        bills.add(
          Bill(
            id: id,
            provider: BillProvider.electrica,
            contractCode: nlc,
            address: locations[nlc] ?? '',
            invoiceNumber: number,
            amount: amount,
            balance: unpaid > 0 ? unpaid : amount,
            issueDate: issued,
            dueDate: parseBillDate(inv['DueDate']),
            fetchedAt: now,
            openAtProvider: unpaid > 0,
          ),
        );
      }
    }
    return bills;
  }

  void close() => _http.close();

  /// Lista din răspuns, oriunde ar fi: direct, în `body.response` sau în
  /// `details`.
  static List<Map> _list(dynamic raw) {
    dynamic value = raw;
    if (raw is Map) {
      final body = raw['body'];
      value = body is Map && body.containsKey('response')
          ? body['response']
          : raw['details'];
    }
    return value is List ? value.whereType<Map>().toList() : const [];
  }

  static String _address(Map loc) {
    String cap(dynamic v) => '${v ?? ''}'
        .trim()
        .toLowerCase()
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
    final street = [
      cap(loc['Street']),
      '${loc['HouseNumber'] ?? ''}'.trim(),
    ].where((s) => s.isNotEmpty).join(' ');
    return [street, cap(loc['City'])].where((s) => s.isNotEmpty).join(', ');
  }
}
