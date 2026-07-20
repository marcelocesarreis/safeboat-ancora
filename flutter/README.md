# Âncora Virtual — código Flutter para o MAIN

Estrutura no padrão do módulo de câmeras
(`lib/features/anchor/{models,services,screens,widgets}`).

## Arquivos

- `models/anchor_models.dart` — `GpsFix`, `AnchorSnapshot`, `DriftInfo`,
  `AnchorConfig`, enum `AnchorState`. Espelham a saída de `core/anchor-core.js`.
- `services/anchor_service.dart` — conexão com o SAFEBOAT (WS local / relay),
  comandos (`dropAnchor`, `arm`, `disarm`, `acknowledge`, `moveAnchor`,
  `setConfig`) e stream de `AnchorSnapshot`. Pontos de conexão real marcados com
  `TODO(dev)`.

## Como plugar

1. `AnchorService.connect()`: descomentar o WebSocket e mapear a telemetria do
   dispositivo para `AnchorSnapshot`/`GpsFix`.
2. A UI escuta `service.snapshots` e redesenha o mapa (o protótipo web em
   `public/` é a referência visual e de comportamento — mesmo núcleo, mesmo
   design).
3. Onde roda o núcleo de decisão:
   - **Recomendado**: a bordo. O SAFEBOAT manda `{type:'snapshot'}` já decidido;
     o alarme vale com o app fechado.
   - **Alternativa**: o barco manda `{type:'fix'}` cru e o app roda o núcleo
     localmente (portar `anchor-core.js` para Dart, ou rodá-lo via
     `flutter_js`/FFI). Bom para animação suave, mas não substitui a decisão de
     bordo.

## Notificação

Alarme de âncora **precisa furar** o modo silencioso: iOS Critical Alerts,
Android canal de alta prioridade + serviço em primeiro plano. Disparado pelo
dispositivo via relay → FCM/APNs.

O núcleo (`core/anchor-core.js`) é a fonte da verdade do algoritmo — se portar
para Dart, mantenha os testes de `test-scenarios.cjs`/`test-sweep.cjs` como
referência de paridade.
