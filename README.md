# Pump It Baby - Featured Bot and Auto-Invest Dashboard

Flutter desktop/web app that monitors pump.fun featured memecoins in real time and orchestrates an auto-invest bot with filtering, simulation, AI summaries, and optional live execution via Jupiter or PumpPortal.

## Overview

Pump It Baby is a trading research and automation dashboard for Solana memecoins. It pulls featured coins, applies configurable filters, runs simulations, and optionally executes real swaps on desktop using a local keypair. On web, it can connect to Phantom for read-only or constrained flows.

## Key Features

- Real-time featured memecoin feed with filters and insights
- Auto-invest engine with risk controls, budget limits, and cooldowns
- Simulation mode and AI summaries for performance analysis
- Dual execution modes: Jupiter (AMM) and PumpPortal (bonding curve)
- WebSocket confirmations and fast RPC paths for low-latency execution

## Tech Stack

- Flutter 3.27+, Dart 3.6+
- State management: Riverpod (Notifiers, Providers)
- Solana integrations: JSON-RPC, WebSockets, Helius Enhanced APIs
- Swaps: Jupiter and PumpPortal
- Optional AI: OpenAI API (summaries and simulation analysis)

## Architecture (High Level)

- UI layer: Flutter widgets grouped by feature modules
- State layer: Riverpod Notifiers for Featured coins and Auto invest
- Services layer: API clients, execution services, analytics, and AI
- Data sources: pump.fun API, Solana RPC/WS, Helius Enhanced API
- Execution: Desktop uses local keypair. Web uses Phantom provider

See `ARCHITECTURE.md` for the connection and confirmation pipeline details.

## State Management

- `FeaturedCoinNotifier` drives discovery, filters, AI summaries, and refresh cadence
- `AutoInvestNotifier` stores configuration, bot state, and positions
- `AutoInvestExecutor` observes state, applies eligibility checks, and triggers swaps
- Providers are scoped at app root for reactive updates across tabs

## Runtime Modes

- Web: Read-only or Phantom-connected, useful for dashboards and demos
- Desktop: Local keypair + RPC for live execution with fast confirmations

## Configuration

### Environment variables (optional)

```powershell
$env:OPENAI_API_KEY = 'sk-xxxxx'
$env:OPENAI_MODEL = 'gpt-4o-mini'
```

### Dart defines

- `OPENAI_API_KEY`, `OPENAI_MODEL`
- `JUPITER_BASE_URL` (default `https://quote-api.jup.ag`)
- `JUPITER_DEFAULT_SLIPPAGE_BPS` (default `300`)
- `JUPITER_PRIORITY_FEE_LAMPORTS`
- `LOCAL_KEY_PATH` (desktop only)
- `RPC_URL`
- `PUMP_PORTAL_BASE_URL` (default `https://pumpportal.fun`)
- `HELIUS_API_KEY` (optional, analytics)

Examples:

```bash
# Web (Chrome) with AI
flutter run -d chrome \
  --dart-define=OPENAI_API_KEY=sk-xxxx \
  --dart-define=JUPITER_PRIORITY_FEE_LAMPORTS=5000

# Desktop (Windows) with local keypair and Helius
flutter run -d windows ^
  --dart-define=LOCAL_KEY_PATH=C:\\Keys\\auto_bot.json ^
  --dart-define=HELIUS_API_KEY=your_helius_key ^
  --dart-define=OPENAI_API_KEY=sk-xxxx ^
  --dart-define=JUPITER_PRIORITY_FEE_LAMPORTS=5000
```

## Running

```bash
flutter run -d windows   # or macos/linux
```

## Tests

```bash
flutter analyze
flutter test
```

## Security Notes

- Use a dedicated wallet with capped funds.
- Prefer a private RPC for speed and reliability.
- Start in devnet and increase exposure gradually.

## Portfolio Snapshot

Pump It Baby is a full-stack Flutter trading dashboard that combines real-time Solana data, a rule-based auto-invest engine, and optional AI summaries. The app is modular by feature, uses Riverpod for state management, and separates data acquisition, decision logic, and execution services. It supports desktop execution with low-latency WebSocket confirmations and web demos via Phantom.
