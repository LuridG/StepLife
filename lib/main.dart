import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/theme/app_theme.dart';
import 'features/profile/providers/profile_provider.dart';
import 'features/step_tracker/providers/step_provider.dart';
import 'features/chore_tracker/providers/chore_provider.dart';
import 'features/store_journal/providers/store_provider.dart';
import 'features/step_tracker/presentation/step_tracker_screen.dart';
import 'features/chore_tracker/presentation/chore_tracker_screen.dart';
import 'features/store_journal/presentation/store_journal_screen.dart';
import 'features/about/presentation/about_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 适配 Windows/Linux/macOS 桌面端 SQLite 运行环境
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
        ChangeNotifierProvider(create: (_) => StepProvider()),
        ChangeNotifierProvider(create: (_) => ChoreProvider()),
        ChangeNotifierProvider(create: (_) => StoreProvider()),
      ],
      child: const StepLifeApp(),
    ),
  );
}

class StepLifeApp extends StatelessWidget {
  const StepLifeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StepLife - 步履生活',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainHomeScreen(),
    );
  }
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          StepTrackerScreen(),
          ChoreTrackerScreen(),
          StoreJournalScreen(),
          AboutScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
          _pageController.jumpToPage(index);
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.directions_walk),
            label: '步量路线',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.check_circle_outline),
            label: '家务习惯',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.storefront_outlined),
            label: '生活记录',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.info_outline),
            label: '关于程序',
          ),
        ],
      ),
    );
  }
}
