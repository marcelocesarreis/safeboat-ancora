# SAFEBOAT — Âncora Virtual

Vigília de fundeio (anchor watch) do app SAFEBOAT. Detecta quando o barco
**garra** (a âncora arrasta) ou quando **rompe a poita**, sem acordar ninguém à
toa. Feito **fora da MAIN**, com o dispositivo **simulado**, e organizado para
plugar o SAFEBOAT real depois trocando um único arquivo.

> **A diferença que muda o projeto inteiro:** o SAFEBOAT é um dispositivo **fixo
> a bordo**. Os apps de âncora de celular usam o próprio celular como sensor —
> quando o dono desce em terra, o sensor sai junto e a vigília acaba. O SAFEBOAT
> vigia 24/7 com o app fechado; só a **notificação** viaja para o celular.

---

## O problema, em uma frase

O erro do GPS (~15–20 m de deriva ao longo de horas num receptor comum; ~3 m com
correção SBAS) é da **mesma ordem** do que se quer medir (um raio de giro de
30–50 m). Apertar o raio → alarme falso às 3h da manhã. Afrouxar → o alarme toca
tarde demais. Todo o projeto gira em torno de resolver essa tensão — e é aí que o
dispositivo de bordo ganha dos apps de celular.

## O que o SAFEBOAT faz que os melhores apps não fazem

Pesquisa comparativa dos apps mais bem avaliados (Anchor Pro, Anchor! do Fabian
Weber, DragQueen, Anchor Watch, Savvy Navvy, Vesper Cortex, Signal K, Maretron,
Yacht Devices) e das queixas de usuários (YBW, Cruisers Forum, Sailing Anarchy,
App Store). O que ficou no núcleo:

| Técnica | Apps de celular | SAFEBOAT |
|---|---|---|
| Círculo centrado na **âncora** (não na antena) | poucos | ✅ offset antena→proa por rumo |
| **Scope pitagórico** `√(amarra² − (prof+roleta)²)` | só os avançados (Signal K/Maretron) | ✅ |
| **Filtro de posição** antes de alarmar | os bons (Anchor! usa 5 fixes) | ✅ persistência + porta de velocidade |
| **Gate por precisão do GPS (HDOP)** | *"ninguém faz isso"* (pesquisa) | ✅ limite se alarga com GPS ruim |
| **Detector de deriva do centro** (radial vs tangencial) | nenhum | ✅ pega garrada lenta que nem sai do raio |
| **Estimar a âncora pelo arco de giro** | impossível no celular (só está a bordo às vezes) | ✅ `anchorFromTrack` |
| **Rastro da noite** (breadcrumb) | os bons | ✅ |
| Vigília com **app fechado / dono em terra** | falha silenciosa (OS mata o app) | ✅ decidido a bordo |
| GPS **abaixo do convés** (casco de metal) | queixa recorrente | ✅ antena fixa bem instalada |

O detector de deriva do centro é o pulo do gato. Vento rondando ou maré
invertendo movem o barco **tangencialmente** (ele dá a volta na âncora); a âncora
garrando o empurra **radialmente** (para longe do ponto). Separar esses dois é o
que derruba a queixa nº 1 dos apps — *"acordei 3h da manhã e o barco estava no
lugar"* — sem deixar passar a garrada lenta que nem chega a sair do raio.

---

## Arquitetura

```
core/anchor-core.js     Núcleo puro: geometria, filtro, máquina de estados,
                        detector de deriva, ajuste de círculo. Sem I/O, sem DOM.
                        Roda igual no navegador, no Node e serve de referência
                        para o firmware do SAFEBOAT e o app Flutter.

core/sim-device.js      Barco simulado: física de fundeio + os fenômenos que
                        fazem os alarmes tocar à toa (guinada, rajada, ronda de
                        vento, maré, multipath) e os que TÊM que alarmar (garrar,
                        romper poita). Saída idêntica à do SAFEBOAT real.

core/device-adapter.js  A COSTURA. SimAdapter (protótipo) e SafeboatAdapter
                        (stub do hardware real). Trocar um pelo outro é a única
                        mudança para conectar um barco de verdade.

public/                 Protótipo navegável fiel ao design do app (porta 8101):
                        mapa ao vivo, rastro, métricas, simulador de cenários.

flutter/                Código Dart pronto para o dev anexar ao MAIN
                        (models + service com os pontos de conexão marcados).

test-scenarios.cjs      Bancada: roda cada cenário e verifica o esperado.
test-sweep.cjs          Varredura de robustez: N sementes × 2 tipos de barco.
```

### Contrato de um fix (o que todo dispositivo entrega)

```js
{ t, lat, lon, accuracy, heading, cog, sog, depth, novalid }
```

