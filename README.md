# wanna_english

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Faster iteration while developing

- **Debug `flutter run` is inherently slow**: JIT compilation, extra assertions,
  and dev tooling make cold starts and rebuilds much slower than release.
  Use **`flutter run --release`** when you need to judge real startup or
  scrolling performance (not for debugging breakpoints).
- **Profile CPU/GPU and jank** with **`flutter run --profile`** and DevTools;
  profile builds sit between debug and release.
- **Avoid `flutter clean` on every run**; it forces a full rebuild. Prefer
  hot reload/restart unless dependencies or generated files are broken.
- **Rendering engine (iOS/macOS)**: Flutter may use Impeller depending on
  platform and version. If you suspect a GPU/back-end issue, check the current
  flags in `flutter run --help` (e.g. Impeller enable/disable) and the
  [Flutter Impeller docs](https://docs.flutter.dev/perf/impeller).
