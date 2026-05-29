import 'dart:async';

import 'package:flutter/foundation.dart';
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
  group('OtelNavigatorObserver', () {
    testWidgets('didPush creates span with screen name attribute',
        (tester) async {
      final exporter = InMemorySpanExporter();
      final observer =
          OtelNavigatorObserver(tracer: _provider(exporter).get('nav'));

      final route = MaterialPageRoute<void>(
        builder: (_) => const SizedBox(),
        settings: const RouteSettings(name: '/settings'),
      );
      observer.didPush(route, null);
      observer.didPop(route, null);

      final span = exporter.spans.first as SDKSpan;
      expect(span.name, 'navigate_to /settings');
      expect(span.attributes['screen.name'],
          AttributeValue.string('/settings'));
      expect(span.kind, SpanKind.internal);
      expect(span.status.code, StatusCode.ok);
    });

    testWidgets('didPush with null route name uses /', (tester) async {
      final exporter = InMemorySpanExporter();
      final observer =
          OtelNavigatorObserver(tracer: _provider(exporter).get('nav'));

      final route = MaterialPageRoute<void>(
        builder: (_) => const SizedBox(),
        settings: const RouteSettings(name: null),
      );
      observer.didPush(route, null);
      observer.didPop(route, null);

      final span = exporter.spans.first as SDKSpan;
      expect(span.name, 'navigate_to /');
      expect(span.attributes['screen.name'], AttributeValue.string('/'));
    });

    testWidgets('multiple pushes and pops in order', (tester) async {
      final exporter = InMemorySpanExporter();
      final observer =
          OtelNavigatorObserver(tracer: _provider(exporter).get('nav'));

      final r1 = MaterialPageRoute<void>(
        builder: (_) => const SizedBox(),
        settings: const RouteSettings(name: '/a'),
      );
      final r2 = MaterialPageRoute<void>(
        builder: (_) => const SizedBox(),
        settings: const RouteSettings(name: '/b'),
      );
      final r3 = MaterialPageRoute<void>(
        builder: (_) => const SizedBox(),
        settings: const RouteSettings(name: '/c'),
      );

      observer.didPush(r1, null);
      observer.didPush(r2, r1);
      observer.didPush(r3, r2);
      observer.didPop(r3, r2);
      observer.didPop(r2, r1);
      observer.didPop(r1, null);

      expect(exporter.spans.length, 3);
      expect((exporter.spans[0] as SDKSpan).name, 'navigate_to /c');
      expect((exporter.spans[1] as SDKSpan).name, 'navigate_to /b');
      expect((exporter.spans[2] as SDKSpan).name, 'navigate_to /a');

      for (final s in exporter.spans) {
        expect((s as SDKSpan).status.code, StatusCode.ok);
      }
    });

    testWidgets('didPop does nothing if route was never pushed',
        (tester) async {
      final exporter = InMemorySpanExporter();
      final observer =
          OtelNavigatorObserver(tracer: _provider(exporter).get('nav'));

      final route = MaterialPageRoute<void>(
        builder: (_) => const SizedBox(),
        settings: const RouteSettings(name: '/ghost'),
      );
      observer.didPop(route, null);

      expect(exporter.spans.isEmpty, isTrue);
    });

    testWidgets('didReplace transfers span to new route', (tester) async {
      final exporter = InMemorySpanExporter();
      final observer =
          OtelNavigatorObserver(tracer: _provider(exporter).get('nav'));

      final oldRoute = MaterialPageRoute<void>(
        builder: (_) => const SizedBox(),
        settings: const RouteSettings(name: '/old'),
      );
      final newRoute = MaterialPageRoute<void>(
        builder: (_) => const SizedBox(),
        settings: const RouteSettings(name: '/new'),
      );

      observer.didPush(oldRoute, null);
      observer.didReplace(newRoute: newRoute, oldRoute: oldRoute);
      observer.didPop(newRoute, null);

      expect(exporter.spans.length, 2);
      expect((exporter.spans[0] as SDKSpan).name, 'navigate_to /old');
      expect((exporter.spans[1] as SDKSpan).name, 'navigate_to /new');
    });

    testWidgets('didReplace with null newRoute does nothing', (tester) async {
      final exporter = InMemorySpanExporter();
      final observer =
          OtelNavigatorObserver(tracer: _provider(exporter).get('nav'));

      final oldRoute = MaterialPageRoute<void>(
        builder: (_) => const SizedBox(),
        settings: const RouteSettings(name: '/old'),
      );
      observer.didPush(oldRoute, null);
      observer.didReplace(newRoute: null, oldRoute: oldRoute);

      expect(exporter.spans.length, 1);
    });

    testWidgets('didReplace with null oldRoute adds new route', (tester) async {
      final exporter = InMemorySpanExporter();
      final observer =
          OtelNavigatorObserver(tracer: _provider(exporter).get('nav'));

      final newRoute = MaterialPageRoute<void>(
        builder: (_) => const SizedBox(),
        settings: const RouteSettings(name: '/new'),
      );
      observer.didReplace(newRoute: newRoute, oldRoute: null);
      observer.didPop(newRoute, null);

      expect(exporter.spans.length, 1);
      expect((exporter.spans.first as SDKSpan).name, 'navigate_to /new');
    });
  });

  group('OtelWidgetsBindingObserver', () {
    testWidgets('all four lifecycle states create spans', (tester) async {
      final exporter = InMemorySpanExporter();
      final observer = OtelWidgetsBindingObserver(
          tracer: _provider(exporter).get('lifecycle'));

      observer
          .didChangeAppLifecycleState(AppLifecycleState.resumed);
      observer
          .didChangeAppLifecycleState(AppLifecycleState.inactive);
      observer
          .didChangeAppLifecycleState(AppLifecycleState.paused);
      observer
          .didChangeAppLifecycleState(AppLifecycleState.detached);

      expect(exporter.spans.length, 4);
      expect((exporter.spans[0] as SDKSpan).name, 'lifecycle_resumed');
      expect((exporter.spans[1] as SDKSpan).name, 'lifecycle_inactive');
      expect((exporter.spans[2] as SDKSpan).name, 'lifecycle_paused');
      expect((exporter.spans[3] as SDKSpan).name, 'lifecycle_detached');
    });

    testWidgets('lifecycle span includes app.lifecycle attribute',
        (tester) async {
      final exporter = InMemorySpanExporter();
      final observer = OtelWidgetsBindingObserver(
          tracer: _provider(exporter).get('lifecycle'));

      observer
          .didChangeAppLifecycleState(AppLifecycleState.inactive);

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
        resource: Resource.empty,
        processors: [],
      );
      await FlutterOtelInitializer.initialize(tracerProvider: provider);
      expect(FlutterError.onError, isNotNull);
    });

    testWidgets('error handler creates span with error attributes',
        (tester) async {
      final exporter = InMemorySpanExporter();
      final provider = _provider(exporter);
      await FlutterOtelInitializer.initialize(tracerProvider: provider);

      FlutterError.onError!.call(FlutterErrorDetails(
        exception: StateError('invalid state'),
        library: 'widgets_library',
        context: ErrorDescription('while building MyWidget'),
      ));

      expect(exporter.spans.length, 1);
      final span = exporter.spans.first as SDKSpan;
      expect(span.name, 'flutter-error');
      expect(span.kind, SpanKind.internal);
      expect(span.status.code, StatusCode.error);
      expect(span.attributes['error.library'],
          AttributeValue.string('widgets_library'));
      expect(span.attributes['error.context'],
          isA<AttributeValue>());
      expect(span.events.isNotEmpty, isTrue);
    });

    testWidgets('presentError is still called after our handler',
        (tester) async {
      final exporter = InMemorySpanExporter();
      final provider = _provider(exporter);
      FlutterErrorDetails? captured;

      await FlutterOtelInitializer.initialize(tracerProvider: provider);

      FlutterError.presentError = (details) => captured = details;
      FlutterError.onError!.call(FlutterErrorDetails(
        exception: Exception('test'),
        library: 'test_lib',
      ));

      expect(captured, isNotNull);
      expect(exporter.spans.isNotEmpty, isTrue);
    });

    testWidgets('platform error handler returns true', (tester) async {
      final exporter = InMemorySpanExporter();
      final provider = _provider(exporter);
      await FlutterOtelInitializer.initialize(tracerProvider: provider);

      final result = PlatformDispatcher.instance
          .onError!(Exception('platform crash'), StackTrace.current);

      expect(result, isTrue);
    });

    testWidgets('platform error handler creates error span', (tester) async {
      final exporter = InMemorySpanExporter();
      final provider = _provider(exporter);
      await FlutterOtelInitializer.initialize(tracerProvider: provider);

      PlatformDispatcher.instance
          .onError!(FormatException('bad json'), StackTrace.current);

      expect(exporter.spans.length, 1);
      final span = exporter.spans.first as SDKSpan;
      expect(span.name, 'platform-error');
      expect(span.kind, SpanKind.internal);
      expect(span.status.code, StatusCode.error);
      expect(span.events.isNotEmpty, isTrue);
    });
  });

  group('OtelFlutterExtension', () {
    testWidgets('initializeOtel calls FlutterOtelInitializer', (tester) async {
      final exporter = InMemorySpanExporter();
      final provider = _provider(exporter);
      final binding = TestWidgetsFlutterBinding.ensureInitialized();

      binding.initializeOtel(tracerProvider: provider);

      expect(FlutterError.onError, isNotNull);

      FlutterError.onError!.call(
          FlutterErrorDetails(exception: Exception('test'), library: 'test'));
      expect(exporter.spans.length, 1);
    });
  });
}
