import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'dish_model.dart';

String _friendly(DioException e, String what) {
  final data = e.response?.data;
  if (data is Map && data['message'] is String) return data['message'] as String;
  if (data is String && data.isNotEmpty && data.length < 200) return data;
  return 'Could not $what. Check your connection.';
}

/// All dishes (active and inactive), sorted by English label. Also feeds the
/// Reports dish filter.
final dishesProvider = FutureProvider.autoDispose<List<Dish>>((ref) async {
  final dio = ref.watch(apiClientProvider);
  try {
    final res = await dio.get('/dishes');
    final list = [
      for (final d in res.data as List) Dish.fromJson(d as Map<String, dynamic>)
    ];
    list.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return list;
  } on DioException catch (e) {
    if (e.response?.statusCode == 401) rethrow;
    throw Exception(_friendly(e, 'load the menu'));
  }
});

/// Default tax % for new dishes (`DefaultTaxRate` setting; web falls back to 5).
final defaultTaxRateProvider = FutureProvider.autoDispose<double>((ref) async {
  final dio = ref.watch(apiClientProvider);
  try {
    final res = await dio.get('/settings');
    for (final s in res.data as List) {
      if ((s as Map)['key'] == 'DefaultTaxRate') {
        return double.tryParse('${s['value']}') ?? 5;
      }
    }
  } on DioException catch (_) {}
  return 5;
});

/// Bumped after a photo upload: the server reuses one filename per dish
/// (`dish-<id>.jpg`), so image URLs get a `?v=` suffix to defeat the cache.
final imageStampProvider = StateProvider<int>((ref) => 0);

// Actions return null on success or a user-facing error message.

Future<String?> toggleDish(WidgetRef ref, int id) async {
  try {
    await ref.read(apiClientProvider).patch('/dishes/$id/toggle');
    ref.invalidate(dishesProvider);
    return null;
  } on DioException catch (e) {
    return _friendly(e, 'update the dish');
  }
}

Future<String?> setAllDishes(WidgetRef ref, bool active) async {
  try {
    await ref.read(apiClientProvider).patch('/dishes/toggle-all', data: {'isActive': active});
    ref.invalidate(dishesProvider);
    return null;
  } on DioException catch (e) {
    return _friendly(e, 'update the menu');
  }
}

/// Creates (existing == null) or updates a dish, then uploads [photo] if given.
Future<String?> saveDish(
  WidgetRef ref, {
  int? existingId,
  required DishInput input,
  Uint8List? photo,
}) async {
  final dio = ref.read(apiClientProvider);
  try {
    int id;
    if (existingId == null) {
      final res = await dio.post('/dishes', data: input.toJson());
      id = ((res.data as Map)['id'] as num).toInt();
    } else {
      await dio.put('/dishes/$existingId', data: input.toJson());
      id = existingId;
    }
    if (photo != null) {
      try {
        await dio.post('/dishes/$id/image',
            data: FormData.fromMap({'file': MultipartFile.fromBytes(photo, filename: 'dish.jpg')}));
        ref.read(imageStampProvider.notifier).state++;
      } on DioException catch (e) {
        ref.invalidate(dishesProvider);
        return 'Dish saved, but the photo failed: ${_friendly(e, 'upload the photo')}';
      }
    }
    ref.invalidate(dishesProvider);
    return null;
  } on DioException catch (e) {
    return _friendly(e, 'save the dish');
  }
}

Future<String?> deleteDish(WidgetRef ref, int id) async {
  try {
    await ref.read(apiClientProvider).delete('/dishes/$id');
    ref.invalidate(dishesProvider);
    return null;
  } on DioException catch (e) {
    return _friendly(e, 'delete the dish');
  }
}