O SAFEBOAT real pode entregar **fixes crus** (o app roda o núcleo para animar) ou
o **snapshot já decidido** a bordo (recomendado — o alarme vale com o app
fechado). Ambos os caminhos estão previstos no `AnchorService` do Flutter.

---

## Como rodar o protótipo

```bash
node server.cjs        # http://localhost:8101   (launch.json: "safeboat-ancora")
```

Na barra **Simulador de dispositivo**, escolha um cenário. Os verdes/neutros não
podem alarmar; os vermelhos (garrando / poita rompida) têm que alarmar. Ative o
alarme (define raio → lança âncora → dá ré para cravar → vigia) e observe o mapa:
o círculo tracejado é o raio, a trilha azul é o rastro, o pino é a âncora
estimada, e o círculo branco pontilhado é a âncora **real** da simulação (para
comparar). Velocidade 30×/60×/120× acelera o mar.

## Validação

```bash
node test-scenarios.cjs            # 10 cenários, checagem do comportamento
node test-sweep.cjs 20             # 20 sementes × 2 barcos × 90 min cada
```

Resultado atual da varredura (280 fundeios benignos + 120 garradas):

```
falsos alarmes: 0/280     garradas não detectadas: 0
Garrando de verdade   →  alarme com ~15 m de garrada em ~16 min
Garrando devagar      →  alarme com ~15 m em ~45 min (pelo centro migrando)
Poita rompida         →  alarme com ~20 m em ~15 min
```

**Zero falso alarme** em noite calma, rajadas até 35 nós, ronda de vento de 180°,
inversão de maré, multipath de cais e volta completa na poita — tanto para lancha
(fica quieta) quanto para veleiro (veleja muito no fundeio).

---

## Parâmetros (todos em `DEFAULTS` do núcleo)

| Parâmetro | Padrão | O que é |
|---|---|---|
| `confirmSeconds` | 45 s | tempo fora do raio (contínuo) para confirmar garrada |
| `prealarmFraction` | 0,85 | fração do raio que acende a atenção |
| `driftWindowMin` | 20 min | janela do detector de deriva do centro |
| `driftThreshold` | 0,15 | fração do raio que o centro pode migrar antes de alarmar |
| `accuracyLimit` | 25 m | acima disso a posição é ruim (vira aviso de sinal) |
| `speedGate` | 4,1 m/s | salto acima disso entre fixes = multipath, descarta |
| `holdOffSeconds` | 90 s | carência após armar (deixa o barco assentar) |
| `autoFitAnchor` | true | refina a âncora pelo arco de giro (com travas anti-perseguição) |

Raio calculado: `√(amarra² − (prof + roleta)²) + comprimento do barco + folga GPS`.
Se o usuário fixa `alarmRadius`, esse manda.

---

## Conectar o SAFEBOAT real (para o dev do MAIN)

1. **`core/device-adapter.js` → `SafeboatAdapter.start()`**: abrir o WebSocket do
   dispositivo (Wi-Fi do barco) ou do relay (nuvem) e mapear a mensagem de
   telemetria para o contrato de fix. O esqueleto e o exemplo já estão no arquivo.
2. **`flutter/.../services/anchor_service.dart`**: `connect()` e `_command()` têm
   os `TODO(dev)` com o WS e o POST no relay prontos para descomentar.
3. **Onde roda o núcleo**: idealmente **a bordo** (o SAFEBOAT decide e manda o
   snapshot), para o alarme valer com o app fechado. O mesmo `anchor-core.js`
   pode ser portado para o firmware — é puro, sem dependência, e foi escrito
   pensando em microcontrolador (filtro leve, sem matriz pesada).
4. **Push**: o alarme decidido a bordo dispara a notificação via relay → FCM/APNs,
   com **Critical Alert** no iOS (fura o modo silencioso — obrigatório para
   alarme de âncora) e canal de alta prioridade + serviço em primeiro plano no
   Android.

### Evoluções previstas (ganchos já no núcleo)

- **Anemômetro a bordo**: separar "amarra esticando com o vento" de "garrando"
  *antes* de o barco passar do limite físico da amarra (hoje isso é inferido pela
  saturação da amarra). O núcleo já recebe vento no fix — é só usar.
- **Sonda (profundidade)**: recomputar o scope com a maré em tempo real (o núcleo
  já atualiza `depth` no estado SETTING).
- **AIS**: alertar quando *outro* barco garra em cima do seu.
- **Compartilhar com a tripulação**: um link de navegador com o estado ao vivo
  (o snapshot já é serializável).

---

## Relação com os outros módulos SAFEBOAT

Mesma arquitetura das **câmeras** (dispositivo de bordo → relay na nuvem → app,
fonte local no Wi-Fi / remota no 4G) e do sensor **VIB** de vibração. A Âncora
Virtual entra no dashboard entre o card de câmeras e os motores, com o mesmo
design (fundo `#1E2A49`, verde `#A5CB74`, Poppins).
