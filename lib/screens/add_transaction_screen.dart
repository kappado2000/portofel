import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../providers/money_provider.dart';
import '../utils/categories.dart';
import '../utils/formatters.dart';

class AddTransactionScreen extends StatefulWidget {
  final int initialTab;

  const AddTransactionScreen({super.key, this.initialTab = 0});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Adaugă tranzacție'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Venit'),
            Tab(text: 'Cheltuială'),
            Tab(text: 'Transfer / Schimb'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _IncomeExpenseForm(isIncome: true),
          _IncomeExpenseForm(isIncome: false),
          _TransferForm(),
        ],
      ),
    );
  }
}

class _IncomeExpenseForm extends StatefulWidget {
  final bool isIncome;
  const _IncomeExpenseForm({required this.isIncome});

  @override
  State<_IncomeExpenseForm> createState() => _IncomeExpenseFormState();
}

class _IncomeExpenseFormState extends State<_IncomeExpenseForm> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String? _accountId;
  String? _category;
  DateTime _date = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MoneyProvider>();
    final accounts = provider.accounts;
    final categories = widget.isIncome ? incomeCategories : expenseCategories;
    _accountId ??= accounts.isNotEmpty ? accounts.first.id : null;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _accountId,
            decoration: InputDecoration(
              labelText: widget.isIncome ? 'Cont destinație' : 'Cont sursă',
            ),
            items: accounts
                .map((a) => DropdownMenuItem(
                      value: a.id,
                      child: Text('${a.name} (${currencyLabel(a.currency)})'),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Sumă'),
            validator: (v) {
              final value = double.tryParse((v ?? '').replaceAll(',', '.'));
              if (value == null || value <= 0) return 'Introdu o sumă validă';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _noteController,
            decoration: InputDecoration(
              labelText: 'Denumire operațiune',
              hintText: widget.isIncome
                  ? 'ex: Salariu, Cadou de la...'
                  : 'ex: Cumpărături Lidl, Factură curent',
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Introdu denumirea operațiunii' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Categorie'),
            items: categories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _category = v),
            validator: (v) => v == null ? 'Alege o categorie' : null,
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(dateTimeFormat.format(_date)),
            subtitle: const Text('Data operațiunii (completată automat, poți schimba)'),
            trailing: const Icon(Icons.edit_outlined, size: 18),
            onTap: _pickDateTime,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: accounts.isEmpty ? null : _submit,
            child: Text(widget.isIncome ? 'Adaugă venit' : 'Adaugă cheltuială'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (pickedTime == null) return;
    setState(() {
      _date = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _accountId == null) return;
    final amount = double.parse(_amountController.text.replaceAll(',', '.'));
    final provider = context.read<MoneyProvider>();

    if (widget.isIncome) {
      await provider.addIncome(
        accountId: _accountId!,
        amount: amount,
        category: _category ?? '',
        note: _noteController.text,
        date: _date,
      );
    } else {
      final account = provider.accountById(_accountId!);
      if (account != null && account.balance < amount) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Sold insuficient'),
            content: Text(
              'Contul "${account.name}" are ${formatAmount(account.balance, account.currency)}. '
              'Vrei să continui oricum?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anulează')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continuă')),
            ],
          ),
        );
        if (proceed != true) return;
      }
      await provider.addExpense(
        accountId: _accountId!,
        amount: amount,
        category: _category ?? '',
        note: _noteController.text,
        date: _date,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.isIncome ? 'Venit adăugat' : 'Cheltuială adăugată')),
      );
      _amountController.clear();
      _noteController.clear();
      setState(() {
        _category = null;
        _date = DateTime.now();
      });
    }
  }
}

class _TransferForm extends StatefulWidget {
  const _TransferForm();

  @override
  State<_TransferForm> createState() => _TransferFormState();
}

