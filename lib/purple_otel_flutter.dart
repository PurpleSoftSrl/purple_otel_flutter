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
    _safe(() {
      final oldSpan = _activeSpans.remove(route);
      oldSpan?.end();

      final name = route.settings.name ?? '/';
      final span = _tracer.startSpan(
        'navigate_to $name',
        kind: SpanKind.internal,
      );
      span.setAttribute('screen.name', AttributeValue.string(name));
      _activeSpans[route] = span;
    });
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    _safe(() {
      final span = _activeSpans.remove(route);
      if (span != null) {
        span.setStatus(SpanStatus.ok);
        span.end();
      }
    });
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    _safe(() {
      if (oldRoute != null) {
        final span = _activeSpans.remove(oldRoute);
        span?.end();
      }
      if (newRoute != null) {
        final name = newRoute.settings.name ?? '/';
        final span = _tracer.startSpan(
          'navigate_to $name',
          kind: SpanKind.internal,
        );
        span.setAttribute('screen.name', AttributeValue.string(name));
        _activeSpans[newRoute] = span;
      }
    });
  }

  void _safe(void Function() fn) {
    try {
      fn();
    } catch (_) {
      // Swallow — never break Flutter navigation because of tracing
    }
  }

  void dispose() {
    for (final span in _activeSpans.values) {
      try {
        span.end();
      } catch (_) {}
    }
    _activeSpans.clear();
  }
}

final class OtelWidgetsBindingObserver with WidgetsBindingObserver {
  final Tracer _tracer;

  OtelWidgetsBindingObserver({required Tracer tracer}) : _tracer = tracer;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    try {
      final span = _tracer.startSpan(
        'lifecycle_${state.name}',
        kind: SpanKind.internal,
      );
      span.setAttribute(
          'app.lifecycle', AttributeValue.string(state.name));
      span.setStatus(SpanStatus.ok);
      span.end();
    } catch (_) {}
  }
}

final class FlutterOtelInitializer {
  static bool _initialized = false;

  FlutterOtelInitializer._();

  @visibleForTesting
  static void reset() {
    _initialized = false;
  }

  static Future<void> initialize({
    required TracerProvider tracerProvider,
  }) async {
    if (_initialized) return;
    _initialized = true;

    final tracer = tracerProvider.get('flutter');
    final previousFlutterErrorHandler = FlutterError.onError;
    final previousPlatformErrorHandler =
        PlatformDispatcher.instance.onError;

    FlutterError.onError = (FlutterErrorDetails details) {
      _safe(() {
        final span =
            tracer.startSpan('flutter-error', kind: SpanKind.internal);
        span.recordException(
          details.exception,
          stackTrace: details.stack,
        );
        span.setAttribute('error.library',
            AttributeValue.string(_limit(details.library ?? '', 128)));
        span.setAttribute('error.context',
            AttributeValue.string(_limit(details.context?.toString() ?? '', 256)));
        span.setStatus(
            SpanStatus.error(_limit(details.exceptionAsString(), 256)));
        span.end();
      });

      try {
        previousFlutterErrorHandler?.call(details);
      } catch (_) {}
    };

    PlatformDispatcher.instance.onError =
        (Object error, StackTrace stack) {
      _safe(() {
        final span = tracer.startSpan(
            'platform-error', kind: SpanKind.internal);
        span.recordException(error, stackTrace: stack);
        span.setStatus(
            SpanStatus.error(_limit(error.toString(), 256)));
        span.end();
      });

      try {
        previousPlatformErrorHandler?.call(error, stack);
      } catch (_) {}

      return true;
    };
  }

  static void _safe(void Function() fn) {
    try {
      fn();
    } catch (_) {}
  }

  static String _limit(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength - 3)}...';
  }
}

extension OtelFlutterExtension on WidgetsBinding {
  void initializeOtel({
    required TracerProvider tracerProvider,
  }) {
    FlutterOtelInitializer.initialize(tracerProvider: tracerProvider);
  }
}
