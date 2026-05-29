# PurpleOTel Flutter

[![Pub Version](https://img.shields.io/pub/v/purple_otel_flutter.svg)](https://pub.dev/packages/purple_otel_flutter)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/flutter-%3E%3D3.16.0-blue.svg)](https://flutter.dev)

**OpenTelemetry auto-instrumentation for Flutter — zero-config navigation tracking, lifecycle monitoring, and error capture.**

Stop writing manual spans for every `Navigator.push`, `didChangeAppLifecycleState`, and `FlutterError.onError`. Drop in a single initializer and observer, and every screen transition, lifecycle event, and unhandled exception becomes an OpenTelemetry span automatically.

---

## Features

- **`OtelNavigatorObserver`** — automatic spans for every route push, pop, and replacement. Route names flow into `screen.name` attributes on every span.
- **`OtelWidgetsBindingObserver`** — `AppLifecycleState` transitions (`resumed`, `paused`, `inactive`, `detached`) captured as spans with `app.lifecycle` attributes.
- **`FlutterOtelInitializer`** — captures `FlutterError.onError` and `PlatformDispatcher.instance.onError`, records exception + stack trace + library context, and marks spans as `ERROR`.
- **One-line setup** — `WidgetsBinding.instance.initializeOtel(tracerProvider: …)` wires up error capture before `runApp`.
- **Zero code generation** — no build_runner, no annotations, no source_gen.

---

## Installation

```yaml
dependencies:
  flutter:
    sdk: flutter
  purple_otel_sdk: ^0.1.0
  purple_otel_flutter: ^0.1.0
```

This package depends on [`purple_otel_sdk`](https://pub.dev/packages/purple_otel_sdk) for `TracerProvider`, `Span`, `SpanExporter`, and OTLP export. Configure your SDK first, then wire in the Flutter instrumentation.

---

## Quick Start

```dart
import 'package:flutter/material.dart';
import 'package:purple_otel_sdk/purple_otel_sdk.dart';
import 'package:purple_otel_flutter/purple_otel_flutter.dart';

void main() {
  final tracerProvider = SDKTracerProvider(
    resource: Resource(Attributes.fromMap({'service.name': 'my-flutter-app'})),
    processors: [SimpleSpanProcessor(ConsoleSpanExporter())],
  );

  // Capture unhandled Flutter & platform errors as spans
  FlutterOtelInitializer.initialize(tracerProvider: tracerProvider);

  runApp(MyApp(tracerProvider: tracerProvider));
}

class MyApp extends StatelessWidget {
  final TracerProvider tracerProvider;

  const MyApp({super.key, required this.tracerProvider});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [
        OtelNavigatorObserver(tracer: tracerProvider.get('navigation')),
      ],
      home: const HomePage(),
    );
  }
}
```

With this setup every `Navigator.push`, `Navigator.pop`, `Navigator.pushReplacement`, unhandled `FlutterError`, and platform-level `onError` produces a trace span.

---

## Components

### `OtelNavigatorObserver`

Drop-in `NavigatorObserver` that wraps route transitions in OpenTelemetry spans.

```dart
MaterialApp(
  navigatorObservers: [
    OtelNavigatorObserver(tracer: tracerProvider.get('navigation')),
  ],
  // …
);
```

| Navigator event    | Behavior                                                               |
| ------------------ | ---------------------------------------------------------------------- |
| `didPush`          | Creates span `navigate_to /route-name` with attribute `screen.name`    |
| `didPop`           | Ends the pushed span with status `ok`                                  |
| `didReplace`       | Ends the old route span, creates a new span for the incoming route     |

Span kind is `SpanKind.internal` on every navigation event.

### `FlutterOtelInitializer`

Static initializer that patches Flutter's error handlers. Call once before `runApp`.

```dart
FlutterOtelInitializer.initialize(tracerProvider: tracerProvider);
```

Captured errors:

| Hook                             | Span name         | Attributes                                     |
| -------------------------------- | ----------------- | ---------------------------------------------- |
| `FlutterError.onError`           | `flutter-error`   | `error.library`, `error.context`, `exception.*` |
| `PlatformDispatcher.instance.onError` | `platform-error` | `exception.*`, stack trace                    |

Both produce spans with `SpanStatus.error` and call `span.recordException(…)`.

> After capturing, `FlutterError.presentError` is invoked so the framework's default red-screen-of-death still appears in debug mode.

#### Convenience extension

`FlutterOtelInitializer` is also exposed as an extension on `WidgetsBinding`:

```dart
WidgetsBinding.instance.initializeOtel(tracerProvider: tracerProvider);
```

The two calls are identical — use whichever reads better in your codebase.

### `OtelWidgetsBindingObserver`

Pass-through `WidgetsBindingObserver` that creates spans for every `AppLifecycleState` transition.

```dart
final observer = OtelWidgetsBindingObserver(tracer: tracerProvider.get('lifecycle'));
WidgetsBinding.instance.addObserver(observer);
```

| Lifecycle state  | Span name           | Attribute                   |
| ---------------- | ------------------- | --------------------------- |
| `resumed`        | `lifecycle_resumed` | `app.lifecycle = resumed`   |
| `paused`         | `lifecycle_paused`  | `app.lifecycle = paused`    |
| `inactive`       | `lifecycle_inactive`| `app.lifecycle = inactive`  |
| `detached`       | `lifecycle_detached`| `app.lifecycle = detached`  |

All lifecycle spans are `SpanKind.internal`, end immediately with `SpanStatus.ok`, and carry the `app.lifecycle` attribute for filtering in your observability backend.

---

## Full `MaterialApp` Integration

```dart
import 'package:flutter/material.dart';
import 'package:purple_otel_sdk/purple_otel_sdk.dart';
import 'package:purple_otel_flutter/purple_otel_flutter.dart';

void main() {
  final tracerProvider = SDKTracerProvider(
    resource: Resource(Attributes.fromMap({'service.name': 'my-app'})),
    processors: [
      BatchSpanProcessor(
        OtlpHttpSpanExporter(
          endpoint: Uri.parse('https://otlp.example.com/v1/traces'),
        ),
      ),
    ],
  );

  FlutterOtelInitializer.initialize(tracerProvider: tracerProvider);

  runApp(MyApp(tracerProvider: tracerProvider));
}

class MyApp extends StatelessWidget {
  final TracerProvider tracerProvider;

  const MyApp({super.key, required this.tracerProvider});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PurpleOTel Demo',
      navigatorObservers: [
        OtelNavigatorObserver(tracer: tracerProvider.get('navigation')),
      ],
      home: const HomeScreen(tracerProvider: tracerProvider),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final TracerProvider tracerProvider;

  const HomeScreen({super.key, required this.tracerProvider});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final OtelWidgetsBindingObserver _lifecycleObserver;

  @override
  void initState() {
    super.initState();
    _lifecycleObserver = OtelWidgetsBindingObserver(
      tracer: widget.tracerProvider.get('lifecycle'),
    );
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                settings: const RouteSettings(name: '/details'),
                builder: (_) => const DetailsScreen(),
              ),
            );
          },
          child: const Text('Go to Details'),
        ),
      ),
    );
  }
}

class DetailsScreen extends StatelessWidget {
  const DetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Details')),
      body: const Center(child: Text('Details page')),
    );
  }
}
```

---

## Before & After

### Before — manual instrumentation

```dart
// Manual error handler wiring
FlutterError.onError = (details) {
  final span = tracer.startSpan('flutter-error');
  span.recordException(details.exception, stackTrace: details.stack);
  span.setStatus(SpanStatus.error(details.exceptionAsString()));
  span.end();
  FlutterError.presentError(details);
};

PlatformDispatcher.instance.onError = (error, stack) {
  final span = tracer.startSpan('platform-error');
  span.recordException(error, stackTrace: stack);
  span.setStatus(SpanStatus.error(error.toString()));
  span.end();
  return true;
};

// Manual navigation spans on every push/pop
Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsScreen())).then((_) {
  final span = tracer.startSpan('navigate_to /details');
  span.setAttribute('screen.name', '/details');
  span.end();
});

// Manual lifecycle hook in every StatefulWidget
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  final span = tracer.startSpan('lifecycle_${state.name}');
  span.setAttribute('app.lifecycle', state.name);
  span.end();
}
```

### After — with `purple_otel_flutter`

```dart
void main() {
  final tp = SDKTracerProvider(/* … */);
  FlutterOtelInitializer.initialize(tracerProvider: tp);        // ← errors
  runApp(MaterialApp(
    navigatorObservers: [
      OtelNavigatorObserver(tracer: tp.get('navigation')),      // ← nav
    ],
    home: const HomePage(),
  ));
}

// Lifecycle observer: add once in initState, remove once in dispose
final _obs = OtelWidgetsBindingObserver(tracer: tp.get('lifecycle'));
WidgetsBinding.instance.addObserver(_obs);
```

Three composable pieces. No per-screen boilerplate. No copy-pasted error handlers.

---

## Companion Packages

| Package                                                                 | Purpose                                           |
| ----------------------------------------------------------------------- | ------------------------------------------------- |
| [`purple_otel_sdk`](https://pub.dev/packages/purple_otel_sdk)           | OpenTelemetry SDK — traces, logs, metrics, OTLP   |
| [`purple_otel_api`](https://pub.dev/packages/purple_otel_api)           | OpenTelemetry API types — `Span`, `Tracer`, etc.  |

---

---

---

---

---


---

## Built by PurpleSoft

**[PurpleSoft S.r.l.](https://www.purplesoft.io)** — software house with offices in Monza, Milano, and Lugano (Switzerland). Since 2017.

> We build what doesn't exist yet.

### The sectors we dominate

**Conversational AI & Voice Assistants.** We design and ship end-to-end AI voice platforms — from the physical device (ESP32 with custom Opus codec firmware) to the cloud backend (.NET 10, ASP.NET Core, Blazor Server) to the mobile companion app (Flutter with BLE). Our multi-agent LLM architecture orchestrates 8 specialized agents (conversation, memory, content enrichment, exploration, and more) with a multi-layered memory system spanning graph, episodic, and working memory — including adaptive forgetting, poison detection via z-score outlier analysis, and automatic episodic-to-semantic compression. We deploy DeepSeek V4 for primary inference at 53x lower cost than GPT-4o, with multi-provider fallback across OpenAI, Anthropic, Gemini, and Ollama. Our scientific research pipeline uses a 4-scorer verification chain (NLI dual-label, cross-model consistency, evidence retrieval, hallucination detection) with consensus voting to ensure factual accuracy. We design RAG pipelines with HNSW vector search (1024-dim embeddings), hybrid full-text + semantic RRF, sharded K-means search, and training-free chunk pre-filtering.

**Fintech & Payments.** We build payment orchestration layers that abstract Stripe, SumUp, Nexi, Axerve, PayPal, Google Pay, and Apple Pay behind a single API — plus Bitcoin, Ethereum, and 100+ cryptocurrencies. Our engineers have shipped POS terminal firmware, fiscal receipt systems compliant with Italian *Fattura Elettronica* regulations, and cash register management platforms processing millions of transactions.

**Cybersecurity & Identity.** We ship post-quantum cryptography implementations using NIST-standardized algorithms on .NET 10 (ML-KEM, ML-DSA, SLH-DSA) — the cryptography standard that will replace RSA and ECC. Our authentication infrastructure integrates SPID (Italian public digital identity), OAuth 2.0/OpenID Connect across Google, Apple, Microsoft, Facebook, Instagram, LinkedIn, and GitHub. We build digital signature platforms with PKCS#11 hardware security module support, handling the full envelope lifecycle from document preparation to legally binding execution.

**Artificial Intelligence & On-Device ML.** We deploy ONNX models to phones via custom Dart runtime bindings with GPU acceleration. We integrate Litert and MediaPipe for on-device LLM inference. We build neural text-to-speech engines that run across all 6 Flutter platforms — from Android to Web — and speech recognition systems with Italian dialect support. We design content intelligence pipelines that ingest, enrich via LLM, embed (1024-dim vectors), and serve via hybrid semantic search — at scale: 28,000 items enriched, 30,000 embeddings generated, 14 pipelines with 3 stages each (scrape → enrich → embed). DeepSeek V4 Pro processes content enrichment at a fraction of the cost of GPT-4o.

**Enterprise SaaS & Cloud-Native Architecture.** We architect, build, and operate platforms at enterprise scale. Our .NET 10 monorepo spans 239 C# projects with consistent Azure Pipelines CI/CD, 297 test suites passing, zero build errors. We design multi-engine database abstraction layers (PostgreSQL + pgvector, MySQL, Microsoft SQL Server) with automated schema-to-code generation that produces complete ASP.NET API controllers. Our notification engine handles 6 channels (email, push, SMS, chat, webhook, in-app) with DNS-based email validation and template management. Our audio SDK provides unified TTS/STT across ElevenLabs, DashScope, DeepGram, Whisper, and Windows Speech with Opus/OGG codec support and real-time streaming.

**IoT & Embedded Systems.** We write ESP32 firmware targeting ESP-IDF v5.4 with 21 FreeRTOS tasks, I²S audio pipelines, Opus codec integration, and a 6-state WiFi state machine with validated recovery paths. We build certificate authority infrastructure that generates and manages device TLS certificates with challenge-response verification. We write native Flutter plugins for hardware that doesn't have one yet — from payment terminals to BLE device provisioning to audio codecs.

**Observability & DevOps.** Full-stack observability is the foundation we build our client solutions on. We ship a complete OpenTelemetry SDK for Dart/Flutter (traces, logs, metrics, W3C propagation, OTLP export), enterprise structured logging with file rotation, and auto-instrumentation for HTTP, Dio, and Flutter navigation — all red-team audited with 256 automated tests.

### The technologies we master

Our engineering team works across the full stack — from ESP32 firmware in C to cloud-native backends in C# (.NET 10) to cross-platform mobile apps in Dart/Flutter. We write production code in **C# (.NET 10)**, **Dart**, **TypeScript**, **JavaScript**, **C**, **C++**, **Python**, and **Rust**. Our frameworks of choice are **ASP.NET Core**, **Blazor Server**, **Flutter**, **Angular**, and **React**. Our AI stack spans **DeepSeek**, **OpenAI**, **Anthropic Claude**, **Google Gemini**, **Ollama**, **Microsoft Semantic Kernel**, and **Microsoft Agents.AI**. We operate **Microsoft Azure** (Key Vault, Blob Storage, Resource Manager, IoT Hub, Virtual Machines), deploy on **NGINX**, and manage **PostgreSQL + pgvector**, **MySQL**, **Microsoft SQL Server**, and **ESP-IDF v5.4** at scale. We use **EF Core** with **Npgsql** for data access, **FFmpeg** for audio processing, **LVGL** for embedded displays, and **BLE** for device provisioning. Our CI/CD runs on **Azure Pipelines**.

### Microsoft Partner since 2018 · SumUp Partner · Dell Partner

---

### Trusted by

`ABB` `Intesa Sanpaolo` `Tenaris` `Reply` `Aubay` `Comune di Milano` `BCC` `FIMAP` `Alten` `Altran` `Prometeia` `illimity` `Be Shaping the Future` `DS Group` `NVALUE` `Inoptim` `Docflow` `P&C`

*and 40+ other enterprises across banking, manufacturing, energy, and public sector.*

---

> Your project can't wait. We've solved these exact problems for companies you know.
> Let's solve them for you.

[🌐 **purplesoft.io**](https://www.purplesoft.io) &nbsp;·&nbsp; [📧 **developers@purplesoft.io**](mailto:developers@purplesoft.io) &nbsp;·&nbsp; [📞 **+39 0362 148 3978**](tel:+3903621483978) &nbsp;·&nbsp; [💼 **LinkedIn**](https://www.linkedin.com/company/purplesoft-srl) &nbsp;·&nbsp; [🐙 **GitHub**](https://github.com/purplesoftsrl)

## License

GNU Affero General Public License v3.0 — see [LICENSE](LICENSE).