class _TransferFormState extends State<_TransferForm> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _rateController = TextEditingController();
  final _noteController = TextEditingController();
  String? _fromId;
  String? _toId;
  DateTime _date = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MoneyProvider>();
    final accounts = provider.accounts;
    _fromId ??= accounts.isNotEmpty ? accounts.first.id : null;
    _toId ??= accounts.length > 1 ? accounts[1].id : null;

    final fromAccount = _fromId != null ? provider.accountById(_fromId!) : null;
    final toAccount = _toId != null ? provider.accountById(_toId!) : null;
    final needsRate = fromAccount != null &&
        toAccount != null &&
        fromAccount.currency != toAccount.currency;

    if (needsRate && _rateController.text.isEmpty) {
      _rateController.text = provider.defaultExchangeRate.toStringAsFixed(4);
    }

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Folosește acest formular pentru: retragere numerar din cont, '
            'depunere la bancă, sau schimb valutar RON ↔ EUR.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _fromId,
            decoration: const InputDecoration(labelText: 'Din contul'),
            items: accounts
                .map((a) => DropdownMenuItem(
                      value: a.id,
                      child: Text('${a.name} (${currencyLabel(a.currency)})'),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _fromId = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _toId,
            decoration: const InputDecoration(labelText: 'În contul'),
            items: accounts
                .where((a) => a.id != _fromId)
                .map((a) => DropdownMenuItem(
                      value: a.id,
                      child: Text('${a.name} (${currencyLabel(a.currency)})'),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _toId = v),
            validator: (v) => v == null ? 'Alege contul destinație' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Sumă${fromAccount != null ? ' (${currencyLabel(fromAccount.currency)})' : ''}',
            ),
            validator: (v) {
              final value = double.tryParse((v ?? '').replaceAll(',', '.'));
              if (value == null || value <= 0) return 'Introdu o sumă validă';
              return null;
            },
            onChanged: (_) => setState(() {}),
          ),
          if (needsRate) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _rateController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Curs de schimb (1 EUR = ? RON)',
              ),
              validator: (v) {
                final value = double.tryParse((v ?? '').replaceAll(',', '.'));
                if (value == null || value <= 0) return 'Introdu un curs valid';
                return null;
              },
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Text(_previewText(fromAccount, toAccount), style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: 'Denumire operațiune (opțional)',
              hintText: 'ex: Retragere numerar, Schimb valutar vacanță',
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(dateTimeFormat.format(_date)),
            subtitle: const Text('Data operațiunii (completată automat, poți schimba)'),
            trailing: const Icon(Icons.edit_outlined, size: 18),
            onTap: _pickDateTime,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: (accounts.length < 2) ? null : _submit,
            child: const Text('Confirmă transferul'),
          ),
        ],
      ),
    );
  }

  String _previewText(Account from, Account to) {
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    final rate = double.tryParse(_rateController.text.replaceAll(',', '.'));
    if (amount == null || rate == null || rate <= 0) return '';
    double converted;
    if (from.currency == AccountCurrency.eur) {
      converted = amount * rate;
    } else {
      converted = amount / rate;
    }
    return 'Vei primi: ${formatAmount(converted, to.currency)}';
  }

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (pickedTime == null) return;
    setState(() {
      _date = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _fromId == null || _toId == null) return;
    final amount = double.parse(_amountController.text.replaceAll(',', '.'));
    final rate = _rateController.text.isNotEmpty
        ? double.tryParse(_rateController.text.replaceAll(',', '.'))
        : null;

    final provider = context.read<MoneyProvider>();
    final fromAccount = provider.accountById(_fromId!);
    if (fromAccount != null && fromAccount.balance < amount) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sold insuficient'),
          content: Text(
            'Contul "${fromAccount.name}" are ${formatAmount(fromAccount.balance, fromAccount.currency)}. '
            'Vrei să continui oricum?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anulează')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continuă')),
          ],
        ),
      );
      if (proceed != true) return;
    }

    await provider.addTransfer(
      fromAccountId: _fromId!,
      toAccountId: _toId!,
      amount: amount,
      exchangeRate: rate,
      note: _noteController.text,
      date: _date,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transfer efectuat')),
      );
      _amountController.clear();
      _noteController.clear();
      setState(() => _date = DateTime.now());
    }
  }
}
