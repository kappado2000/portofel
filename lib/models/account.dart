enum AccountCurrency { ron, eur }

enum AccountKind { cash, bank }

enum AccountGroup { personal, family }

class Account {
  final String id;
  String name;
  AccountCurrency currency;
  AccountKind kind;
  double balance;
  AccountGroup group;
  int sortOrder;

  Account({
    required this.id,
    required this.name,
    required this.currency,
    required this.kind,
    this.balance = 0,
    this.group = AccountGroup.personal,
    this.sortOrder = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'currency': currency.name,
        'kind': kind.name,
        'balance': balance,
        'group': group.name,
        'sortOrder': sortOrder,
      };

  factory Account.fromMap(Map map) => Account(
        id: map['id'] as String,
        name: map['name'] as String,
        currency: AccountCurrency.values.byName(map['currency'] as String),
        kind: AccountKind.values.byName(map['kind'] as String),
        balance: (map['balance'] as num).toDouble(),
        group: AccountGroup.values.byName(map['group'] as String? ?? 'personal'),
        // Missing for accounts saved before drag-to-reorder existed — falls
        // back to 0 so they all tie and simply keep Hive's insertion order
        // (their existing on-screen order) until reordered once.
        sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
      );
}
