import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'phantom_wallet_service_stub.dart'
    if (dart.library.html) 'phantom_wallet_service_web.dart';

export 'phantom_wallet_service_stub.dart'
    if (dart.library.html) 'phantom_wallet_service_web.dart';

final phantomWalletServiceProvider = Provider<PhantomWalletService>((ref) {
  return PhantomWalletService();
});
