import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purple_otel_api/purple_otel_api.dart';
import 'package:purple_otel_flutter/purple_otel_flutter.dart';
import 'package:purple_otel_sdk/purple_otel_sdk.dart';

void main() {
  group('OtelNavigatorObserver', () {
    testWidgets('didPush + didPop creates and ends span', (tester) async {
      final exporter = InMemorySpanExporter();
      final provider = SDKTracerProvider(
        resource: Resource.empty,
        processors: [SimpleSpanProcessor(exporter)],
      );
      final observer = OtelNavigatorObserver(tracer: provider.get('nav'));

      final route = MaterialPageRoute<void>(
        builder: (_) => const SizedBox(),
        settings: const RouteSettings(name: '/home'),
      );

      observer.didPush(route, null);
      observer.didPop(route, null);

      expect(exporter.spans.length, 1);
      final span = exporter.spans.first as SDKSpan;
      expect(span.name, 'navigate_to /home');
      expect(span.status.code, StatusCode.ok);
    });

    testWidgets('didReplace swaps active span and exports both',
        (tester) async {
      final exporter = InMemorySpanExporter();
      final provider = SDKTracerProvider(
        resource: Resource.empty,
        processors: [SimpleSpanProcessor(exporter)],
      );
      final observer = OtelNavigatorObserver(tracer: provider.get('nav'));

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
      expect((exporter.spans.last as SDKSpan).name, 'navigate_to /new');
    });
  });

  group('OtelWidgetsBindingObserver', () {
    testWidgets('creates span for each lifecycle state', (tester) async {
      final exporter = InMemorySpanExporter();
      final provider = SDKTracerProvider(
        resource: Resource.empty,
        processors: [SimpleSpanProcessor(exporter)],
      );
      final observer =
          OtelWidgetsBindingObserver(tracer: provider.get('lifecycle'));

      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      observer.didChangeAppLifecycleState(AppLifecycleState.inactive);

      expect(exporter.spans.length, 3);
      expect((exporter.spans[0] as SDKSpan).name, 'lifecycle_paused');
      expect((exporter.spans[1] as SDKSpan).name, 'lifecycle_resumed');
      expect((exporter.spans[2] as SDKSpan).name, 'lifecycle_inactive');
      expect((exporter.spans[0] as SDKSpan).status.code, StatusCode.ok);
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

    testWidgets('error handler creates flutter-error span', (tester) async {
      final exporter = InMemorySpanExporter();
      final provider = SDKTracerProvider(
        resource: Resource.empty,
        processors: [SimpleSpanProcessor(exporter)],
      );
      await FlutterOtelInitializer.initialize(tracerProvider: provider);

      FlutterError.onError!.call(FlutterErrorDetails(
        exception: Exception('test error'),
        library: 'test_library',
      ));

      expect(exporter.spans.length, 1);
      final span = exporter.spans.first as SDKSpan;
      expect(span.name, 'flutter-error');
      expect(span.status.code, StatusCode.error);
      expect(span.attributes['error.library'],
          AttributeValue.string('test_library'));
    });
  });
}
