import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ApiServiceStatus {
  checking,
  online,
  offline,
}

class ApiStatusState {
  final ApiServiceStatus anilistStatus;
  final ApiServiceStatus newTvStatus;

  ApiStatusState({
    required this.anilistStatus,
    required this.newTvStatus,
  });

  ApiStatusState copyWith({
    ApiServiceStatus? anilistStatus,
    ApiServiceStatus? newTvStatus,
  }) {
    return ApiStatusState(
      anilistStatus: anilistStatus ?? this.anilistStatus,
      newTvStatus: newTvStatus ?? this.newTvStatus,
    );
  }
}

class ApiStatusNotifier extends StateNotifier<ApiStatusState> {
  ApiStatusNotifier() : super(ApiStatusState(
    anilistStatus: ApiServiceStatus.checking,
    newTvStatus: ApiServiceStatus.checking,
  )) {
    checkAll();
  }

  Future<void> checkAll() async {
    state = state.copyWith(
      anilistStatus: ApiServiceStatus.checking,
      newTvStatus: ApiServiceStatus.checking,
    );
    await Future.wait([
      _checkAnilist(),
      _checkNewTv(),
    ]);
  }

  Future<void> _checkAnilist() async {
    try {
      final dio = Dio(BaseOptions(validateStatus: (status) => true, connectTimeout: const Duration(seconds: 5)));
      final response = await dio.post(
        'https://graphql.anilist.co',
        data: {'query': '{ Media(id: 1) { id } }'},
      );
      // Anilist should return 200. If it returns 403, we are blocked and it's effectively offline for us.
      if (response.statusCode == 200) {
        state = state.copyWith(anilistStatus: ApiServiceStatus.online);
      } else {
        state = state.copyWith(anilistStatus: ApiServiceStatus.offline);
      }
    } catch (_) {
      state = state.copyWith(anilistStatus: ApiServiceStatus.offline);
    }
  }

  Future<void> _checkNewTv() async {
    try {
      final dio = Dio(BaseOptions(validateStatus: (status) => true, connectTimeout: const Duration(seconds: 5)));
      final response = await dio.get('https://net27.cc');
      // For NewTV, 200 means ok, 403/503 means cloudflare is up (which we can bypass). 
      // As long as we get a response, the server is online.
      if (response.statusCode != null) {
        state = state.copyWith(newTvStatus: ApiServiceStatus.online);
      } else {
        state = state.copyWith(newTvStatus: ApiServiceStatus.offline);
      }
    } catch (_) {
      state = state.copyWith(newTvStatus: ApiServiceStatus.offline);
    }
  }
}

final apiStatusProvider = StateNotifierProvider<ApiStatusNotifier, ApiStatusState>((ref) {
  return ApiStatusNotifier();
});
