import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

class AppUser {
  AppUser({required this.id, required this.username, required this.fullName, required this.role});
  final int id;
  final String username;
  final String fullName;
  final String role; // admin / manager / operator

  bool get isAdmin => role == 'admin';
  bool get canManage => role == 'admin' || role == 'manager';

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as int,
        username: j['username'] as String,
        fullName: j['full_name'] as String,
        role: j['role'] as String,
      );
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    ref.watch(localStoreProvider),
    onUnauthorized: () => ref.read(authProvider.notifier).logout(),
  );
});

/// null = logged out. Loading while a saved token is being verified.
class AuthController extends AsyncNotifier<AppUser?> {
  @override
  Future<AppUser?> build() async {
    final store = ref.read(localStoreProvider);
    if (store.token == null) return null;
    try {
      final me = await ref.read(apiClientProvider).get('/auth/me');
      return AppUser.fromJson(me as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.statusCode == 401) await store.setToken(null);
      return null;
    }
  }

  Future<void> login(String username, String password) async {
    final res = await ref
        .read(apiClientProvider)
        .post('/auth/login', {'username': username.trim(), 'password': password});
    await ref.read(localStoreProvider).setToken(res['access_token'] as String);
    state = AsyncData(AppUser.fromJson(res['user'] as Map<String, dynamic>));
  }

  Future<void> logout() async {
    await ref.read(localStoreProvider).setToken(null);
    state = const AsyncData(null);
  }
}

final authProvider = AsyncNotifierProvider<AuthController, AppUser?>(AuthController.new);

/// Current user; only valid inside logged-in screens.
final currentUserProvider = Provider<AppUser?>((ref) => ref.watch(authProvider).value);
