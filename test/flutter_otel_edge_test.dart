import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purple_otel_api/purple_otel_api.dart';
import 'package:purple_otel_flutter/purple_otel_flutter.dart';
import 'package:purple_otel_sdk/purple_otel_sdk.dart';

SDKTracerProvider _provider(InMemorySpanExporter exporter) {
  return SDKTracerProvider(
    resource: Resource.empty,
    processors: [SimpleSpanProcessor(exporter)],
  );
}

void main() {
  setUp(() => FlutterOtelInitializer.reset());

  group('OtelNavigatorObserver edge cases', () {
    testWidgets('double push on same route ends old span', (tester) async {
      final exporter = InMemorySpanExporter();
      final observer =
          OtelNavigatorObserver(tracer: _provider(exporter).get('nav'));

      final r = MaterialPageRoute<void>(
          builder: (_) => const SizedBox(),
          settings: const RouteSettings(name: '/home'));
      observer.didPush(r, null);
      observer.didPush(r, null);
      observer.didPop(r, null);

      expect(exporter.spans.length, 2);
    });

    testWidgets('dispose ends all active spans', (tester) async {
      final exporter = InMemorySpanExporter();
      final observer =
          OtelNavigatorObserver(tracer: _provider(exporter).get('nav'));

      observer.didPush(
        MaterialPageRoute<void>(
            builder: (_) => const SizedBox(),
            settings: const RouteSettings(name: '/a')),
        null,
      );
      observer.didPush(
        MaterialPageRoute<void>(
            builder: (_) => const SizedBox(),
            settings: const RouteSettings(name: '/b')),
        null,
      );
      observer.dispose();

      expect(exporter.spans.length, 2);
    });

    testWidgets('does not throw when tracer is disposed', (tester) async {
      final exporter = InMemorySpanExporter();
      final provider = _provider(exporter);
      final tracer = provider.get('nav');
      provider.shutdown();

      final observer = OtelNavigatorObserver(tracer: tracer);
      final r = MaterialPageRoute<void>(
          builder: (_) => const SizedBox(),
          settings: const RouteSettings(name: '/home'));

      observer.didPush(r, null);
      observer.didPop(r, null);
      observer.didReplace(newRoute: r, oldRoute: r);
      observer.dispose();
    });

    testWidgets('didReplace both null does nothing', (tester) async {
      final exporter = InMemorySpanExporter();
      final observer =
          OtelNavigatorObserver(tracer: _provider(exporter).get('nav'));
      observer.didReplace(newRoute: null, oldRoute: null);
      expect(exporter.spans.isEmpty, isTrue);
    });
  });

  group('OtelWidgetsBindingObserver edge cases', () {
    testWidgets('does not throw when tracer is disposed', (tester) async {
      final provider = SDKTracerProvider(
          resource: Resource.empty, processors: []);
      final tracer = provider.get('lifecycle');
      provider.shutdown();

      final obs = OtelWidgetsBindingObserver(tracer: tracer);
      obs.didChangeAppLifecycleState(AppLifecycleState.paused);
    });
  });

  group('FlutterOtelInitializer edge cases', () {
    testWidgets('double initialization is a no-op', (tester) async {
      final exporter1 = InMemorySpanExporter();
      final provider1 = _provider(exporter1);
      await FlutterOtelInitializer.initialize(tracerProvider: provider1);

      final exporter2 = InMemorySpanExporter();
      final provider2 = _provider(exporter2);
      await FlutterOtelInitializer.initialize(tracerProvider: provider2);
    });
  });

  group('FlutterOtelInitializer — plain dart tests', () {
    // These use plain `test()` because testWidgets intercepts FlutterError.onError
    test('error messages truncated at 256 chars', () async {
      FlutterOtelInitializer.reset();
      final exporter = InMemorySpanExporter();
      final provider = _provider(exporter);
      await FlutterOtelInitializer.initialize(tracerProvider: provider);

      FlutterError.onError!.call(FlutterErrorDetails(
        exception: Exception('A' * 500),
        library: 'test',
      ));

      final span = exporter.spans.first as SDKSpan;
      final desc = span.status.description!;
      expect(desc.length, lessThanOrEqualTo(256));
      expect(desc.endsWith('...'), isTrue);
    });

    test('handles disposed tracer without throwing', () async {
      FlutterOtelInitializer.reset();
      final exporter = InMemorySpanExporter();
      final provider = _provider(exporter);
      await FlutterOtelInitializer.initialize(tracerProvider: provider);
      provider.shutdown();

      FlutterError.onError!
          .call(FlutterErrorDetails(exception: Exception('x'), library: 'x'));
    });

    test('previous FlutterError.onError is called after ours', () async {
      FlutterOtelInitializer.reset();
      final exporter = InMemorySpanExporter();
      final provider = _provider(exporter);
      var called = false;
      FlutterError.onError = (details) => called = true;

      await FlutterOtelInitializer.initialize(tracerProvider: provider);
      FlutterError.onError!.call(
          FlutterErrorDetails(exception: Exception('test'), library: 'lib'));

      expect(exporter.spans.length, 1);
      expect(called, isTrue);
    });
  });
}
