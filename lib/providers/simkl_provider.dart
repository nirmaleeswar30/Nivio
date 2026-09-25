import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nivio/services/simkl_auth_service.dart';

/// Provider for the Simkl authenticated user state (movies, TV & anime sync).
final simklAuthProvider =
    StateNotifierProvider<SimklAuthNotifier, SimklUser?>((ref) {
  return SimklAuthNotifier();
});

class SimklAuthNotifier extends StateNotifier<SimklUser?> {
  final SimklAuthService _service = SimklAuthService.instance;

  SimklAuthNotifier() : super(null) {
    _init();
    _service.userNotifier.addListener(_onUserChanged);
  }

  void _onUserChanged() {
    state = _service.userNotifier.value;
  }

  @override
  void dispose() {
    _service.userNotifier.removeListener(_onUserChanged);
    super.dispose();
  }

  Future<void> _init() async {
    await _service.init();
    state = _service.currentUser;
  }

  Future<bool> launchAuth() => _service.launchAuthorization();

  Future<bool> loginWithInput(String input) async {
    final success = await _service.authenticateWithInput(input);
    if (success) state = _service.currentUser;
    return success;
  }

  Future<void> logout() async {
    await _service.disconnect();
    state = null;
  }
}
