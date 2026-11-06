## 0.1.6

- Includes 0.1.4 and 0.1.5 below, which were tagged but never published to pub.dev.
- Releases are now published from GitHub Actions on version tags.

## 0.1.5

- `OtelNavigatorObserver` gains an optional `routeNameExtractor`, so routes in nested navigators can be named unambiguously. The default behaviour is unchanged.
- New `FlutterResourceDetector`: fills `telemetry.sdk.*` and `os.type`, `os.name`, `os.version` without extra plugins.

## 0.1.4

- Version bump only, no code changes.

## 0.1.3

- No release notes were recorded for this version.

## 0.1.2

- No release notes were recorded for this version.

## 0.1.0

- Initial release
- OtelNavigatorObserver for automatic route tracking
- OtelWidgetsBindingObserver for lifecycle events
- FlutterOtelInitializer for one-shot error capture setup
- Captures FlutterError.onError and PlatformDispatcher.onError as spans
