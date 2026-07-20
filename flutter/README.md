# SAFEBOAT — Âncora Virtual (app Flutter)

App Flutter **completo** da vigília de fundeio: núcleo de detecção, simulação,
adaptador de dispositivo e UI — tudo em Dart. Roda em modo **demo** (dispositivo
simulado) igualzinho ao protótipo web, e está pronto para plugar o SAFEBOAT real
trocando um adaptador.

## Rodar

```bash
flutter pub get
flutter run                 # Android / iOS / web / desktop
```

## Validar (o port é fiel ao JS já testado)

```bash
flutter test                # paridade com o núcleo JS + bancada de cenários
dart run bin/bench.dart      # bancada no terminal (espelha test-scenarios.cjs)
dart run bin/bench.dart garrando   # um cenário com detalhes
```

O `flutter test` confere o port contra **vetores-golden** gerados pelo núcleo JS
(0 falso alarme em 280 fundeios): RNG bit-a-bit, geometria, e um trace do núcleo
sobre fixes determinísticos (estado, distância, deriva). Se algum bug de tradução
tiver entrado, o teste acusa. Regenerar os golden (se mudar o núcleo JS):

```bash
node gen-golden.cjs          # gera test/golden.json a partir de ../core/*.js
node verify-rng.cjs          # confere o RNG Dart bit-a-bit vs JS (emulação BigInt)
```

## Estrutura

```
lib/
  main.dart                          entrada do app (modo demo)
  theme.dart                         identidade visual SAFEBOAT
  features/anchor/
    core/
      geo.dart                       geometria (plano local ENU, haversine, fitCircle...)
      anchor_core.dart               AnchorWatch: filtro, máquina de estados,
                                     detector de deriva radial-vs-tangencial
      sim_device.dart                SimulatedBoat + 10 cenários + RNG semeado
      device_adapter.dart            SimAdapter (demo) + SafeboatAdapter (stub real)
    services/
      anchor_controller.dart         ChangeNotifier que amarra núcleo+dispositivo+UI
    screens/anchor_screen.dart       tela principal
    widgets/
      anchor_map.dart                CustomPainter do mapa (raio, rastro, barco, âncora)
      radius_sheet.dart              bottom sheet "Configurar raio"
bin/bench.dart                       bancada de cenários (dart run)
test/anchor_core_test.dart           teste de paridade + bancada
test/golden.json                     vetores-golden gerados pelo JS
```

## Conectar o SAFEBOAT real (para o dev do MAIN)

A UI e o núcleo consomem só o `DeviceAdapter`. Para trocar a simulação pelo barco:

1. Implemente `SafeboatAdapter.start()` em `core/device_adapter.dart` (o esqueleto
   com o WebSocket e o mapeamento da telemetria para `GpsFix` já está lá).
2. Chame `controller.connectDevice(SafeboatAdapter(boatId: ..., wsUrl: ...))`.

Onde roda o núcleo de decisão:
- **Recomendado**: a bordo. O SAFEBOAT manda o snapshot já decidido; o alarme
  vale com o app fechado.
- **Alternativa**: o barco manda fixes crus e o app roda o núcleo Dart localmente
  (é o que o demo faz) — bom para animação suave, mas não substitui a decisão de
  bordo.

## Notificação

Alarme de âncora precisa **furar** o modo silencioso: iOS Critical Alerts, Android
canal de alta prioridade + serviço em primeiro plano. Disparado pelo dispositivo
via relay → FCM/APNs.

## Fonte da verdade

O algoritmo é o mesmo de `../core/anchor-core.js` (validado em `../test-*.cjs`).
Este Dart é um porte fiel; os testes de paridade garantem que assim continue.
