# Pump It Baby · Featured Bot

Flutter desktop/web para monitorear en tiempo real la sección **featured** de [pump.fun](https://pump.fun) y orquestar un bot de auto-invest que filtra, simula, genera insights con IA y, en desktop, puede ejecutar swaps reales vía Jupiter.

## Requisitos

- Flutter 3.27+ con soporte desktop (Windows/macOS/Linux).
- Dart 3.6+.
- Para IA: clave de OpenAI (`OPENAI_API_KEY`).
- Para el bot real en desktop: keypair local (`id.json`) y un RPC confiable (Helius/QuickNode…).

## Configuración mínima

1. **Dependencias**
   ```bash
   flutter pub get
   ```

2. **IA opcional**
   ```powershell
   $env:OPENAI_API_KEY = 'sk-xxxxx'
   $env:OPENAI_MODEL = 'gpt-4o-mini'   # opcional
   ```

3. **Variables `--dart-define`**
   - `OPENAI_API_KEY` y `OPENAI_MODEL`.
   - `JUPITER_BASE_URL` (default `https://quote-api.jup.ag`).
   - `JUPITER_DEFAULT_SLIPPAGE_BPS` (default `300` = 3%).
   - `JUPITER_PRIORITY_FEE_LAMPORTS`.
   - `LOCAL_KEY_PATH`: ruta del `id.json` (solo desktop).
   - `RPC_URL`: endpoint RPC donde enviar las transacciones.
   - `PUMP_PORTAL_BASE_URL`: host de la API de PumpPortal (default `https://pumpportal.fun`).

   Ejemplos:
   ```bash
   # Solo lectura/IA en web (Phantom)
   flutter run -d chrome \
     --dart-define=OPENAI_API_KEY=sk-xxxx \
     --dart-define=JUPITER_PRIORITY_FEE_LAMPORTS=5000

   # Bot real en desktop (keypair local + Helius)
   flutter run -d windows ^
     --dart-define=LOCAL_KEY_PATH=C:\Keys\auto_bot.json ^
     --dart-define=RPC_URL=https://mainnet.helius-rpc.com/?api-key=TU_KEY ^
     --dart-define=OPENAI_API_KEY=sk-xxxx ^
     --dart-define=JUPITER_PRIORITY_FEE_LAMPORTS=5000
   ```

## Ejecución
```bash
flutter run -d windows   # o macos/linux
```
La UI refresca cada ~25 s, filtra por market cap, ordena y alimenta un panel IA. Los filtros son editables (MC, volumen, fecha, ordenamiento) y se aplican al presionar **Aplicar filtros**.

## Tests
```bash
flutter analyze
flutter test
```

## Arquitectura rápida

- **Datos**: `PumpFunClient` consume el endpoint público real y normaliza en `FeaturedCoin`.
- **Estado**: `FeaturedCoinNotifier` + `AutoInvestNotifier` (Riverpod) controlan filtros, IA, simulaciones y ejecución.
- **IA**: heurístico o `OpenAiInsightService` si defines `OPENAI_API_KEY`.
- **UI**: pestañas `Featured bot`, `Auto invest`, `Resultados`.
- **Auto invest**: `AutoInvestExecutor` observa criterios y, cuando el bot está encendido, dispara swaps en Jupiter y firma (Phantom en web, keypair local en desktop).

## Simulaciones + IA

- En **Auto invest** usa *Simular auto invest* para crear corridas sintéticas. Aparecen en **Resultados**.
- Define `OPENAI_API_KEY` para habilitar *Analizar resultados con IA*. Obtendrás insights sobre rendimiento y ajustes sugeridos.

## Auto invest (web + Phantom)

1. `flutter config --enable-web` y `flutter run -d chrome`.
2. Instala Phantom y permite conexiones desde `http://localhost`.
3. En **Auto invest** conecta Phantom, ajusta criterios y activa el switch. (Recuerda que, si publicas en GitHub Pages, necesitarás un proxy propio para sortear CORS al leer pump.fun.)

## Auto invest (desktop + keypair local)

1. **Keypair dedicado**
   ```bash
   solana-keygen new -o C:\Keys\auto_bot.json --no-bip39-passphrase --force
   solana-keygen pubkey C:\Keys\auto_bot.json
   ```
   Guarda el archivo fuera del repo (BitLocker/FileVault) y fondea la cuenta con presupuesto limitado.

2. **RPC PRIVADO (CRÍTICO para velocidad) ⚡**
   - ⚠️ **OBLIGATORIO**: Usa un RPC privado de alto rendimiento (Helius recomendado)
   - Sin RPC privado, el bot será lento (2-20s por transacción). Con RPC privado: <500ms
   - **Configuración Helius (recomendado):**
     ```bash
     --dart-define=HELIUS_API_KEY=tu_api_key_de_helius
     ```
     El bot automáticamente usará:
     - **RPC HTTP**: `https://mainnet.helius-rpc.com/?api-key=TU_KEY`
     - **WebSocket**: `wss://mainnet.helius-rpc.com/?api-key=TU_KEY`
     - **Enhanced API**: `https://api-mainnet.helius-rpc.com/v0/transactions/?api-key=TU_KEY`
   - **Alternativa (override manual):**
     ```bash
     --dart-define=RPC_URL=https://mainnet.helius-rpc.com/?api-key=TU_KEY
     ```
   - Ajusta `JUPITER_PRIORITY_FEE_LAMPORTS` según congestión (recomendado: 5000-10000)

3. **Lanzar la app**
   ```powershell
   flutter run -d windows `
     --dart-define=LOCAL_KEY_PATH=C:\Keys\auto_bot.json `
     --dart-define=HELIUS_API_KEY=tu_api_key_de_helius `
     --dart-define=OPENAI_API_KEY=sk-xxxx `
     --dart-define=JUPITER_PRIORITY_FEE_LAMPORTS=5000
   ```
   
   **Nota:** Con `HELIUS_API_KEY` configurado, el bot automáticamente usa:
   - RPC HTTP de Helius para transacciones
   - WebSocket de Helius para confirmaciones en tiempo real
   - Enhanced API de Helius para analytics (si está habilitado)

4. **Operar**
   - Pulsa *Connect wallet* (lee tu `id.json`).
   - Ajusta filtros (MC, volumen), presupuestos y reglas de riesgo (stop loss/take profit).
   - Enciende el switch **Auto Invest**. El bot solicitará quotes en Jupiter (o PumpPortal si lo eliges), firmará con tu key y enviará la transacción al RPC configurado.
   - Revisa la pestaña **Resultados** para ver simulaciones y órdenes reales (txid, horario, estado).

> ⚠️ Usa wallets dedicadas, preset de límites diarios y priority fees. Comienza en devnet y sube a mainnet gradualmente.

## ⚡ Optimizaciones de Velocidad Implementadas

El bot está optimizado para trading de alta frecuencia con las siguientes mejoras:

1. **✅ Skip Preflight**: Habilitado por defecto (aumenta velocidad x5)
2. **✅ Jito Bundles**: Habilitado para compras/ventas vía PumpPortal (salta al frente del bloque)
3. **✅ Confirmación Optimizada**: Timeout agresivo (15s) con verificación manual de fallback
4. **✅ Envío en Paralelo**: Múltiples ventas pueden ejecutarse simultáneamente
5. **✅ RPC Privado**: Configuración obligatoria para máximo rendimiento
6. **✅ Preconstrucción de Transacciones**: Cache de 5 segundos para evitar regenerar transacciones idénticas

**Tiempos esperados con RPC privado:**
- Compra: <500ms (envío) + <2s (confirmación)
- Venta: <500ms (envío) + <2s (confirmación)

**Sin RPC privado:** 2-20s por transacción (no recomendado para trading)

## Próximos pasos sugeridos

- Añadir ventas/stop-loss automáticos.
- Persistir snapshots del bot para backtesting.
- Headless/CLI para correr el motor sin UI.

## Auto invest (pump.fun bonding curve)

Si quieres operar tokens que siguen en la bonding curve de pump.fun, activa el nuevo riel **PumpPortal**:

1. Mantén la configuración de escritorio (keypair local + `RPC_URL`). No se requiere API key; el bot usa el endpoint público `/api/trade-local`.
2. En la tarjeta **Motor de ejecución** selecciona *PumpPortal (bonding curve)*. Ese modo le dice al bot que solicite la transacción al servicio de PumpPortal en lugar de Jupiter.
3. Ajusta el *slippage* permitido, la *priority fee* (en SOL) y el *pool* preferido (`pump`, `pump-amm`, `raydium`, etc.). Por defecto usamos 10 % y 0.001 SOL.
4. Opcional: sobreescribe `PUMP_PORTAL_BASE_URL` si hospedas tu propio mirror. Si no, deja el valor por defecto.
5. Al ejecutarse, el bot pide la transacción a PumpPortal, la firma con tu wallet local y la envía por el RPC que configuraste. Esto permite entrar a memecoins antes de que “se gradúen” y aparezcan en Jupiter.

> ⚠️ PumpPortal simplemente construye la transacción; la custodia sigue en tu wallet. Aun así, opera con montos acotados, valida los mints y monitorea que la bonding curve tenga liquidez real antes de subir tamaños.
