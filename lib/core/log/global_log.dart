import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppLogLevel { neutral, success, error }

class GlobalLogState {
  const GlobalLogState({
    required this.message,
    required this.level,
    required this.visible,
    this.timestamp,
  });

  factory GlobalLogState.hidden() => const GlobalLogState(
        message: null,
        level: AppLogLevel.neutral,
        visible: false,
      );

  final String? message;
  final AppLogLevel level;
  final bool visible;
  final DateTime? timestamp;

  GlobalLogState copyWith({
    String? message,
    AppLogLevel? level,
    bool? visible,
    DateTime? timestamp,
  }) {
    return GlobalLogState(
      message: message ?? this.message,
      level: level ?? this.level,
      visible: visible ?? this.visible,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

class GlobalLogNotifier extends Notifier<GlobalLogState> {
  Timer? _hideTimer;
  static const _autoHide = Duration(seconds: 6);

  @override
  GlobalLogState build() {
    ref.onDispose(() => _hideTimer?.cancel());
    return GlobalLogState.hidden();
  }

  void show(String message, {AppLogLevel level = AppLogLevel.neutral}) {
    _hideTimer?.cancel();
    state = GlobalLogState(
      message: message,
      level: level,
      visible: true,
      timestamp: DateTime.now(),
    );
    _hideTimer = Timer(_autoHide, () {
      // Solo ocultar si no hubo otro mensaje más reciente
      final last = state.timestamp;
      if (last != null && DateTime.now().difference(last) >= _autoHide) {
        hide();
      }
    });
  }

  void hide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    state = state.copyWith(visible: false);
  }
}

final globalLogProvider = NotifierProvider<GlobalLogNotifier, GlobalLogState>(
  GlobalLogNotifier.new,
);
