import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 网络连接状态
class NetworkState {
  final bool isConnected;
  final bool isChecking;

  const NetworkState({
    this.isConnected = true,
    this.isChecking = false,
  });
}

/// 网络监听 Notifier
///
/// V1 简化版：假设有网（Firebase 未接入），
/// 后续用 connectivity_plus 替换为真实监听
class NetworkNotifier extends StateNotifier<NetworkState> {
  Timer? _timer;

  NetworkNotifier() : super(const NetworkState()) {
    _startListening();
  }

  /// 开始监听网络变化
  void _startListening() {
    // TODO: 接入 Firebase + connectivity_plus 后，替换为真实监听
    // connectivity.onConnectivityChanged.listen((result) {
    //   state = NetworkState(isConnected: result != ConnectivityResult.none);
    // });
  }

  /// 手动检查网络
  Future<void> checkConnection() async {
    state = const NetworkState(isChecking: true);
    await Future.delayed(const Duration(milliseconds: 500));

    // TODO: 真实网络检查
    // try {
    //   final result = await Connectivity().checkConnectivity();
    //   state = NetworkState(isConnected: result != ConnectivityResult.none);
    // } catch (_) {
    //   state = const NetworkState(isConnected: false);
    // }
    state = const NetworkState(isConnected: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// 网络状态 Provider
final networkProvider =
    StateNotifierProvider<NetworkNotifier, NetworkState>((ref) {
  return NetworkNotifier();
});
