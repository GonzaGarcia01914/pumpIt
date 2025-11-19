import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 📊 Categoría de error
enum ErrorCategory {
  temporary, // Errores temporales (red, timeout) → reintentar rápido
  permanent, // Errores permanentes (insufficient funds, invalid token) → no reintentar
  priority, // Errores de prioridad (low priority) → aumentar fee y reintentar
  unknown, // Error desconocido → comportamiento conservador
}

/// 📊 Recomendación de acción para un error
enum ErrorAction {
  retryFast, // Reintentar rápidamente (1-5 segundos)
  retryWithHigherFee, // Reintentar con fee más alto
  retrySlow, // Reintentar lentamente (30-60 segundos)
  doNotRetry, // No reintentar (error permanente)
  pauseTemporarily, // Pausar temporalmente (circuit breaker activado)
}

/// 📊 Análisis de error con recomendación de acción
class ErrorAnalysis {
  ErrorAnalysis({
    required this.category,
    required this.action,
    required this.message,
    this.retryDelay,
    this.shouldIncreaseFee,
    this.feeMultiplier,
    this.shouldPause,
    this.pauseDuration,
  });

  final ErrorCategory category;
  final ErrorAction action;
  final String message;
  final Duration? retryDelay; // Delay recomendado antes de reintentar
  final bool? shouldIncreaseFee; // Si se debe aumentar el fee
  final double? feeMultiplier; // Multiplicador para el fee (ej: 1.5x, 2x)
  final bool? shouldPause; // Si se debe pausar temporalmente
  final Duration? pauseDuration; // Duración de la pausa

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('Error Category: $category');
    buffer.writeln('Recommended Action: $action');
    buffer.writeln('Message: $message');
    if (retryDelay != null) {
      buffer.writeln('Retry Delay: ${retryDelay!.inSeconds}s');
    }
    if (shouldIncreaseFee == true && feeMultiplier != null) {
      buffer.writeln('Increase Fee: ${feeMultiplier}x');
    }
    if (shouldPause == true && pauseDuration != null) {
      buffer.writeln('Pause Duration: ${pauseDuration!.inSeconds}s');
    }
    return buffer.toString();
  }
}

/// 📊 Estado del circuit breaker
class CircuitBreakerState {
  CircuitBreakerState({
    required this.isOpen,
    required this.failureCount,
    required this.lastFailureTime,
    this.openedAt,
  });

  final bool isOpen; // true si el circuit breaker está abierto (pausado)
  final int failureCount; // Número de fallos consecutivos
  final DateTime lastFailureTime; // Último fallo
  final DateTime? openedAt; // Cuándo se abrió el circuit breaker
}

/// 📊 Servicio para manejo inteligente de errores
class ErrorHandlerService {
  ErrorHandlerService({
    int? maxFailuresBeforePause,
    Duration? pauseDuration,
    Duration? circuitBreakerResetTime,
  })  : _maxFailuresBeforePause = maxFailuresBeforePause ?? 10,
        _pauseDuration = pauseDuration ?? const Duration(minutes: 5),
        _circuitBreakerResetTime = circuitBreakerResetTime ?? const Duration(minutes: 10);

  final int _maxFailuresBeforePause;
  final Duration _pauseDuration;
  final Duration _circuitBreakerResetTime;

  // Circuit breaker por contexto (mint, operación, etc.)
  final Map<String, CircuitBreakerState> _circuitBreakers = {};

  // Historial de errores recientes
  final Map<String, List<DateTime>> _errorHistory = {};
  static const _errorHistoryWindow = Duration(minutes: 5);

