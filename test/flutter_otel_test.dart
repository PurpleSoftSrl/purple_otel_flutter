import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  group('OtelNavigatorObserver', () {
    testWidgets('didPush creates span with screen name', (tester) async {
      final exporter = InMemorySpanExporter();
      final observer =
          OtelNavigatorObserver(tracer: _provider(exporter).get('nav'));

      final r = MaterialPageRoute<void>(
        builder: (_) => const SizedBox(),
        settings: const RouteSettings(name: '/settings'),
      );
      observer.didPush(r, null);
      observer.didPop(r, null);

      final span = exporter.spans.first as SDKSpan;
      expect(span.name, 'navigate_to /settings');
      expect(span.attributes['screen.name'],
          AttributeValue.string('/settings'));
    });

    testWidgets('null route name uses /', (tester) async {
      final exporter = InMemorySpanExporter();
      final observer =
          OtelNavigatorObserver(tracer: _provider(exporter).get('nav'));

      final r = MaterialPageRoute<void>(
        builder: (_) => const SizedBox(),
        settings: const RouteSettings(name: null),
      );
      observer.didPush(r, null);
      observer.didPop(r, null);

      final span = exporter.spans.first as SDKSpan;
      expect(span.name, 'navigate_to /');
    });

    testWidgets('multi push/pop exports in LIFO order', (tester) async {
      final exporter = InMemorySpanExporter();
      final observer =
          OtelNavigatorObserver(tracer: _provider(exporter).get('nav'));

      final a = MaterialPageRoute<void>(
          builder: (_) => const SizedBox(), settings: const RouteSettings(name: '/a'));
      final b = MaterialPageRoute<void>(
          builder: (_) => const SizedBox(), settings: const RouteSettings(name: '/b'));
      final c = MaterialPageRoute<void>(
          builder: (_) => const SizedBox(), settings: const RouteSettings(name: '/c'));

      observer.didPush(a, null);
      observer.didPush(b, a);
      observer.didPush(c, b);
      observer.didPop(c, b);
      observer.didPop(b, a);
      observer.didPop(a, null);

      expect(exporter.spans.length, 3);
      expect((exporter.spans[0] as SDKSpan).name, 'navigate_to /c');
      expect((exporter.spans[1] as SDKSpan).name, 'navigate_to /b');
      expect((exporter.spans[2] as SDKSpan).name, 'navigate_to /a');
    });

    testWidgets('didPop with unknown route is no-op', (tester) async {
      final exporter = InMemorySpanExporter();
      final observer =
          OtelNavigatorObserver(tracer: _provider(exporter).get('nav'));

      observer.didPop(
        MaterialPageRoute<void>(
            builder: (_) => const SizedBox(),
            settings: const RouteSettings(name: '/gone')),
        null,
      );
      expect(exporter.spans.isEmpty, isTrue);
    });

    testWidgets('didReplace transfers span to new route', (tester) async {
      final exporter = InMemorySpanExporter();
      final observer =
          OtelNavigatorObserver(tracer: _provider(exporter).get('nav'));

      final oldR = MaterialPageRoute<void>(
          builder: (_) => const SizedBox(), settings: const RouteSettings(name: '/old'));
      final newR = MaterialPageRoute<void>(
          builder: (_) => const SizedBox(), settings: const RouteSettings(name: '/new'));

      observer.didPush(oldR, null);
      observer.didReplace(newRoute: newR, oldRoute: oldR);
      observer.didPop(newR, null);

      expect(exporter.spans.length, 2);
    });

    testWidgets('didReplace null newRoute keeps old span', (tester) async {
      final exporter = InMemorySpanExporter();
      final observer =
          OtelNavigatorObserver(tracer: _provider(exporter).get('nav'));

      final r = MaterialPageRoute<void>(
          builder: (_) => const SizedBox(), settings: const RouteSettings(name: '/old'));
      observer.didPush(r, null);
      observer.didReplace(newRoute: null, oldRoute: r);

      expect(exporter.spans.length, 1);
    });

    testWidgets('didReplace null oldRoute adds new', (tester) async {
      final exporter = InMemorySpanExporter();
      final observer =
          OtelNavigatorObserver(tracer: _provider(exporter).get('nav'));

      final r = MaterialPageRoute<void>(
          builder: (_) => const SizedBox(), settings: const RouteSettings(name: '/new'));
      observer.didReplace(newRoute: r, oldRoute: null);
      observer.didPop(r, null);

      expect(exporter.spans.length, 1);
    });
  });

  group('OtelWidgetsBindingObserver', () {
    testWidgets('all 4 lifecycle states create spans', (tester) async {
      final exporter = InMemorySpanExporter();
      final observer =
          OtelWidgetsBindingObserver(tracer: _provider(exporter).get('lifecycle'));

      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      observer.didChangeAppLifecycleState(AppLifecycleState.inactive);
      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      observer.didChangeAppLifecycleState(AppLifecycleState.detached);

      expect(exporter.spans.length, 4);
      expect((exporter.spans[0] as SDKSpan).name, 'lifecycle_resumed');
      expect((exporter.spans[3] as SDKSpan).name, 'lifecycle_detached');
    });

    testWidgets('span has app.lifecycle attribute', (tester) async {
      final exporter = InMemorySpanExporter();
      final observer =
          OtelWidgetsBindingObserver(tracer: _provider(exporter).get('lifecycle'));

      observer.didChangeAppLifecycleState(AppLifecycleState.inactive);

      final span = exporter.spans.first as SDKSpan;
      expect(span.attributes['app.lifecycle'],
          AttributeValue.string('inactive'));
      expect(span.kind, SpanKind.internal);
      expect(span.status.code, StatusCode.ok);
    });
  });

  group('FlutterOtelInitializer', () {
    testWidgets('registers FlutterError.onError handler', (tester) async {
      final provider = SDKTracerProvider(
          resource: Resource.empty, processors: []);
      await FlutterOtelInitializer.initialize(tracerProvider: provider);
      expect(FlutterError.onError, isNotNull);
    });
  });
}

