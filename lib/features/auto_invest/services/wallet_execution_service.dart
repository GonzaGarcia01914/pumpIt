import 'wallet_execution_service_stub.dart'
    if (dart.library.html) 'wallet_execution_service_phantom.dart'
    if (dart.library.io) 'wallet_execution_service_local.dart' as impl;

export 'wallet_execution_service_stub.dart'
    if (dart.library.html) 'wallet_execution_service_phantom.dart'
    if (dart.library.io) 'wallet_execution_service_local.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef WalletExecutionService = impl.WalletExecutionService;

final walletExecutionServiceProvider = Provider<WalletExecutionService>((ref) {
  final service = impl.WalletExecutionService();
  ref.onDispose(service.dispose);
  return service;
});
