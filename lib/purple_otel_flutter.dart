import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:purple_otel_api/purple_otel_api.dart';
import 'package:purple_otel_sdk/purple_otel_sdk.dart';

final class OtelNavigatorObserver extends NavigatorObserver {
  final Tracer _tracer;
  final Map<Route, Span> _activeSpans = {};

  OtelNavigatorObserver({required Tracer tracer}) : _tracer = tracer;

  @override
  void didPush(Route route, Route? previousRoute) {
    final span = _tracer.startSpan(
      'navigate_to ${route.settings.name ?? '/'}',
      kind: SpanKind.internal,
    );
    span.setAttribute(
        'screen.name', AttributeValue.string(route.settings.name ?? '/'));
    _activeSpans[route] = span;
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    final span = _activeSpans.remove(route);
    if (span != null) {
      span.setStatus(SpanStatus.ok);
      span.end();
    }
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    if (oldRoute != null) {
      final span = _activeSpans.remove(oldRoute);
      span?.end();
    }
    if (newRoute != null) {
      final span = _tracer.startSpan(
        'navigate_to ${newRoute.settings.name ?? '/'}',
        kind: SpanKind.internal,
      );
      span.setAttribute(
          'screen.name', AttributeValue.string(newRoute.settings.name ?? '/'));
      _activeSpans[newRoute] = span;
    }
  }
}

final class OtelWidgetsBindingObserver with WidgetsBindingObserver {
  final Tracer _tracer;

  OtelWidgetsBindingObserver({required Tracer tracer}) : _tracer = tracer;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final span = _tracer.startSpan(
      'lifecycle_${state.name}',
      kind: SpanKind.internal,
    );
    span.setAttribute('app.lifecycle', AttributeValue.string(state.name));
    span.setStatus(SpanStatus.ok);
    span.end();
  }
}

final class FlutterOtelInitializer {
  static Future<void> initialize({
    required TracerProvider tracerProvider,
  }) async {
    final tracer = tracerProvider.get('flutter');

    FlutterError.onError = (FlutterErrorDetails details) {
      final span = tracer.startSpan('flutter-error', kind: SpanKind.internal);
      span.recordException(
        details.exception,
        stackTrace: details.stack,
      );
      span.setAttribute(
          'error.library', AttributeValue.string(details.library ?? ''));
      span.setAttribute('error.context',
          AttributeValue.string(details.context?.toString() ?? ''));
      span.setStatus(SpanStatus.error(details.exceptionAsString()));
      span.end();

      FlutterError.presentError(details);
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      final span = tracer.startSpan('platform-error', kind: SpanKind.internal);
      span.recordException(error, stackTrace: stack);
      span.setStatus(SpanStatus.error(error.toString()));
      span.end();
      return true;
    };
  }
}

extension OtelFlutterExtension on WidgetsBinding {
  void initializeOtel({
    required TracerProvider tracerProvider,
  }) {
    FlutterOtelInitializer.initialize(tracerProvider: tracerProvider);
  }
}
