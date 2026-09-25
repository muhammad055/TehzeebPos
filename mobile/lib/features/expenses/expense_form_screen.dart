import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../shared/network_thumb.dart';
import '../../shared/photo_picker.dart';
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
    setState(() => _saving = true);
    final err = await saveExpense(
      ref,
      existingId: widget.purchaseId,
      date: _date,
      supplier: _supplier.text.trim(),
      description: _description.text.trim(),
      amount: double.parse(_amount.text.trim()),
      category: _category,
      photos: _newPhotos,
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
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount (AED)'),
              validator: (v) {
                final n = double.tryParse((v ?? '').trim());
                if (n == null) return 'Enter an amount';
                return n <= 0 ? 'Must be more than 0' : null;
              },
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
