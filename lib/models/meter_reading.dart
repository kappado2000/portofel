import 'bill.dart';

/// Ultimul index înregistrat de furnizor pentru un contor.
class MeterReading {
  final BillProvider provider;
  final String contractCode;
  final String address;
  final String meterNumber;
  final String label;
  final double value;
  final DateTime? date;

  MeterReading({
    required this.provider,
    required this.contractCode,
    this.address = '',
    this.meterNumber = '',
    this.label = '',
    required this.value,
    this.date,
  });

  Map<String, dynamic> toMap() => {
    'provider': provider.name,
    'contractCode': contractCode,
    'address': address,
    'meterNumber': meterNumber,
    'label': label,
    'value': value,
    'date': date?.toIso8601String(),
  };

  factory MeterReading.fromMap(Map map) => MeterReading(
    provider: BillProvider.values.firstWhere(
      (p) => p.name == map['provider'],
      orElse: () => BillProvider.hidroelectrica,
    ),
    contractCode: map['contractCode'] as String? ?? '',
    address: map['address'] as String? ?? '',
    meterNumber: map['meterNumber'] as String? ?? '',
    label: map['label'] as String? ?? '',
    value: (map['value'] as num?)?.toDouble() ?? 0,
    date: map['date'] is String ? DateTime.tryParse(map['date']) : null,
  );
}
