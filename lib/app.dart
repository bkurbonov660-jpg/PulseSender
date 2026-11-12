import 'package:flutter/material.dart';
import 'screens/agent_screen.dart';
import 'screens/assistant_hub_screen.dart';
import 'screens/history_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/quick_commands_screen.dart';
import 'screens/settings_screen.dart';

class PulseAgentApp extends StatefulWidget {
  const PulseAgentApp({super.key});

  @override
  State<PulseAgentApp> createState() => _PulseAgentAppState();
}

class _PulseAgentAppState extends State<PulseAgentApp> {
  int _currentIndex = 0;

  void _switchToAgentTab() {
    setState(() {
      _currentIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const AgentScreen(),
      AssistantHubScreen(onSwitchToAgentTab: _switchToAgentTab),
      QuickCommandsScreen(onSwitchToAgentTab: _switchToAgentTab),
      HistoryScreen(onSwitchToAgentTab: _switchToAgentTab),
      const SettingsScreen(),
      const ProfileScreen(),
    ];

    return MaterialApp(
      title: 'PulseAgent v2.0',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3F51B5),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1A1C29),
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: pages,
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFE8EAF6),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.smart_toy_outlined),
              selectedIcon: Icon(Icons.smart_toy, color: Color(0xFF3F51B5)),
              label: 'Агент',
            ),
            NavigationDestination(
              icon: Icon(Icons.support_agent_outlined),
              selectedIcon: Icon(Icons.support_agent, color: Color(0xFF3F51B5)),
              label: 'Секретарь',
            ),
            NavigationDestination(
              icon: Icon(Icons.bolt_outlined),
              selectedIcon: Icon(Icons.bolt, color: Color(0xFF3F51B5)),
              label: 'Быстрые',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history, color: Color(0xFF3F51B5)),
              label: 'История',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings, color: Color(0xFF3F51B5)),
              label: 'Настройки',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person, color: Color(0xFF3F51B5)),
              label: 'Профиль',
            ),
          ],
        ),
      ),
    );
  }
}
