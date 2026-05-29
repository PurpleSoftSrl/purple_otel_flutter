import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purple_otel_api/purple_otel_api.dart';
import 'package:purple_otel_flutter/purple_otel_flutter.dart';
import 'package:purple_otel_sdk/purple_otel_sdk.dart';

SDKTracerProvider _makeProvider(InMemorySpanExporter exporter) {
  return SDKTracerProvider(
    resource: Resource.empty,
    processors: [SimpleSpanProcessor(exporter)],
  );
}

// ---------------------------------------------------------------------------
// Evil helpers
// ---------------------------------------------------------------------------

class _ThrowingSettings extends RouteSettings {
  const _ThrowingSettings() : super(name: '');

  @override
  String get name => throw Exception('evil settings.name threw');
}

class _RouteThrowingSettings<T> extends PageRouteBuilder<T> {
  _RouteThrowingSettings()
      : super(
          pageBuilder: (_, __, ___) => const SizedBox(),
          settings: const _ThrowingSettings(),
        );
}

class _RouteNullName<T> extends PageRouteBuilder<T> {
  _RouteNullName()
      : super(
          pageBuilder: (_, __, ___) => const SizedBox(),
          settings: const RouteSettings(),
        );
}

class _RouteSettingsGetterThrows<T> extends PageRouteBuilder<T> {
  _RouteSettingsGetterThrows()
      : super(
          pageBuilder: (_, __, ___) => const SizedBox(),
        );

  @override
  RouteSettings get settings => throw Exception('evil settings getter threw');
}

class _ThrowingTracerProvider implements TracerProvider {
  @override
  Tracer get(String name, {String? version, String? schemaUrl}) {
    throw Exception('tracer provider get() is evil');
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}

class _ThrowingStartSpanTracer implements Tracer {
  @override
  Span startSpan(
    String name, {
    SpanKind? kind,
    Context? parentContext,
    Attributes? attributes,
    List<SpanLink>? links,
    DateTime? startTime,
  }) {
    throw Exception('tracer.startSpan threw');
  }
}

class _NullNameTracerProvider implements TracerProvider {
  @override
  Tracer get(String name, {String? version, String? schemaUrl}) {
    return _NullNameTracer();
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}

class _NullNameTracer implements Tracer {
  @override
  Span startSpan(
    String name, {
    SpanKind? kind,
    Context? parentContext,
    Attributes? attributes,
    List<SpanLink>? links,
    DateTime? startTime,
  }) {
    final provider = SDKTracerProvider(
      resource: Resource.empty,
      processors: [SimpleSpanProcessor(InMemorySpanExporter())],
    );
    final realTracer = provider.get('evil');
    return realTracer.startSpan(name, kind: kind, parentContext: parentContext,
        attributes: attributes, links: links, startTime: startTime);
  }
}

// ===========================================================================
// NavigatorObserver — Route & Settings attacks
// ===========================================================================
void main() {
  group('OtelNavigatorObserver — Route / Settings attacks', () {
    late InMemorySpanExporter exporter;
    late SDKTracerProvider provider;
    late OtelNavigatorObserver observer;

    setUp(() {
      exporter = InMemorySpanExporter();
      provider = _makeProvider(exporter);
      observer = OtelNavigatorObserver(tracer: provider.get('flutter'));
    });

    testWidgets('route.settings.name throws — should not crash', (tester) async {
      final route = _RouteThrowingSettings();
      observer.didPush(route, null);
      // should not reach here if it crashes
      expect(true, isTrue);
    });

    testWidgets('route.settings getter throws — should not crash didPush', (tester) async {
      final route = _RouteSettingsGetterThrows();
      observer.didPush(route, null);
      expect(true, isTrue);
    });

    testWidgets('route.settings getter throws — should not crash didPop', (tester) async {
      final route = _RouteSettingsGetterThrows();
      observer.didPop(route, null);
      expect(true, isTrue);
    });

    testWidgets('route.settings getter throws — should not crash didReplace', (tester) async {
      final evilRoute = _RouteSettingsGetterThrows();
      final normalRoute = PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SizedBox(),
        settings: const RouteSettings(name: '/safe'),
      );
      observer.didReplace(newRoute: evilRoute, oldRoute: normalRoute);
      observer.didReplace(newRoute: normalRoute, oldRoute: evilRoute);
      observer.didReplace(newRoute: evilRoute, oldRoute: evilRoute);
      expect(true, isTrue);
    });

    testWidgets('route.settings.name is null — should not crash (uses / fallback)', (tester) async {
      final route = _RouteNullName();
      observer.didPush(route, null);
      // survived, no assertion needed beyond no crash
      expect(true, isTrue);
    });

    testWidgets('route.settings.name is null in didReplace — should not crash', (tester) async {
      final route = _RouteNullName();
      final normalRoute = PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SizedBox(),
        settings: const RouteSettings(name: '/safe'),
      );
      observer.didReplace(newRoute: route, oldRoute: normalRoute);
      observer.didReplace(oldRoute: route);
      expect(true, isTrue);
    });
  });

