import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../shared/network_thumb.dart';
import 'dish_model.dart';
import 'menu_provider.dart';

final _searchProvider = StateProvider.autoDispose<String>((ref) => '');
final _price = NumberFormat('#,##0.##');

class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  void _snack(BuildContext context, String? error, String ok) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(error ?? ok)));

  Future<void> _bulk(BuildContext context, WidgetRef ref, bool active) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(active ? 'Enable all dishes?' : 'Disable all dishes?'),
        content: Text(active
            ? 'Every dish becomes available for sale at the counter.'
            : 'Every dish is hidden from the counter until re-enabled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true) return;
    final err = await setAllDishes(ref, active);
    if (context.mounted) _snack(context, err, active ? 'All dishes enabled.' : 'All dishes disabled.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dishes = ref.watch(dishesProvider);
    final query = ref.watch(_searchProvider).trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Menu'),
        actions: [
          PopupMenuButton<bool>(
            tooltip: 'Bulk actions',
            onSelected: (active) => _bulk(context, ref, active),
            itemBuilder: (_) => const [
              PopupMenuItem(value: true, child: Text('Enable all')),
              PopupMenuItem(value: false, child: Text('Disable all')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/menu/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add dish'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              onChanged: (v) => ref.read(_searchProvider.notifier).state = v,
              decoration: const InputDecoration(
                hintText: 'Search dishes',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(dishesProvider);
                await ref.read(dishesProvider.future).then((_) {}, onError: (_) {});
              },
              child: dishes.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(children: [
                      Text(e.toString().replaceFirst('Exception: ', ''), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => ref.invalidate(dishesProvider),
                        child: const Text('Retry'),
                      ),
                    ]),
                  ),
                ]),
                data: (all) {
                  final list = query.isEmpty
                      ? all
                      : all
                          .where((d) =>
                              d.name.toLowerCase().contains(query) ||
                              (d.printName ?? '').toLowerCase().contains(query))
                          .toList();
                  if (list.isEmpty) {
                    return ListView(children: const [
                      Padding(padding: EdgeInsets.all(48), child: Center(child: Text('No dishes found.'))),
                    ]);
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88), // clear the FAB
                    itemCount: list.length,
                    itemBuilder: (context, i) => _DishTile(dish: list[i]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DishTile extends ConsumerWidget {
  const _DishTile({required this.dish});
  final Dish dish;

  String get _prices {
    final parts = [dish.price, if (dish.doublePrice != null) dish.doublePrice!, if (dish.thirdPrice != null) dish.thirdPrice!];
    return parts.map(_price.format).join(' / ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = !dish.isActive;
    return Opacity(
      opacity: muted ? 0.55 : 1,
      child: ListTile(
        onTap: () => context.push('/menu/${dish.id}'),
        leading: NetworkThumb(path: dish.imagePath),
        title: Text(dish.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            if (dish.printName != null && dish.printName!.isNotEmpty) dish.printName!,
            'AED $_prices',
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Switch(
          value: dish.isActive,
          onChanged: (_) async {
            final err = await toggleDish(ref, dish.id);
            if (err != null && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
            }
          },
        ),
      ),
    );
  }
}
