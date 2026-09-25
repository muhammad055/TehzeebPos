import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/network_thumb.dart';
import '../../shared/photo_picker.dart';
import 'dish_model.dart';
import 'menu_provider.dart';

/// Add (dishId == null) or edit a dish, including its photo and delete.
class DishFormScreen extends ConsumerStatefulWidget {
  const DishFormScreen({super.key, this.dishId});
  final int? dishId;

  @override
  ConsumerState<DishFormScreen> createState() => _DishFormScreenState();
}

class _DishFormScreenState extends ConsumerState<DishFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _printName = TextEditingController();
  final _price = TextEditingController();
  final _price2 = TextEditingController();
  final _price3 = TextEditingController();
  final _tax = TextEditingController();

  PricingScheme _scheme = PricingScheme.singleDouble;
  Uint8List? _photo; // picked, not yet uploaded
  Dish? _existing;
  bool _loaded = false;
  bool _saving = false;

  bool get _isEdit => widget.dishId != null;

  @override
  void dispose() {
    for (final c in [_name, _printName, _price, _price2, _price3, _tax]) {
      c.dispose();
    }
    super.dispose();
  }

  String _num(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v');

  void _populate(Dish d) {
    _existing = d;
    _name.text = d.name;
    _printName.text = d.printName ?? '';
    _price.text = _num(d.price);
    _price2.text = _num(d.doublePrice);
    _price3.text = _num(d.thirdPrice);
    _tax.text = _num(d.taxRate);
    _scheme = PricingScheme.parse(d.pricingScheme);
  }

  String? _requiredNumber(String? v, {bool allowZero = false}) {
    final n = double.tryParse((v ?? '').trim());
    if (n == null) return 'Enter a number';
    if (n < 0 || (!allowZero && n == 0)) return allowZero ? 'Must be 0 or more' : 'Must be more than 0';
    return null;
  }

  String? _optionalNumber(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return double.tryParse(v.trim()) == null ? 'Enter a number' : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final input = DishInput(
      name: _name.text.trim(),
      printName: _printName.text,
      price: double.parse(_price.text.trim()),
      taxRate: double.parse(_tax.text.trim()),
      doublePrice: double.tryParse(_price2.text.trim()),
      thirdPrice: double.tryParse(_price3.text.trim()),
      scheme: _scheme,
    );
    final err = await saveDish(ref, existingId: widget.dishId, input: input, photo: _photo);
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      // "Dish saved, but the photo failed" still saved — leave the screen.
      if (!err.startsWith('Dish saved')) return;
    }
    context.pop();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${_existing?.label ?? 'dish'}?'),
        content: const Text(
            'It disappears from the menu. Past orders keep their recorded dish names. '
            'To just hide it, turn it off instead.'),
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
    final err = await deleteDish(ref, widget.dishId!);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final dishes = ref.watch(dishesProvider);
    final defaultTax = ref.watch(defaultTaxRateProvider).valueOrNull;

    // One-time population once the dish list (edit) / default tax (add) arrives.
    if (!_loaded) {
      if (_isEdit) {
        final list = dishes.valueOrNull;
        if (list != null) {
          final match = list.where((d) => d.id == widget.dishId);
          if (match.isNotEmpty) _populate(match.first);
          _loaded = true;
        }
      } else if (defaultTax != null || ref.read(defaultTaxRateProvider).hasError) {
        _tax.text = _num(defaultTax ?? 5);
        _loaded = true;
      }
    }

    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: Text(_isEdit ? 'Edit dish' : 'Add dish')),
        body: dishes.hasError
            ? Center(child: Text(dishes.error.toString().replaceFirst('Exception: ', '')))
            : const Center(child: CircularProgressIndicator()),
      );
    }
    if (_isEdit && _existing == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit dish')),
        body: const Center(child: Text('This dish no longer exists.')),
      );
    }

    final labels = _scheme.tierLabels;
    final hasTier2 = (double.tryParse(_price2.text.trim()) ?? 0) > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit dish' : 'Add dish'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete dish',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: GestureDetector(
                onTap: _saving
                    ? null
                    : () async {
                        final bytes = await pickPhoto(context);
                        if (bytes != null) setState(() => _photo = bytes);
                      },
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _photo != null
                          ? Image.memory(_photo!, width: 140, height: 140, fit: BoxFit.cover)
                          : NetworkThumb(path: _existing?.imagePath, size: 140),
                    ),
                    const CircleAvatar(radius: 16, child: Icon(Icons.photo_camera, size: 18)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name (shown in the app)'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _printName,
              decoration: const InputDecoration(
                labelText: 'Print name (English, for receipts)',
                helperText: 'Receipts are ASCII-only — use this when the name is Urdu.',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PricingScheme>(
              initialValue: _scheme,
              decoration: const InputDecoration(labelText: 'Portion sizes'),
              items: const [
                DropdownMenuItem(value: PricingScheme.singleDouble, child: Text('Single / Double')),
                DropdownMenuItem(value: PricingScheme.quarterHalfFull, child: Text('Quarter / Half / Full')),
              ],
              onChanged: (v) => setState(() => _scheme = v ?? _scheme),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: '${labels[0]} price (AED)'),
              validator: _requiredNumber,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _price2,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: '${labels[1]} price (AED, optional)',
                helperText: 'Leave empty if the dish has one price.',
              ),
              validator: _optionalNumber,
              onChanged: (_) => setState(() {}),
            ),
            if (_scheme == PricingScheme.quarterHalfFull) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _price3,
                enabled: hasTier2,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: '${labels[2]} price (AED, optional)'),
                validator: _optionalNumber,
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _tax,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Tax rate (%)'),
              validator: (v) => _requiredNumber(v, allowZero: true),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isEdit ? 'Save changes' : 'Add dish'),
            ),
          ],
        ),
      ),
    );
  }
}
