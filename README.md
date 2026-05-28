# PurpleOTel Flutter Integration

[![Pub Version](https://img.shields.io/pub/v/purple_otel_flutter.svg)](https://pub.dev/packages/purple_otel_flutter)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

OpenTelemetry auto-instrumentation for Flutter — navigation tracking, lifecycle monitoring, and error capture.

## Features

- **NavigatorObserver** — automatic spans for route push/pop/replace
- **Lifecycle tracking** — app lifecycle state changes captured as spans
- **Error capture** — `FlutterError.onError` and `PlatformDispatcher.onError` captured as spans with stack traces
- **One-line setup** — `FlutterOtelInitializer.initialize(tracerProvider: ...)`

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

  // One-shot setup: captures all unhandled errors as spans
  FlutterOtelInitializer.initialize(tracerProvider: tracerProvider);

  runApp(MyApp(tracerProvider: tracerProvider));
}

class MyApp extends StatelessWidget {
  final TracerProvider tracerProvider;

  const MyApp({super.key, required this.tracerProvider});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Auto-span for every navigation
      navigatorObservers: [
        OtelNavigatorObserver(tracer: tracerProvider.get('navigation')),
      ],
      home: const HomePage(),
    );
  }
}
```

## Components

### OtelNavigatorObserver

```dart
MaterialApp(
  navigatorObservers: [
    OtelNavigatorObserver(tracer: tracerProvider.get('navigation')),
  ],
);
```

| Event | Span Created |
|-------|-------------|
| `didPush` | `navigate_to /screen-name` |
| `didPop` | Span ended with status ok |
| `didReplace` | Old span ended, new span created |

### FlutterOtelInitializer

```dart
FlutterOtelInitializer.initialize(tracerProvider: tracerProvider);
```

Captures and creates spans for:
- `FlutterError.onError` → span with `error.library`, `error.context` attributes
- `PlatformDispatcher.instance.onError` → span with exception + stack trace

### OtelWidgetsBindingObserver

```dart
class _MyWidgetState extends State<MyWidget> with OtelWidgetsBindingObserver {
  _MyWidgetState() : super(tracer: tracerProvider.get('lifecycle'));
}
```

Creates spans for: `lifecycle_resumed`, `lifecycle_paused`, `lifecycle_inactive`, `lifecycle_detached`

## License

Apache-2.0 — see [LICENSE](LICENSE).
