enum BillProvider { hidroelectrica, eon }

String billProviderLabel(BillProvider p) =>
    p == BillProvider.hidroelectrica ? 'Hidroelectrica' : 'E.ON';

/// O factură preluată de la un furnizor. [balance] și [openAtProvider]
/// reflectă ce a raportat furnizorul la ultima actualizare; [paid] e bifa
/// pusă manual de utilizator și nu e niciodată modificată de actualizare.
/// O factură cu [archived] a fost salvată în istoricul facturilor achitate.
class Bill {
  final String id;
  final BillProvider provider;
  final String contractCode;
  String address;
  final String invoiceNumber;
  double amount;
  double balance;
  DateTime? issueDate;
  DateTime? dueDate;
  bool paid;
  DateTime? paidAt;
  DateTime fetchedAt;
  bool openAtProvider;
  bool archived;

  Bill({
    required this.id,
    required this.provider,
    required this.contractCode,
    this.address = '',
    this.invoiceNumber = '',
    required this.amount,
    required this.balance,
    this.issueDate,
    this.dueDate,
    this.paid = false,
    this.paidAt,
    required this.fetchedAt,
    this.openAtProvider = true,
    this.archived = false,
  });

  static String buildId(
    BillProvider provider,
    String contractCode,
    String invoiceNumber,
  ) => '${provider.name}|$contractCode|$invoiceNumber';

  bool get isOverdue {
    final due = dueDate;
    if (paid || due == null) return false;
    final now = DateTime.now();
    return due.isBefore(DateTime(now.year, now.month, now.day));
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'provider': provider.name,
    'contractCode': contractCode,
    'address': address,
    'invoiceNumber': invoiceNumber,
    'amount': amount,
    'balance': balance,
    'issueDate': issueDate?.toIso8601String(),
    'dueDate': dueDate?.toIso8601String(),
    'paid': paid,
    'paidAt': paidAt?.toIso8601String(),
    'fetchedAt': fetchedAt.toIso8601String(),
    'openAtProvider': openAtProvider,
    'archived': archived,
  };

  factory Bill.fromMap(Map map) => Bill(
    id: map['id'] as String,
    provider: BillProvider.values.firstWhere(
      (p) => p.name == map['provider'],
      orElse: () => BillProvider.hidroelectrica,
    ),
    contractCode: map['contractCode'] as String? ?? '',
    address: map['address'] as String? ?? '',
    invoiceNumber: map['invoiceNumber'] as String? ?? '',
    amount: (map['amount'] as num?)?.toDouble() ?? 0,
    balance: (map['balance'] as num?)?.toDouble() ?? 0,
    issueDate: _date(map['issueDate']),
    dueDate: _date(map['dueDate']),
    paid: map['paid'] as bool? ?? false,
    paidAt: _date(map['paidAt']),
    fetchedAt: _date(map['fetchedAt']) ?? DateTime.now(),
    openAtProvider: map['openAtProvider'] as bool? ?? true,
    archived: map['archived'] as bool? ?? false,
  );

  static DateTime? _date(dynamic v) =>
      v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
}