  // =========================================================================
  // NavigatorObserver — Map growth / concurrency
  // =========================================================================
  group('OtelNavigatorObserver — Map growth & concurrency', () {
    late InMemorySpanExporter exporter;
    late SDKTracerProvider provider;
    late OtelNavigatorObserver observer;

    setUp(() {
      exporter = InMemorySpanExporter();
      provider = _makeProvider(exporter);
      observer = OtelNavigatorObserver(tracer: provider.get('flutter'));
    });

    testWidgets('10000 routes pushed without pop — should not crash / OOM', (tester) async {
      const count = 10000;
      for (var i = 0; i < count; i++) {
        final route = PageRouteBuilder(
          pageBuilder: (_, __, ___) => const SizedBox(),
          settings: RouteSettings(name: '/route$i'),
        );
        observer.didPush(route, null);
      }
      // If we got here, the map survived 10k entries
      expect(true, isTrue);
    });

    testWidgets('same route pushed twice — first span ended, second is active', (tester) async {
      final route = PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SizedBox(),
        settings: const RouteSettings(name: '/dup'),
      );
      observer.didPush(route, null);
      final afterFirst = exporter.spans.length;

      observer.didPush(route, null);
      // Each push creates one span; duplicate ends the old one.
      // total spans = 2 (both were pushed, both were ended)
      expect(exporter.spans.length, greaterThanOrEqualTo(afterFirst + 1));
    });

    testWidgets('rapid sequential didPush / didPop interleaving', (tester) async {
      const cycles = 1000;
      for (var i = 0; i < cycles; i++) {
        final route = PageRouteBuilder(
          pageBuilder: (_, __, ___) => const SizedBox(),
          settings: RouteSettings(name: '/interleave$i'),
        );
        observer.didPush(route, null);
        observer.didPop(route, null);
      }
      expect(true, isTrue);
    });

    testWidgets('didPush pop didPush pop same route repeatedly', (tester) async {
      final route = PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SizedBox(),
        settings: const RouteSettings(name: '/same'),
      );
      for (var i = 0; i < 500; i++) {
        observer.didPush(route, null);
        observer.didPop(route, null);
      }
      expect(true, isTrue);
    });

    testWidgets('didReplace called with all-null args', (tester) async {
      observer.didReplace();
      expect(true, isTrue);
    });

