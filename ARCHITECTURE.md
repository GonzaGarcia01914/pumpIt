# Connection Architecture - Pump It Baby

## Summary

The bot uses a three-layer connection stack to optimize speed and reliability:

1. WebSockets for real-time events and confirmations
2. JSON-RPC HTTP for point-in-time reads and transaction submission
3. Helius Enhanced APIs for analytics, reporting, and enriched history

---

## WebSockets

Use case: Low-latency, real-time workflows

Implemented:

- Transaction confirmation (`signatureSubscribe`)
  - Replaces slow polling
  - Immediate confirmation on-chain
  - Automatic fallback to RPC HTTP if WS fails

- Program log subscriptions (`logsSubscribe`)
  - Detect pump.fun events faster than HTTP polling
  - Useful for tracking buys/sells/migrations

- Account subscriptions (`accountSubscribe`)
  - Monitor pool state (price, liquidity)
  - Enables fast take-profit and stop-loss reactions

Location:
- `lib/features/auto_invest/services/solana_websocket_service.dart`

Example:
```dart
// Confirmation via WebSocket (automatic in waitForConfirmation)
await wallet.waitForConfirmation(signature);

// Subscribe to pump.fun program logs
final logsStream = websocketService.subscribeToProgramLogs(pumpFunProgramId);
await for (final event in logsStream) {
  // React to real-time events
}
```

---

## JSON-RPC HTTP

Use case: Non-critical point reads and transaction submission

Implemented:

- Submit transactions (`sendTransaction`)
  - `WalletExecutionService.signAndSendBase64()`
  - skipPreflight enabled for speed

- State reads (non-critical)
  - `getBalance()` for UI refresh
  - `getTokenAccountsByOwner()` for fallback paths
  - `getLatestBlockhash()` before signing

- Transaction reads
  - `getTransaction()` for swap details
  - `readTokenAmountFromTransaction()` for fills

Location:
- `lib/features/auto_invest/services/wallet_execution_service_local.dart`

Example:
```dart
final blockhash = await wallet.getLatestBlockhash();
final balance = await wallet.getWalletBalance(address);
```

---

## Helius Enhanced APIs

Use case: History, reporting, analytics, and dashboards

Implemented:

- Parsed transaction history
  - `getParsedTransactions()`
  - `getParsedTrades()` with PnL
  - `getPumpFunActivity()`

- Analytics and stats
  - `getTokenVolumeStats()`
  - `getPnLReport()`

Location:
- `lib/features/auto_invest/services/helius_enhanced_api_service.dart`

Configuration:
```bash
--dart-define=HELIUS_API_KEY=your_api_key
```

Example:
```dart
final trades = await heliusService.getParsedTrades(
  walletAddress: walletAddress,
  limit: 100,
);

final pnlReport = await heliusService.getPnLReport(
  walletAddress: walletAddress,
);
```

---

## Optimized Confirmation Flow

Before (RPC only):

1. Send transaction via HTTP
2. Poll every X ms
3. Confirm after multiple retries

Now (WebSocket + fallback):

1. Send transaction via HTTP
2. WebSocket subscription
3. If WS fails, fallback to HTTP polling

Result: Typical confirmations in under 2s instead of 5-15s.

---

## Responsibilities Matrix

| Operation | Method | Tech |
| --- | --- | --- |
| Submit transaction | `signAndSendBase64()` | RPC HTTP |
| Confirm transaction | `waitForConfirmation()` | WebSocket with HTTP fallback |
| Read balance | `getWalletBalance()` | RPC HTTP |
| Get blockhash | `getLatestBlockhash()` | RPC HTTP |
| Trade history | `getParsedTrades()` | Helius Enhanced API |
| Analytics/PnL | `getPnLReport()` | Helius Enhanced API |
| Program events | `subscribeToProgramLogs()` | WebSocket |
| Pool monitoring | `subscribeToAccount()` | WebSocket |

---

## Next Steps

- Expose Enhanced API insights in the UI
- Add program log subscriptions to the executor
- Use WS pool monitoring for take-profit and stop-loss
- Expand analytics dashboards

---

## Configuration

```bash
# RPC (required)
--dart-define=RPC_URL=https://mainnet.helius-rpc.com/?api-key=YOUR_KEY

# Enhanced API (optional, analytics)
--dart-define=HELIUS_API_KEY=your_api_key
```

WebSockets are derived from the RPC URL:

- `https://` -> `wss://`
- `http://` -> `ws://`

If WebSocket is unavailable, RPC HTTP is used as fallback.
