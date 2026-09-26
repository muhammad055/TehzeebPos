import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../shared/network_thumb.dart';
import '../../shared/photo_picker.dart';
import '../../core/theme.dart';
import '../inventory/inventory_model.dart';
import '../inventory/inventory_provider.dart';
import 'expenses_provider.dart';
import 'purchase_model.dart';

/// Add (purchaseId == null) or edit an expense, with receipt photos.
class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({super.key, this.purchaseId});
  final int? purchaseId;

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supplier = TextEditingController();
  final _description = TextEditingController();
  final _amount = TextEditingController();

  late DateTime _date = uaeToday();
  String _category = expenseCategories.first;
  final List<Uint8List> _newPhotos = [];
  final List<_LineCtl> _lines = [];
  bool _loaded = false;
  bool _saving = false;

  bool get _isEdit => widget.purchaseId != null;

  @override
  void initState() {
    super.initState();
    _loaded = !_isEdit;
  }

  @override
  void dispose() {
    _supplier.dispose();
    _description.dispose();
    _amount.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  void _populate(Purchase p) {
    _date = p.date;
    _supplier.text = p.supplier;
    _description.text = p.description;
    _amount.text = p.totalAmount == p.totalAmount.roundToDouble()
        ? p.totalAmount.toStringAsFixed(0)
        : '${p.totalAmount}';
    // Keep unknown/legacy categories selectable instead of silently changing them.
    _category = p.category;
    for (final i in p.items) {
      _lines.add(_LineCtl(itemId: i.itemId, quantity: qty(i.quantity), price: qty(i.unitPrice)));
    }
  }

  double get _linesTotal => _lines.fold<double>(0, (s, l) => s + l.total);

  void _addLine() => setState(() => _lines.add(_LineCtl()));

  void _removeLine(int i) => setState(() => _lines.removeAt(i).dispose());

  Future<void> _newItem(int lineIndex) async {
    final name = TextEditingController();
    var unit = 'kg';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('New item'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Chicken'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: unit,
              decoration: const InputDecoration(labelText: 'Unit'),
              items: [for (final u in stockUnits) DropdownMenuItem(value: u, child: Text(u))],
              onChanged: (u) => setD(() => unit = u ?? unit),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(90, 44)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    final entered = name.text.trim();
    name.dispose();
    if (ok != true || entered.isEmpty) return;
    final r = await createItem(ref, entered, unit);
    if (!mounted) return;
    if (r.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.error!)));
      return;
    }
    setState(() {
      if (lineIndex < _lines.length) _lines[lineIndex].itemId = r.item!.id;
    });
  }

  List<String> get _categoryOptions =>
      expenseCategories.contains(_category) ? expenseCategories : [_category, ...expenseCategories];

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: uaeToday(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _addPhoto() async {
    final bytes = await pickPhoto(context);
    if (bytes != null) setState(() => _newPhotos.add(bytes));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    for (final l in _lines) {
      if (l.itemId == null || l.quantity <= 0 || l.price < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Each item needs an item, a quantity above 0 and a price.')));
        return;
      }
    }
    setState(() => _saving = true);
    final err = await saveExpense(
      ref,
      existingId: widget.purchaseId,
      date: _date,
      supplier: _supplier.text.trim(),
      description: _description.text.trim(),
      amount: _lines.isNotEmpty ? _linesTotal : double.parse(_amount.text.trim()),
      category: _category,
      photos: _newPhotos,
      // Editing always sends the lines (even none) so removed lines are removed on the server.
      lines: _lines.isEmpty && !_isEdit
          ? null
          : [for (final l in _lines) BillLineInput(itemId: l.itemId!, quantity: l.quantity, unitPrice: l.price)],
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      if (!err.startsWith('Expense saved')) return;
    }
    context.pop();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: const Text('The expense and its photos are removed permanently.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final err = await deleteExpense(ref, widget.purchaseId!);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    context.pop();
  }

  Future<void> _removeAttachment(Attachment a) async {
    final err = await deleteAttachment(ref, widget.purchaseId!, a.id);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    Purchase? existing;
    if (_isEdit) {
      final async = ref.watch(purchaseProvider(widget.purchaseId!));
      existing = async.valueOrNull;
      if (!_loaded && existing != null) {
        _populate(existing);
        _loaded = true;
      }
      if (!_loaded) {
        return Scaffold(
          appBar: AppBar(title: const Text('Edit expense')),
          body: async.hasError
              ? Center(child: Text(async.error.toString().replaceFirst('Exception: ', '')))
              : const Center(child: CircularProgressIndicator()),
        );
      }
    }

    final itemOptions = ref.watch(itemsProvider).valueOrNull ?? const <Item>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit expense' : 'Add expense'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete expense',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _confirmDelete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(DateFormat('EEE, d MMM y').format(_date)),
            ),
            const SizedBox(height: 12),
            if (_lines.isEmpty)
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount (AED)'),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null) return 'Enter an amount';
                  return n <= 0 ? 'Must be more than 0' : null;
                },
              )
            else
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Total (AED) — sum of the items below'),
                child: Text(aed.format(_linesTotal),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [for (final c in _categoryOptions) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (c) => setState(() => _category = c ?? _category),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _supplier,
              decoration: const InputDecoration(labelText: 'Supplier'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 20),
            Text('Items on this bill', style: Theme.of(context).textTheme.titleMedium),
            const Text('Optional — lets the app track stock',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 8),
            for (final (i, l) in _lines.indexed)
              _LineCard(
                key: ObjectKey(l),
                line: l,
                items: itemOptions,
                onChanged: () => setState(() {}),
                onNewItem: () => _newItem(i),
                onRemove: _saving ? null : () => _removeLine(i),
              ),
            OutlinedButton.icon(
              onPressed: _saving ? null : _addLine,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add item'),
            ),
            const SizedBox(height: 20),
            Text('Receipts', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in existing?.attachments ?? const <Attachment>[])
                _PhotoBox(
                  onRemove: _saving ? null : () => _removeAttachment(a),
                  child: NetworkThumb(path: a.imagePath, size: 88, icon: Icons.receipt_long),
                ),
              for (final (i, bytes) in _newPhotos.indexed)
                _PhotoBox(
                  onRemove: _saving ? null : () => setState(() => _newPhotos.removeAt(i)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(bytes, width: 88, height: 88, fit: BoxFit.cover),
                  ),
                ),
              InkWell(
                onTap: _saving ? null : _addPhoto,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.outline),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.add_a_photo_outlined),
                ),
              ),
            ]),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isEdit ? 'Save changes' : 'Add expense'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Editable state for one bill line.
