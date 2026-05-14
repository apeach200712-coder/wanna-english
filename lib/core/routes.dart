import 'package:flutter/material.dart';

import '../pages/home/home_page.dart';
import '../pages/todo/todo_page.dart';
import '../pages/students/students_page.dart';
import '../pages/reports/report_page.dart';
import '../pages/reports/grade_calculator_page.dart';
import '../pages/materials/materials_page.dart' deferred as materials_lib;
import '../pages/calendar/calendar_page.dart';
import '../pages/announcements/announcement_page.dart';
import '../pages/attendance/attendance_page.dart';
import '../pages/homework/homework_page.dart';
import '../pages/exams/grade_input_page.dart';
import '../pages/settings/settings_page.dart';
import '../pages/classes/class_page.dart';
import '../theme/app_colors.dart';

/// First open of the Materials tab loads the heavy memo/PDF module in the background.
class _DeferredMaterialsPage extends StatefulWidget {
  const _DeferredMaterialsPage();

  @override
  State<_DeferredMaterialsPage> createState() => _DeferredMaterialsPageState();
}

class _DeferredMaterialsPageState extends State<_DeferredMaterialsPage> {
  late final Future<void> _load = materials_lib.loadLibrary();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: const Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: AppColors.blue,
                ),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '자료 화면을 불러오지 못했습니다.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.subText,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }
        return materials_lib.MaterialsPage();
      },
    );
  }
}

class AppRoutes {
  /// Main tabs & shortcuts: no slide animation (instant replace of screen).
  static PageRoute<void> instantPageRoute(String name, WidgetBuilder builder) {
    return PageRouteBuilder<void>(
      settings: RouteSettings(name: name),
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          child,
    );
  }

  static void pushNamedInstant(BuildContext context, String routeName) {
    final builder = routes[routeName];
    if (builder == null) return;
    Navigator.of(context).push(instantPageRoute(routeName, builder));
  }

  static const String home = '/home';
  static const String todo = '/todo';
  static const String students = '/students';
  static const String report = '/report';
  static const String gradeCalculator = '/grade-calculator';
  static const String gradeInput = '/grade-input';
  static const String materials = '/materials';
  static const String calendar = '/calendar';
  static const String announcements = '/announcements';
  static const String attendance = '/attendance';
  static const String homework = '/homework';
  static const String settings = '/settings';
  static const String classManagement = '/class-management';

  static Map<String, WidgetBuilder> get routes {
    return {
      home: (context) => const HomePage(),
      todo: (context) => const TodoPage(),
      students: (context) => const StudentsPage(),
      report: (context) => const ReportPage(),
      gradeCalculator: (context) => const GradeCalculatorPage(),
      gradeInput: (context) => const GradeInputPage(),
      materials: (context) => const _DeferredMaterialsPage(),
      calendar: (context) => const CalendarPage(),
      announcements: (context) => const AnnouncementPage(),
      attendance: (context) => const AttendancePage(),
      homework: (context) => const HomeworkPage(),
      settings: (context) => const SettingsPage(),
      classManagement: (context) => const ClassPage(),
    };
  }

  /// [MaterialApp.home] already provides `/`; omit [home] from [MaterialApp.routes].
  static Map<String, WidgetBuilder> get childRoutes {
    return Map<String, WidgetBuilder>.fromEntries(
      routes.entries.where((e) => e.key != home),
    );
  }
}
