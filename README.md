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

## Built by PurpleSoft

**[PurpleSoft S.r.l.](https://www.purplesoft.io)** — software house with offices in Monza, Milano, and Lugano (Switzerland). Since 2017, we've been the team that companies call when the problem is too hard, too critical, or too late to fail.

> We build what doesn't exist yet.

### What we do

We don't "consult and recommend." We ship. Our engineers write production code across every layer of the stack — from bare-metal native bindings to cloud-native infrastructure, from machine learning pipelines to pixel-perfect mobile UI.

We ship mobile apps that control physical payment terminals via Flutter. We deploy ONNX AI models that run on phones instead of servers. We migrate enterprise ERP systems from SAP ECC to SAP S/4HANA without downtime, moving billions in financial transactions. We build distributed tracing pipelines that survive Black Friday traffic without dropping a single span. We write Flutter plugins for hardware that doesn't have one yet, and Dart packages for observability infrastructure the ecosystem was missing.

---

### Our proprietary SDK portfolio

When off-the-shelf solutions fall short, we build our own. These 10 SDKs are battle-tested across our enterprise projects:

| SDK | Capability |
|-----|-----------|
| **Purple.Authentication** | OAuth 2.0 / OpenID Connect — Google, Apple, Microsoft, Facebook, Instagram, LinkedIn, GitHub, and custom identity providers |
| **Purple.Authorization** | Role-based access control with granular permissions and custom policy rules |
| **Purple.Security** | Post-quantum cryptography using NIST-approved algorithms (CRYSTALS-Kyber, CRYSTALS-Dilithium) |
| **Purple.Payments** | Unified payment abstraction — PayPal, Stripe, SumUp, Nexi, GestPay, Google Pay, Apple Pay, Bitcoin, Ethereum, and 100+ cryptocurrencies |
| **Purple.Notification** | Cross-platform push notifications — iOS (APNs) and Android (FCM) with server-side batching |
| **Purple.Email** | Transactional email and marketing automation — SMTP, SendGrid, MailChimp, MailUp, Sendinblue, MailGun |
| **Purple.Bot** | Multi-platform chatbot integration — Telegram, WhatsApp Business API, Facebook Messenger |
| **Purple.Storage** | Cloud storage abstraction — Azure Blob Storage, Amazon S3, Google Cloud Storage, local filesystem |
| **Purple.Media** | Media processing — compression, format conversion, deduplication, client-side encryption |
| **Purple.Localization** | Multi-platform i18n — Flutter, Angular, VanillaJS, .NET with centralized translation management |

---

### Open source we maintain and contribute to

We don't just consume open source — we build and maintain it:

| Area | What we ship |
|------|-------------|
| **Observability** | Complete OpenTelemetry SDK for Dart/Flutter (traces, logs, metrics, OTLP export), enterprise structured logger with file rotation, auto-instrumentation for HTTP, Dio, and Flutter |
| **On-device AI** | ONNX runtime bindings for Dart with GPU acceleration, Litert/MediaPipe integration for LLM inference, neural text-to-speech (Kokoro engine) across all 6 Flutter platforms |
| **Speech** | Speech-to-text for Android and Windows, wake-word detection, Italian dialect support |
| **Payments** | Official Flutter plugin for SumUp POS terminals (card-present payments, NFC, receipt printing) |
| **Platform** | iOS Live Activities & Dynamic Island, high-performance in-memory cache with journaling, OpenAPI → Dart code generator |
| **Upstream** | Active contributions to HuggingFace Transformers, Microsoft Model Context Protocol SDK (official C# implementation), Ethereum EIP-2535 Diamond standard, ESP-OPUS audio codec |

---

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