class _LineCtl {
  _LineCtl({this.itemId, String quantity = '', String price = ''})
      : qtyCtl = TextEditingController(text: quantity),
        priceCtl = TextEditingController(text: price);

  int? itemId;
  final TextEditingController qtyCtl;
  final TextEditingController priceCtl;

  double get quantity => double.tryParse(qtyCtl.text.trim()) ?? 0;
  double get price => double.tryParse(priceCtl.text.trim()) ?? 0;
  double get total => quantity * price;

  void dispose() {
    qtyCtl.dispose();
    priceCtl.dispose();
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    super.key,
    required this.line,
    required this.items,
    required this.onChanged,
    required this.onNewItem,
    required this.onRemove,
  });

  final _LineCtl line;
  final List<Item> items;
  final VoidCallback onChanged;
  final VoidCallback onNewItem;
  final VoidCallback? onRemove;

  static const _newItemValue = -1;

  @override
  Widget build(BuildContext context) {
    final unit = items.where((i) => i.id == line.itemId).map((i) => i.unit).firstOrNull ?? '';
    // The item may be inactive (hidden from the list) but still on an older bill.
    final known = line.itemId == null || items.any((i) => i.id == line.itemId);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                key: ValueKey('${line.hashCode}-${line.itemId}-${items.length}'),
                initialValue: known ? line.itemId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Item', isDense: true),
                items: [
                  for (final i in items) DropdownMenuItem(value: i.id, child: Text('${i.name} (${i.unit})')),
                  const DropdownMenuItem(value: _newItemValue, child: Text('＋ New item…')),
                ],
                onChanged: (v) {
                  if (v == _newItemValue) {
                    onNewItem();
                  } else {
                    line.itemId = v;
                    onChanged();
                  }
                },
              ),
            ),
            IconButton(
              tooltip: 'Remove item',
              icon: const Icon(Icons.close_rounded, color: AppColors.danger),
              onPressed: onRemove,
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: line.qtyCtl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => onChanged(),
                decoration: InputDecoration(labelText: 'Quantity', isDense: true, suffixText: unit),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: line.priceCtl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => onChanged(),
                decoration: const InputDecoration(labelText: 'Price / unit', isDense: true, prefixText: 'AED '),
              ),
            ),
          ]),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Line total  ${aed.format(line.total)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _PhotoBox extends StatelessWidget {
  const _PhotoBox({required this.child, required this.onRemove});
  final Widget child;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            top: -6,
            right: -6,
            child: InkWell(
              onTap: onRemove,
              child: CircleAvatar(
                radius: 11,
                backgroundColor: Theme.of(context).colorScheme.error,
                child: Icon(Icons.close, size: 14, color: Theme.of(context).colorScheme.onError),
              ),
            ),
          ),
        ],
      );
}