  /// 📊 Analizar un error y proporcionar recomendación de acción
  ErrorAnalysis analyzeError(
    Object error, {
    String? context, // Contexto del error (mint, operación, etc.)
  }) {
    final errorString = error.toString().toLowerCase();
    final errorType = error.runtimeType.toString().toLowerCase();

    // 1. Clasificar el error
    final category = _classifyError(errorString, errorType);

    // 2. Verificar circuit breaker
    if (context != null) {
      final circuitState = _getCircuitBreakerState(context);
      if (circuitState.isOpen) {
        return ErrorAnalysis(
          category: category,
          action: ErrorAction.pauseTemporarily,
          message: 'Circuit breaker activado para $context. Pausando temporalmente.',
          shouldPause: true,
          pauseDuration: _pauseDuration,
        );
      }
    }

    // 3. Determinar acción recomendada
    final action = _determineAction(category, errorString, context);

    // 4. Calcular parámetros de reintento
    Duration? retryDelay;
    bool? shouldIncreaseFee;
    double? feeMultiplier;

    switch (action) {
      case ErrorAction.retryFast:
        retryDelay = const Duration(seconds: 2);
        break;
      case ErrorAction.retryWithHigherFee:
        retryDelay = const Duration(seconds: 3);
        shouldIncreaseFee = true;
        feeMultiplier = _calculateFeeMultiplier(context);
        break;
      case ErrorAction.retrySlow:
        retryDelay = const Duration(seconds: 30);
        break;
      case ErrorAction.doNotRetry:
        retryDelay = null;
        break;
      case ErrorAction.pauseTemporarily:
        retryDelay = _pauseDuration;
        break;
    }

    // 5. Registrar error para circuit breaker
    if (context != null && category != ErrorCategory.permanent) {
      _recordError(context);
    }

    return ErrorAnalysis(
      category: category,
      action: action,
      message: _buildErrorMessage(error, category),
      retryDelay: retryDelay,
      shouldIncreaseFee: shouldIncreaseFee,
      feeMultiplier: feeMultiplier,
      shouldPause: action == ErrorAction.pauseTemporarily,
      pauseDuration: action == ErrorAction.pauseTemporarily ? _pauseDuration : null,
    );
  }

  /// 📊 Clasificar error en una categoría
  ErrorCategory _classifyError(String errorString, String errorType) {
    // Errores temporales (red, timeout)
    if (errorString.contains('timeout') ||
        errorString.contains('timed out') ||
        errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('socket') ||
        errorString.contains('no fue posible contactar') ||
        errorType.contains('timeoutexception') ||
        errorType.contains('socketexception') ||
        errorString.contains('connection refused') ||
        errorString.contains('connection reset')) {
      return ErrorCategory.temporary;
    }

    // Errores de prioridad (low priority, insufficient priority fee)
    if (errorString.contains('low priority') ||
        errorString.contains('insufficient priority') ||
        errorString.contains('priority fee') ||
        errorString.contains('dropped') ||
        errorString.contains('blockhash not found') ||
        errorString.contains('blockhash expired')) {
      return ErrorCategory.priority;
    }

    // Errores permanentes (insufficient funds, invalid token, etc.)
    if (errorString.contains('insufficient funds') ||
        errorString.contains('insufficient balance') ||
        errorString.contains('invalid token') ||
        errorString.contains('token not found') ||
        errorString.contains('account not found') ||
        errorString.contains('invalid account') ||
        errorString.contains('invalid mint') ||
        errorString.contains('already exists') ||
        errorString.contains('duplicate') ||
        errorString.contains('invalid signature') ||
        errorString.contains('unauthorized')) {
      return ErrorCategory.permanent;
    }

    // Por defecto, tratar como desconocido
    return ErrorCategory.unknown;
  }

  /// 📊 Determinar acción recomendada
  ErrorAction _determineAction(
    ErrorCategory category,
    String errorString,
    String? context,
  ) {
    switch (category) {
      case ErrorCategory.temporary:
        // Verificar circuit breaker
        if (context != null) {
          final circuitState = _getCircuitBreakerState(context);
          if (circuitState.failureCount >= _maxFailuresBeforePause) {
            return ErrorAction.pauseTemporarily;
          }
        }
        return ErrorAction.retryFast;

      case ErrorCategory.priority:
        // Aumentar fee y reintentar
        return ErrorAction.retryWithHigherFee;

      case ErrorCategory.permanent:
        // No reintentar
        return ErrorAction.doNotRetry;

      case ErrorCategory.unknown:
        // Comportamiento conservador: reintentar lentamente
        if (context != null) {
          final circuitState = _getCircuitBreakerState(context);
          if (circuitState.failureCount >= _maxFailuresBeforePause) {
            return ErrorAction.pauseTemporarily;
          }
        }
        return ErrorAction.retrySlow;
    }
  }

  /// 📊 Calcular multiplicador de fee
  double _calculateFeeMultiplier(String? context) {
    if (context == null) return 1.5;

    final circuitState = _getCircuitBreakerState(context);
    // Aumentar fee progresivamente: 1.5x, 2x, 3x, etc.
    final multiplier = 1.5 + (circuitState.failureCount * 0.5);
    return multiplier.clamp(1.5, 5.0); // Máximo 5x
  }

