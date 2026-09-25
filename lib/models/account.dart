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

  Account({
    required this.id,
    required this.name,
    required this.currency,
    required this.kind,
    this.balance = 0,
    this.group = AccountGroup.personal,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'currency': currency.name,
        'kind': kind.name,
        'balance': balance,
        'group': group.name,
      };

  factory Account.fromMap(Map map) => Account(
        id: map['id'] as String,
        name: map['name'] as String,
        currency: AccountCurrency.values.byName(map['currency'] as String),
        kind: AccountKind.values.byName(map['kind'] as String),
        balance: (map['balance'] as num).toDouble(),
        group: AccountGroup.values.byName(map['group'] as String? ?? 'personal'),
      );
}
