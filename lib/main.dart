import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/app.dart';
import 'core/backend_bootstrap.dart' deferred as backend_bootstrap;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[STARTUP_DIAG] main: binding initialized');

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint(details.exceptionAsString());
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught async error: $error\n$stack');
    return true;
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('ErrorWidget: ${details.exceptionAsString()}');
    return const _StartupErrorScreen();
  };

  runApp(const WannaEnglishApp());
  debugPrint('[STARTUP_DIAG] main: runApp dispatched');

  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPrint('[STARTUP_DIAG] main: first frame rendered');
  });

  // Heavy plugin / Supabase init loads after the first frame so the shell can
  // paint quickly; deferred import keeps that work off the initial isolate load.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPrint('[STARTUP_DIAG] main: deferred backend bootstrap start');
    unawaited(
      backend_bootstrap.loadLibrary().then(
        (_) => backend_bootstrap.BackendBootstrap.initialize(),
      ),
    );
  });
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0F1115),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            kDebugMode
                ? '화면을 불러오지 못했습니다.\n(디버그 정보는 콘솔을 확인하세요)'
                : '화면을 불러오지 못했습니다.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF8B93A1),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
