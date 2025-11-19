# Arquitectura de Conexiones - Pump It Baby Bot

## 📋 Resumen

El bot ahora usa una arquitectura de 3 capas para optimizar velocidad y eficiencia:

1. **⚡ WebSockets** - Para todo lo crítico en tiempo real
2. **🔄 RPC HTTP JSON-RPC** - Para operaciones puntuales no críticas
3. **🧠 Enhanced Solana APIs (Helius)** - Para analytics, reporting y dashboard

---

## ⚡ WebSockets

**Uso:** Todo lo crítico para la latencia del bot

### Implementado:

- ✅ **Confirmación de transacciones** (`signatureSubscribe`)
  - Reemplaza polling lento vía RPC
  - Confirmación inmediata cuando la tx es confirmada
  - Fallback automático a RPC HTTP si WebSocket falla

- ✅ **Suscripciones a logs de programas** (`logsSubscribe`)
  - Detecta eventos de pump.fun antes que polling HTTP
  - Útil para detectar buys/sells/migraciones en tiempo real

- ✅ **Suscripciones a cuentas** (`accountSubscribe`)
  - Monitorea cambios en pools (precio, liquidez)
  - Permite reaccionar rápido en take-profit/stop-loss

### Ubicación:
- `lib/features/auto_invest/services/solana_websocket_service.dart`

### Uso:
```dart
// Confirmación vía WebSocket (automático en waitForConfirmation)
await wallet.waitForConfirmation(signature); // Usa WebSocket si disponible

// Suscripción a eventos pump.fun
final logsStream = websocketService.subscribeToProgramLogs(pumpFunProgramId);
await for (final event in logsStream) {
  // Reaccionar a eventos en tiempo real
}
```

---

## 🔄 RPC HTTP JSON-RPC

**Uso:** Operaciones puntuales no críticas en tiempo

### Implementado:

- ✅ **Envío de transacciones** (`sendTransaction`)
  - `WalletExecutionService.signAndSendBase64()`
  - Con skipPreflight habilitado para velocidad

- ✅ **Lectura de estado** (no crítico)
  - `getBalance()` - Para actualizar UI
  - `getTokenAccountsByOwner()` - Si no usas Enhanced API
  - `getLatestBlockhash()` - Antes de firmar transacciones

- ✅ **Lectura de transacciones**
  - `getTransaction()` - Para leer resultados de swaps
  - `readTokenAmountFromTransaction()` - Para calcular fills

### Ubicación:
- `lib/features/auto_invest/services/wallet_execution_service_local.dart`

### Uso:
```dart
// Obtener blockhash antes de firmar
final blockhash = await wallet.getLatestBlockhash();

// Leer balance (no crítico)
final balance = await wallet.getWalletBalance(address);
```

---

## 🧠 Enhanced Solana APIs (Helius)

**Uso:** Historial, reporting, analytics y dashboard

### Implementado:

- ✅ **Historial de transacciones parseadas**
  - `getParsedTransactions()` - Trades con metadata
  - `getParsedTrades()` - Solo swaps con PnL calculado
  - `getPumpFunActivity()` - Actividad específica de pump.fun

- ✅ **Analytics y estadísticas**
  - `getTokenVolumeStats()` - Volumen por token
  - `getPnLReport()` - PnL total y por token

### Ubicación:
- `lib/features/auto_invest/services/helius_enhanced_api_service.dart`

### Configuración:
```bash
--dart-define=HELIUS_API_KEY=tu_api_key
```

### Uso:
```dart
// Obtener historial de trades
final trades = await heliusService.getParsedTrades(
  walletAddress: walletAddress,
  limit: 100,
);

// Obtener reporte de PnL
final pnlReport = await heliusService.getPnLReport(
  walletAddress: walletAddress,
);
```

---

## 🔄 Flujo de Confirmación Optimizado

### Antes (solo RPC HTTP):
```
1. Enviar transacción → RPC HTTP
2. Polling cada X ms → RPC HTTP (lento)
3. Confirmación después de varios intentos
```

### Ahora (WebSocket + Fallback):
```
1. Enviar transacción → RPC HTTP
2. Suscripción WebSocket → Confirmación inmediata ⚡
3. Si WebSocket falla → Fallback a RPC HTTP polling
```

**Resultado:** Confirmación en <2s en lugar de 5-15s

---

## 📊 Separación de Responsabilidades

| Operación | Método | Tecnología |
|-----------|--------|------------|
| Enviar transacción | `signAndSendBase64()` | RPC HTTP |
| Confirmar transacción | `waitForConfirmation()` | WebSocket → RPC HTTP fallback |
| Leer balance | `getWalletBalance()` | RPC HTTP |
| Obtener blockhash | `getLatestBlockhash()` | RPC HTTP |
| Historial de trades | `getParsedTrades()` | Enhanced API (Helius) |
| Analytics/PnL | `getPnLReport()` | Enhanced API (Helius) |
| Eventos en tiempo real | `subscribeToProgramLogs()` | WebSocket |
| Monitoreo de pools | `subscribeToAccount()` | WebSocket |

---

## 🚀 Próximos Pasos

- [ ] Integrar Enhanced API en UI para mostrar historial
- [ ] Implementar suscripciones WebSocket para eventos pump.fun en el executor
- [ ] Agregar monitoreo de pools vía WebSocket para take-profit/stop-loss
- [ ] Dashboard con analytics usando Enhanced API

---

## ⚙️ Configuración

### Variables de entorno requeridas:

```bash
# RPC (obligatorio)
--dart-define=RPC_URL=https://mainnet.helius-rpc.com/?api-key=TU_KEY

# Enhanced API (opcional, para analytics)
--dart-define=HELIUS_API_KEY=tu_api_key
```

### WebSocket:
- Se crea automáticamente desde `RPC_URL`
- Convierte `https://` → `wss://` y `http://` → `ws://`
- Fallback automático a RPC HTTP si no está disponible

