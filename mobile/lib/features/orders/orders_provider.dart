import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import 'order_model.dart';

/// Selected calendar day (UAE) on the Orders screen; starts at today.
final ordersDateProvider = StateProvider.autoDispose<DateTime>((ref) => uaeToday());

String _friendly(DioException e, String what) {
  final msg = e.response?.data is Map ? (e.response!.data as Map)['message'] : null;
  return msg is String ? msg : 'Could not $what. Check your connection.';
}

final ordersProvider = FutureProvider.autoDispose<List<PosOrder>>((ref) async {
  final dio = ref.watch(apiClientProvider);
  final date = ref.watch(ordersDateProvider);
  try {
    final res = await dio.get('/orders', queryParameters: {'date': apiDate(date)});
    return [
      for (final o in res.data as List) PosOrder.fromJson(o as Map<String, dynamic>)
    ];
  } on DioException catch (e) {
    throw Exception(_friendly(e, 'load orders'));
  }
});

final orderProvider = FutureProvider.autoDispose.family<PosOrder, int>((ref, id) async {
  final dio = ref.watch(apiClientProvider);
  try {
    final res = await dio.get('/orders/$id');
    return PosOrder.fromJson(res.data as Map<String, dynamic>);
  } on DioException catch (e) {
    throw Exception(_friendly(e, 'load the order'));
  }
});

/// Soft-cancels an order (never hard-deleted; stays visible for audit).
/// Returns null on success, or an error message.
Future<String?> cancelOrder(WidgetRef ref, int id, String? reason) async {
  final dio = ref.read(apiClientProvider);
  try {
    await dio.patch('/orders/$id/cancel', data: {'reason': reason});
    ref.invalidate(orderProvider(id));
    ref.invalidate(ordersProvider);
    return null;
  } on DioException catch (e) {
    return _friendly(e, 'cancel the order');
  }
}
