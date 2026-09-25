import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'stats_model.dart';

/// Fetches `/api/stats`. autoDispose so reopening the dashboard refetches;
/// `ref.invalidate(statsProvider)` powers pull-to-refresh.
final statsProvider = FutureProvider.autoDispose<Stats>((ref) async {
  final dio = ref.watch(apiClientProvider);
  try {
    final res = await dio.get('/stats');
    return Stats.fromJson(res.data as Map<String, dynamic>);
  } on DioException catch (e) {
    if (e.response?.statusCode == 401) rethrow; // interceptor already signs out
    throw Exception('Could not load the dashboard. Check your connection.');
  }
});
