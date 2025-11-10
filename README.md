# Pump It Baby  Featured Bot

Escritorio Flutter que monitorea en tiempo real la seccion **featured** de
[pump.fun](https://pump.fun) y filtra automaticamente las memecoins con un
`market cap` USD superior a 15k. El bot trabaja con el mismo endpoint publico
que usa la WebApp (`https://frontend-api-v3.pump.fun/coins/for-you`), procesa
los datos y genera un resumen impulsado por IA.

## Requisitos

- Flutter 3.27+ con soporte desktop (Windows/macOS/Linux).
- Dart 3.6+.
- (Opcional) API key de OpenAI si se desea activar el resumen generativo.

## Configuracion

1. **Instala dependencias**

   ```bash
   flutter pub get
   ```

2. **(Opcional) habilita IA generativa**

   Exporta una API key valida antes de lanzar la app:

   ```powershell
   # PowerShell
   $env:OPENAI_API_KEY = 'sk-xxxxx'
   # Model opcional (por defecto gpt-4o-mini)
   $env:OPENAI_MODEL = 'gpt-4o-mini'
   ```

   Sin clave, el bot usa un motor heuristico que igual entrega
   insights basados en reglas.

3. **Variables de entorno clave (via `--dart-define`)**
   - `OPENAI_API_KEY`: requerido para IA (panel Featured y Resultados).
   - `OPENAI_MODEL` (opcional, por defecto `gpt-4o-mini`).
   - `JUPITER_BASE_URL` (opcional, default `https://quote-api.jup.ag`).
   - `JUPITER_DEFAULT_SLIPPAGE_BPS` (por ejemplo 300 = 3%).
   - `JUPITER_PRIORITY_FEE_LAMPORTS` para fijar el priority fee en lamports.
   - Ejemplo completo:
     ```bash
     flutter run -d chrome \
       --dart-define=OPENAI_API_KEY=sk-xxxx \
       --dart-define=JUPITER_PRIORITY_FEE_LAMPORTS=5000
     ```

## Ejecucion

```bash
flutter run -d windows   # o macos/linux segun tu SO
```

La UI refresca cada ~25s, muestra todas las monedas featured con
`usd_market_cap >= 15000`, permite abrir la ficha en pump.fun y despliega un
panel de insights IA en espanol. Desde la barra de filtros puedes ajustar
dinamicamente:

- Market cap minimo (USD) directo sobre el endpoint.
- Volumen 24h minimo (USD) aplicado en la llamada.
- Fecha minima de creacion para quedarte con tokens recientes.
- Ordenamiento (Mayor MC, mas recientes o tokens con mas replies).

Escribe los valores deseados, ajusta la fecha y presiona **Aplicar filtros** para refrescar la data en vivo.

## Tests & lint

```bash
flutter analyze
flutter test
```

## Arquitectura rapida

- **Datos**: `PumpFunClient` (HTTP) consume el endpoint oficial y normaliza la
  respuesta en `FeaturedCoin`.
- **Estado**: `FeaturedCoinNotifier` (Riverpod) mantiene coins, errores y
  resultado IA; incluye timer para auto-refresh.
- **IA**: `OpenAiInsightService` (si hay API key) o fallback
  `RuleBasedInsightService`.
- **UI**: pestañas `Featured bot`, `Auto invest` y `Resultados` (responsive desktop/web). Featured muestra las memecoins filtradas + IA; Auto invest permite configurar el bot/simulaciones; Resultados centraliza el histórico y el análisis IA.

## Proximos pasos sugeridos

- Ajustar umbrales dinamicamente desde la UI.
- Anadir modo headless/CLI para automatizar alertas.
- Persistir snapshots para analisis historico.

## Cómo terminar la integración con Phantom/Jupiter

1. `flutter config --enable-web` y ejecuta `flutter run -d chrome`.
2. Instala Phantom en el navegador y permite conexiones desde `http://localhost`.
3. En la pestaña Auto invest, conecta tu wallet (verás el address truncado) y ajusta presupuestos, filtros y reglas; enciende el switch cuando estés listo.
4. Implementa la generación de órdenes:
   - Usa el endpoint de Jupiter (`/quote` + `/swap`) o `https://swap-api.pump.fun` para construir la transacción (base64).
   - Decodifica la tx en Dart, pásala a `PhantomWalletService.signAndSend()` y deja que Phantom la firme/envíe.
   - Añade tu lógica de ejecución al notifier (ej. escanear las coins filtradas en cada refresco, gatillar compra si cumplen criterios, vigilar stop loss/take profit y vender).
5. Usa una wallet dedicada/RPC privado y añade límites diarios/logs antes de dejarlo en producción.
6. ¿Siguiente paso sugerido? Implementar el `ExecutionService` que consuma el estado de Auto Invest, construya swaps con Jupiter y llame a `signAndSend` cuando el bot detecte una oportunidad.

### Simulaciones + IA

- Desde la pestaña **Auto invest** presiona *Simular auto invest* para crear corridas sintéticas con los filtros actuales. Se muestran en la pestaña **Resultados**.
- Para habilitar el análisis IA de esas simulaciones define tu clave al lanzar la app:  
  `flutter run -d chrome --dart-define=OPENAI_API_KEY=sk-xxxx`.
- En **Resultados** pulsa *Analizar resultados con IA* para obtener un resumen de riesgos/ajustes sugeridos.

## Auto Invest + Phantom en Web

1. **Habilita Flutter Web**
   ```bash
   flutter config --enable-web
   flutter run -d chrome
   ```
2. **Instala Phantom** en tu navegador (Chrome/Edge) y activa la opción de permitir conexiones desde `http://localhost`.
3. **Tab “Auto invest”**
   - Conecta/desconecta Phantom con el botón dedicado (solo web).
   - Ajusta presupuesto total y máximo por memecoin.
   - Define filtros (MC/volumen) y reglas de seguridad (stop loss, take profit, retirar tras ganancia).
   - Activa el switch “Auto Invest” cuando la wallet esté conectada para que el bot empiece a monitorear con esos criterios.
4. **Integración de órdenes**
   - El servicio `PhantomWalletService` ya expone `connect/disconnect` y deja preparado `signAndSend`. Completa esa función construyendo swaps con [Jupiter](https://station.jup.ag/docs/apis/swap-api) o `swap-api.pump.fun` y pásalos a Phantom para que firme/envíe.
   - Implementa la lógica de ejecución dentro del notifier (por ejemplo, comparar los filtros con la data en vivo, disparar compras al detectar oportunidades y ventas al alcanzar stop-loss/take-profit).
5. **Buenas prácticas**
   - Usa una wallet separada y presupuestos limitados.
   - Trabaja con un RPC dedicado (Helius/QuickNode) para confirmar las transacciones del bot.
   - Añade límites diarios/logs antes de habilitarlo en mainnet.
