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



## Enterprise Support

This package is developed and maintained by **[PurpleSoft S.r.l.](https://www.purplesoft.io)** — a software house based in Monza, Milano, and Lugano (Switzerland). Since 2017, we've been building the kind of software that other companies call "impossible."

We write the code that runs on factory floors and in boardrooms. We ship Flutter apps that control physical payment terminals, deploy ONNX models to mobile devices that fit in your pocket, and build distributed tracing pipelines that survive Black Friday traffic without dropping a single span. We've migrated ERP systems for multinational manufacturers, trained speech models that understand Italian dialects, and designed caching layers that make API latency disappear.

When a Flutter plugin doesn't exist for the hardware you need, we write it. When your OpenTelemetry collector falls over under load, we fix it. When your AI model needs to run on a phone instead of a server, we make it fit.

Our team spans the full stack — from bare-metal native code to cloud-native infrastructure, from machine learning pipelines to pixel-perfect UI. We don't specialize in one thing. We specialize in solving things that don't have an existing solution.

Trusted by **ABB, Intesa Sanpaolo, Tenaris, Reply, Aubay, Prometeia, Comune di Milano, FIMAP, Altran, BCC,** and 50+ other enterprises across Europe.

[Contact PurpleSoft](https://www.purplesoft.io/cerchi-contatti-software-house-a-monza-e-milano/) · [purplesoft.io](https://www.purplesoft.io) · [developers@purplesoft.io](mailto:developers@purplesoft.io) · [+39 0362 148 3978](tel:+3903621483978)## License

GNU Affero General Public License v3.0 — see [LICENSE](LICENSE).



