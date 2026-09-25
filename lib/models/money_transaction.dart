enum TxType { income, expense, transfer }

class MoneyTransaction {
  final String id;
  final TxType type;
  final DateTime date;
  final String fromAccountId; // sursă (expense/transfer) sau destinație unică (income)
  final String? toAccountId; // doar pentru transfer
  final double amount; // sumă scăzută din fromAccount
  final double? convertedAmount; // sumă adăugată în toAccount (transfer între valute)
  final double? exchangeRate; // folosit doar dacă valutele diferă
  final String category;
  final String note;

  MoneyTransaction({
    required this.id,
    required this.type,
    required this.date,
    required this.fromAccountId,
    this.toAccountId,
    required this.amount,
    this.convertedAmount,
    this.exchangeRate,
    this.category = '',
    this.note = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'date': date.toIso8601String(),
        'fromAccountId': fromAccountId,
        'toAccountId': toAccountId,
        'amount': amount,
        'convertedAmount': convertedAmount,
        'exchangeRate': exchangeRate,
        'category': category,
        'note': note,
      };

  factory MoneyTransaction.fromMap(Map map) => MoneyTransaction(
        id: map['id'] as String,
        type: TxType.values.byName(map['type'] as String),
        date: DateTime.parse(map['date'] as String),
        fromAccountId: map['fromAccountId'] as String,
        toAccountId: map['toAccountId'] as String?,
        amount: (map['amount'] as num).toDouble(),
        convertedAmount: (map['convertedAmount'] as num?)?.toDouble(),
        exchangeRate: (map['exchangeRate'] as num?)?.toDouble(),
        category: map['category'] as String? ?? '',
        note: map['note'] as String? ?? '',
      );
}
