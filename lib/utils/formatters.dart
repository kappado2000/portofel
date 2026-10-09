import 'package:intl/intl.dart';

import '../models/account.dart';
import '../models/bill.dart';

final _ronFormat = NumberFormat.currency(
  locale: 'ro_RO',
  symbol: 'lei',
  decimalDigits: 2,
);
final _eurFormat = NumberFormat.currency(
  locale: 'ro_RO',
  symbol: '€',
  decimalDigits: 2,
);
final _numberFormat = NumberFormat('#,##0.00', 'ro_RO');
final indexFormat = NumberFormat('#,##0', 'ro_RO');
final dateFormat = DateFormat('dd.MM.yyyy');
final dateTimeFormat = DateFormat('dd.MM.yyyy HH:mm');

String formatAmount(double amount, AccountCurrency currency) {
  return currency == AccountCurrency.ron
      ? _ronFormat.format(amount)
      : _eurFormat.format(amount);
}

/// Formatează o sumă cu separator de mii (punct) și 2 zecimale, fără
/// simbol de valută — pentru locurile unde valuta e adăugată manual alături.
String formatNumber(double amount) => _numberFormat.format(amount);

String currencyLabel(AccountCurrency c) =>
    c == AccountCurrency.ron ? 'RON' : 'EUR';

/// Textul cu intervalul de index facturat, sau `null` dacă nu e cunoscut.
String? billIndexLine(Bill bill) {
  final to = bill.indexTo;
  final from = bill.indexFrom;
  if (to == null && from == null) return null;
  String n(double v) =>
      v == v.roundToDouble() ? indexFormat.format(v) : formatNumber(v);
  final range = from != null && to != null
      ? 'Index ${n(from)} → ${n(to)}'
      : 'Index ${n((to ?? from)!)}';
  final extra = [
    if (bill.readingType.isNotEmpty) bill.readingType.toLowerCase(),
    if (bill.indexPeriod.isNotEmpty) bill.indexPeriod,
  ].join(', ');
  return extra.isEmpty ? range : '$range ($extra)';
}

/// „Factura 14.10.2026” — factura cu data scadenței (sau, în lipsa ei, cu
/// data emiterii).
String billDatesLine(Bill bill) {
  final date = bill.dueDate ?? bill.issueDate;
  return date == null ? 'Factura' : 'Factura ${dateFormat.format(date)}';
}

/// Perioada de consum, scurtată la „03.08-04.09”. Dacă textul nu conține
/// două date recunoscute, rămâne neschimbat.
String shortIndexPeriod(String period) {
  final dates = <String>[];
  final pattern = RegExp(
    r'(\d{4})-(\d{2})-(\d{2})|(\d{1,2})[./-](\d{1,2})[./-](\d{4})',
  );
  for (final m in pattern.allMatches(period)) {
    final day = (m.group(3) ?? m.group(4))!.padLeft(2, '0');
    final month = (m.group(2) ?? m.group(5))!.padLeft(2, '0');
    dates.add('$day.$month');
  }
  return dates.length >= 2 ? '${dates[0]}-${dates[1]}' : period.trim();
}

/// Starea plății reale la furnizor, afișată sub factură.
String billProviderStatus(Bill bill) =>
    bill.openAtProvider ? 'Neplătită' : 'Plătită';
