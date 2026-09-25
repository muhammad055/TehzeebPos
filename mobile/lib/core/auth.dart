import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';

/// Roles mirror backend `Roles` (Program.cs). UI gating is a convenience only —
/// the server's policies are the real enforcement.
enum Role {
  owner,
  admin,
  cashier;

  static Role? parse(String? value) {
    for (final r in Role.values) {
      if (r.name == value) return r;
    }
    return null;
  }
}

class AuthSession {
  const AuthSession({required this.token, required this.username, required this.role});

  final String token;
  final String username;
  final Role role;
}

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

const _kToken = 'token';
const _kUsername = 'username';
const _kRole = 'role';

class AuthController extends AsyncNotifier<AuthSession?> {
  final _storage = const FlutterSecureStorage();

  @override
  Future<AuthSession?> build() async {
    final token = await _storage.read(key: _kToken);
    final username = await _storage.read(key: _kUsername);
    final role = Role.parse(await _storage.read(key: _kRole));
    if (token == null || username == null || role == null) return null;
    return AuthSession(token: token, username: username, role: role);
  }

  Future<void> login(String username, String password) async {
    // Uses a bare Dio: there is no token yet and a 401 here means "wrong
    // password", not "session expired".
    final dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
    try {
      final res = await dio.post('/auth/login', data: {
        'username': username,
        'password': password,
        'client': 'mobile', // asks the backend for the long-lived mobile token
      });
      final data = res.data as Map<String, dynamic>;
      final role = Role.parse(data['role'] as String?);
      if (role == null) throw AuthException('Unknown role on this account.');
      final session = AuthSession(
        token: data['token'] as String,
        username: data['username'] as String,
        role: role,
      );
      await _storage.write(key: _kToken, value: session.token);
      await _storage.write(key: _kUsername, value: session.username);
      await _storage.write(key: _kRole, value: role.name);
      state = AsyncData(session);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw AuthException('Incorrect username or password.');
      }
      throw AuthException('Cannot reach the server. Check your connection.');
    }
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    state = const AsyncData(null);
  }
}

final authProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);