  /// 📊 Construir mensaje de error descriptivo
  String _buildErrorMessage(Object error, ErrorCategory category) {
    final errorString = error.toString();
    final categoryName = category.toString().split('.').last;

    switch (category) {
      case ErrorCategory.temporary:
        return 'Error temporal detectado ($categoryName): $errorString. Se reintentará automáticamente.';
      case ErrorCategory.priority:
        return 'Error de prioridad detectado ($categoryName): $errorString. Se reintentará con fee más alto.';
      case ErrorCategory.permanent:
        return 'Error permanente detectado ($categoryName): $errorString. No se reintentará.';
      case ErrorCategory.unknown:
        return 'Error desconocido ($categoryName): $errorString. Se reintentará con precaución.';
    }
  }

  /// 📊 Registrar error para circuit breaker
  void _recordError(String context) {
    final now = DateTime.now();
    final history = _errorHistory.putIfAbsent(context, () => <DateTime>[]);
    history.add(now);

    // Limpiar errores antiguos
    final cutoff = now.subtract(_errorHistoryWindow);
    history.removeWhere((time) => time.isBefore(cutoff));

    // Actualizar circuit breaker
    final currentState = _getCircuitBreakerState(context);
    final recentFailures = history.length;

    if (recentFailures >= _maxFailuresBeforePause) {
      // Abrir circuit breaker
      _circuitBreakers[context] = CircuitBreakerState(
        isOpen: true,
        failureCount: recentFailures,
        lastFailureTime: now,
        openedAt: now,
      );
    } else {
      // Actualizar contador de fallos
      _circuitBreakers[context] = CircuitBreakerState(
        isOpen: false,
        failureCount: recentFailures,
        lastFailureTime: now,
        openedAt: currentState.openedAt,
      );
    }
  }

  /// 📊 Registrar éxito (resetear circuit breaker)
  void recordSuccess(String context) {
    // Limpiar historial de errores
    _errorHistory.remove(context);

    // Cerrar circuit breaker si estaba abierto
    final currentState = _getCircuitBreakerState(context);
    if (currentState.isOpen) {
      _circuitBreakers[context] = CircuitBreakerState(
        isOpen: false,
        failureCount: 0,
        lastFailureTime: currentState.lastFailureTime,
        openedAt: null,
      );
    } else {
      // Resetear contador
      _circuitBreakers[context] = CircuitBreakerState(
        isOpen: false,
        failureCount: 0,
        lastFailureTime: DateTime.now(),
        openedAt: null,
      );
    }
  }

  /// 📊 Obtener estado del circuit breaker
  CircuitBreakerState _getCircuitBreakerState(String context) {
    final state = _circuitBreakers[context];
    if (state == null) {
      return CircuitBreakerState(
        isOpen: false,
        failureCount: 0,
        lastFailureTime: DateTime.now(),
      );
    }

    // Verificar si el circuit breaker debe resetearse automáticamente
    if (state.isOpen && state.openedAt != null) {
      final timeSinceOpened = DateTime.now().difference(state.openedAt!);
      if (timeSinceOpened >= _circuitBreakerResetTime) {
        // Resetear circuit breaker
        _circuitBreakers[context] = CircuitBreakerState(
          isOpen: false,
          failureCount: 0,
          lastFailureTime: state.lastFailureTime,
          openedAt: null,
        );
        return _circuitBreakers[context]!;
      }
    }

    return state;
  }

  /// 📊 Verificar si un contexto está pausado (circuit breaker abierto)
  bool isPaused(String context) {
    final state = _getCircuitBreakerState(context);
    return state.isOpen;
  }

  /// 📊 Obtener tiempo restante hasta que el circuit breaker se resetee
  Duration? getTimeUntilReset(String context) {
    final state = _getCircuitBreakerState(context);
    if (!state.isOpen || state.openedAt == null) {
      return null;
    }

    final timeSinceOpened = DateTime.now().difference(state.openedAt!);
    final remaining = _circuitBreakerResetTime - timeSinceOpened;
    return remaining.isNegative ? null : remaining;
  }

  /// 📊 Obtener número de fallos recientes para un contexto
  int getFailureCount(String context) {
    final state = _getCircuitBreakerState(context);
    return state.failureCount;
  }

  /// 📊 Limpiar estado de un contexto (útil para testing o reset manual)
  void clearContext(String context) {
    _errorHistory.remove(context);
    _circuitBreakers.remove(context);
  }

  /// 📊 Limpiar todo el estado (útil para testing o reset completo)
  void clearAll() {
    _errorHistory.clear();
    _circuitBreakers.clear();
  }
}

final errorHandlerServiceProvider = Provider<ErrorHandlerService>((ref) {
  return ErrorHandlerService();
});