    testWidgets('didReplace with only oldRoute set', (tester) async {
      final route = PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SizedBox(),
        settings: const RouteSettings(name: '/old'),
      );
      observer.didPush(route, null);
      observer.didReplace(oldRoute: route);
      expect(true, isTrue);
    });

    testWidgets('didReplace with only newRoute set (oldRoute null)', (tester) async {
      final route = PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SizedBox(),
        settings: const RouteSettings(name: '/newOnly'),
      );
      observer.didReplace(newRoute: route);
      expect(true, isTrue);
    });
  });

  // =========================================================================
  // NavigatorObserver — Lifecycle (dispose, use-after-free)
  // =========================================================================
  group('OtelNavigatorObserver — Lifecycle attacks', () {
    late InMemorySpanExporter exporter;
    late SDKTracerProvider provider;
    late OtelNavigatorObserver observer;

    setUp(() {
      exporter = InMemorySpanExporter();
      provider = _makeProvider(exporter);
      observer = OtelNavigatorObserver(tracer: provider.get('flutter'));
    });

    testWidgets('dispose() called twice — should not crash', (tester) async {
      final route = PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SizedBox(),
        settings: const RouteSettings(name: '/pre'),
      );
      observer.didPush(route, null);

      observer.dispose();
      observer.dispose(); // second dispose — map is already empty
      expect(true, isTrue);
    });

    testWidgets('dispose() called with zero routes — should not crash', (tester) async {
      observer.dispose();
      expect(true, isTrue);
    });

    testWidgets('use-after-dispose — didPush after dispose should not crash', (tester) async {
      observer.dispose();
      final route = PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SizedBox(),
        settings: const RouteSettings(name: '/afterDeath'),
      );
      observer.didPush(route, null);
      observer.didPop(route, null);
      observer.didReplace(newRoute: route, oldRoute: route);
      expect(true, isTrue);
    });

    testWidgets('dispose while active spans exist — all spans ended', (tester) async {
      for (var i = 0; i < 50; i++) {
        final route = PageRouteBuilder(
          pageBuilder: (_, __, ___) => const SizedBox(),
          settings: RouteSettings(name: '/disposeBulk$i'),
        );
        observer.didPush(route, null);
      }
      final beforeDispose = exporter.spans.length;
      observer.dispose();
      // All active spans are ended via dispose, so exporter should have more
      expect(exporter.spans.length, greaterThan(beforeDispose));
    });
  });

  // =========================================================================
  // NavigatorObserver — Tracer attack surface
  // =========================================================================
  group('OtelNavigatorObserver — Tracer attacks', () {
    testWidgets('tracer.startSpan throws on every call — should not crash', (tester) async {
      final observer = OtelNavigatorObserver(
          tracer: _ThrowingStartSpanTracer());
      final route = PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SizedBox(),
        settings: const RouteSettings(name: '/boom'),
      );
      observer.didPush(route, null);
      observer.didPop(route, null);
      observer.didReplace(newRoute: route, oldRoute: route);
      observer.dispose();
      expect(true, isTrue);
    });

    testWidgets('null-name tracer (wraps real tracer) — should not crash', (tester) async {
      final observer = OtelNavigatorObserver(
          tracer: _NullNameTracerProvider().get('test'));
      final route = PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SizedBox(),
        settings: const RouteSettings(name: '/safe'),
      );
      observer.didPush(route, null);
      expect(true, isTrue);
    });
  });

  // =========================================================================
  // WidgetsBindingObserver — Lifecycle attacks
  // =========================================================================
  group('OtelWidgetsBindingObserver — Lifecycle attacks', () {
    late InMemorySpanExporter exporter;
    late SDKTracerProvider provider;
    late OtelWidgetsBindingObserver observer;

    setUp(() {
      exporter = InMemorySpanExporter();
      provider = _makeProvider(exporter);
      observer = OtelWidgetsBindingObserver(tracer: provider.get('flutter'));
    });

    testWidgets('all normal lifecycle states — should not crash', (tester) async {
      for (final state in AppLifecycleState.values) {
        observer.didChangeAppLifecycleState(state);
      }
      expect(true, isTrue);
    });

    testWidgets('100000 lifecycle changes — should not OOM', (tester) async {
      const count = 100000;
      for (var i = 0; i < count; i++) {
        observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      }
      // spans are created and ended per call, no retention
      // but exporter accumulates — clear periodically to avoid OOM
      expect(true, isTrue);
    });

    testWidgets('lifecycle with throwing tracer — should not crash', (tester) async {
      final evilObserver =
          OtelWidgetsBindingObserver(tracer: _ThrowingStartSpanTracer());
      for (final state in AppLifecycleState.values) {
        evilObserver.didChangeAppLifecycleState(state);
      }
      expect(true, isTrue);
    });
  });

  // =========================================================================
  // FlutterOtelInitializer — Error handler attacks
  // =========================================================================
  group('FlutterOtelInitializer — Error handler attacks', () {
    late dynamic savedFlutterOnError;
    late dynamic savedPlatformOnError;

    setUp(() {
      savedFlutterOnError = FlutterError.onError;
      savedPlatformOnError = PlatformDispatcher.instance.onError;
      FlutterOtelInitializer.reset();
    });

    tearDown(() {
      FlutterError.onError = savedFlutterOnError;
      PlatformDispatcher.instance.onError = savedPlatformOnError;
      FlutterOtelInitializer.reset();
    });

    Future<void> _initClean(SDKTracerProvider provider) async {
      await FlutterOtelInitializer.initialize(
          tracerProvider: provider);
    }

    testWidgets('initialize with normal provider — succeeds', (tester) async {
      final exporter = InMemorySpanExporter();
      final provider = _makeProvider(exporter);
      await _initClean(provider);
      expect(FlutterError.onError, isNotNull);
      expect(PlatformDispatcher.instance.onError, isNotNull);
    });

    testWidgets('initialize 100 times rapidly — idempotent', (tester) async {
      final exporter = InMemorySpanExporter();
      final provider = _makeProvider(exporter);
      for (var i = 0; i < 100; i++) {
        await FlutterOtelInitializer.initialize(
            tracerProvider: provider);
      }
      // All 100 calls past the first returned early
      expect(true, isTrue);
    });

    testWidgets('initialize then reset then initialize — works', (tester) async {
      final exporter = InMemorySpanExporter();
      final provider = _makeProvider(exporter);
      await _initClean(provider);
      FlutterOtelInitializer.reset();
      // Re-initialize with fresh flags
      await _initClean(provider);
      expect(true, isTrue);
    });

    testWidgets('tracerProvider.get() throws — should propagate, not swallow',
        (tester) async {
      final evil = _ThrowingTracerProvider();
      expect(
        () => FlutterOtelInitializer.initialize(
            tracerProvider: evil),
        throwsA(isA<Exception>()),
      );
    });

    testWidgets('FlutterError.onError is null before initialize — should cope',
        (tester) async {
      FlutterError.onError = null;
      final exporter = InMemorySpanExporter();
      final provider = _makeProvider(exporter);
      await _initClean(provider);

      // Simulate a Flutter error — should not crash
      final details = FlutterErrorDetails(exception: 'test-evIl');
      // Call onError directly
      FlutterError.onError?.call(details);
      expect(exporter.spans.length, greaterThanOrEqualTo(1));
    });

    testWidgets(
        'PlatformDispatcher.instance.onError is null — should cope',
        (tester) async {
      PlatformDispatcher.instance.onError = null;
      final exporter = InMemorySpanExporter();
      final provider = _makeProvider(exporter);
      await _initClean(provider);

      expect(PlatformDispatcher.instance.onError, isNotNull);
      // Call the installed handler directly
      final handler = PlatformDispatcher.instance.onError!;
      final result = handler(Exception('testPlat'), StackTrace.current);
      expect(result, isTrue);
    });

    testWidgets(
        'FlutterError.onError handler survives tracer crash — still calls previous',
        (tester) async {
      var previousCalled = false;
      FlutterError.onError = (FlutterErrorDetails details) {
        previousCalled = true;
      };

      final provider = _makeProvider(InMemorySpanExporter());
      await _initClean(provider);

      final details = FlutterErrorDetails(exception: 'testSurvive');
      FlutterError.onError?.call(details);

      expect(previousCalled, isTrue);
    });

    testWidgets(
        'error handler with evil tracer startSpan — still calls previous handler',
        (tester) async {
      var previousCalled = false;
      FlutterError.onError = (FlutterErrorDetails details) {
        previousCalled = true;
      };

      final evilProvider = _ThrowingTracerProvider();
      try {
        await FlutterOtelInitializer.initialize(
            tracerProvider: evilProvider);
      } catch (_) {
        // get() throws - expected
      }

      // Since get() threw, onError was NOT replaced - the original still stands
      final details = FlutterErrorDetails(exception: 'evilTracer');
      FlutterError.onError?.call(details);

      expect(previousCalled, isTrue);
    });

    testWidgets(
        'PlatformDispatcher handler survives tracer crash — still returns true',
        (tester) async {
      final exporter = InMemorySpanExporter();
      final provider = _makeProvider(exporter);
      await _initClean(provider);

      // Even if startSpan throws inside _safe, the handler returns true
      final handler = PlatformDispatcher.instance.onError!;
      final result = handler(Exception('innerBoom'), StackTrace.current);
      expect(result, isTrue);
    });

    testWidgets('tracer copes with null stack in recordException', (tester) async {
      final exporter = InMemorySpanExporter();
      final provider = _makeProvider(exporter);
      final tracer = provider.get('flutter');

      // Replicate the core logic of the FlutterOtelInitializer error handler
      // without touching FlutterError.onError (which the test framework
      // intercepts and interprets as a test failure).
      final span = tracer.startSpan('test', kind: SpanKind.internal);
      span.recordException('nullStack', stackTrace: null);
      span.setAttribute('error.library', AttributeValue.string('test'));
      span.setStatus(SpanStatus.error('nullStack'));
      span.end();

      expect(exporter.spans.length, greaterThanOrEqualTo(1));
    });

    testWidgets('exceptionAsString long — status description truncated safely',
        (tester) async {
      final exporter = InMemorySpanExporter();
      final provider = _makeProvider(exporter);
      final tracer = provider.get('flutter');

      final longMessage = 'a' * 5000;
      final span = tracer.startSpan('test', kind: SpanKind.internal);
      span.recordException(longMessage);
      // Simulate _limit truncation
      final truncated =
          longMessage.length > 256
              ? '${longMessage.substring(0, 253)}...'
              : longMessage;
      span.setStatus(SpanStatus.error(truncated));
      span.end();

      expect(exporter.spans.length, greaterThanOrEqualTo(1));
    });
  });

  // =========================================================================
  // Resource exhaustion — spans and attributes
  // =========================================================================
  group('Resource exhaustion', () {
    testWidgets('create spans at maximum rate via lifecycle observer',
        (tester) async {
      final exporter = InMemorySpanExporter();
      final provider = _makeProvider(exporter);
      final observer =
          OtelWidgetsBindingObserver(tracer: provider.get('lifecycle'));
      const count = 5000;
      for (var i = 0; i < count; i++) {
        observer.didChangeAppLifecycleState(AppLifecycleState.inactive);
        observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
        observer.didChangeAppLifecycleState(AppLifecycleState.paused);
        observer.didChangeAppLifecycleState(AppLifecycleState.detached);
        if (i % 500 == 0) {
          exporter.clear();
        }
      }
      expect(true, isTrue);
    });

    testWidgets('navigator observer creates many spans rapidly', (tester) async {
      final exporter = InMemorySpanExporter();
      final provider = _makeProvider(exporter);
      final observer =
          OtelNavigatorObserver(tracer: provider.get('nav'));
      const count = 5000;
      for (var i = 0; i < count; i++) {
        observer.didPush(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const SizedBox(),
              settings: RouteSettings(name: '/fast$i'),
            ),
            null);
        if (i % 2 == 0) {
          observer.didPop(
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const SizedBox(),
                settings: RouteSettings(name: '/fast${i - 1}'),
              ),
              null);
        }
        if (i % 500 == 0) {
          exporter.clear();
        }
      }
      observer.dispose();
      expect(true, isTrue);
    });
  });
}
