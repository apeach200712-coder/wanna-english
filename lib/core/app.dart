import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/class_selection_service.dart';
import '../theme/app_theme.dart';
import '../pages/home/home_page.dart';
import 'routes.dart';

class WannaEnglishApp extends StatelessWidget {
  const WannaEnglishApp({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[STARTUP_DIAG] app: build MaterialApp');
    return ChangeNotifierProvider(
      create: (_) => ClassSelectionService(),
      child: MaterialApp(
        title: 'Wanna English',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const HomePage(),
        routes: AppRoutes.childRoutes,
      ),
    );
  }
}
