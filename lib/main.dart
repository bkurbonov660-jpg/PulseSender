import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/convert_screen.dart';
import 'screens/player_screen.dart';
import 'screens/files_screen.dart';
import 'screens/profile_screen.dart';
import 'services/converter_service.dart';
import 'services/history_service.dart';
import 'services/queue_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VideoToMp3',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121418),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981),
          secondary: Color(0xFF059669),
          surface: Color(0xFF1B1F26),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121418),
          foregroundColor: Color(0xFFF3F4F6),
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1B1F26),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFF2A303C), width: 1),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF161920),
          selectedItemColor: Color(0xFF10B981),
          unselectedItemColor: Color(0xFF6B7280),
          type: BottomNavigationBarType.fixed,
        ),
      ),
      home: const Shell(),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _tabIndex = 0;
  static const _pages = [
    ConvertScreen(),
    PlayerScreen(),
    FilesScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupNativeCallbacks();
    _checkPendingIntentAction();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      historyChanged.value++;
      _checkPendingIntentAction();
    }
  }

  void _setupNativeCallbacks() {
    ConverterService.mediaChannel.setMethodCallHandler((call) async {
      if (call.method == 'onShareUrlReceived') {
        final map = Map<String, dynamic>.from(call.arguments as Map);
        final url = (map['url'] ?? '') as String;
        final mode = (map['mode'] ?? 'mp3') as String;
        if (url.isNotEmpty) {
          QueueService.instance.enqueueUrls([url], mode: mode);
        }
      } else if (call.method == 'onOpenPlayerFile') {
        final path = call.arguments as String?;
        if (path != null && path.isNotEmpty) {
          historyChanged.value++;
          activePlayRequestPath.value = path;
          if (mounted) setState(() => _tabIndex = 1);
        }
      } else if (call.method == 'onBackgroundDownloadFinished') {
        historyChanged.value++;
      }
      return null;
    });
  }

  Future<void> _checkPendingIntentAction() async {
    try {
      final res = await ConverterService.mediaChannel.invokeMapMethod<String, dynamic>('consumeInitialAction');
      if (res == null) return;
      final type = res['type'] as String?;
      if (type == 'open_player') {
        final filePath = res['filePath'] as String?;
        historyChanged.value++;
        if (filePath != null && filePath.isNotEmpty) {
          activePlayRequestPath.value = filePath;
          if (mounted) setState(() => _tabIndex = 1);
        }
      } else if (type == 'enqueue_url') {
        final url = res['url'] as String?;
        final mode = (res['mode'] ?? 'mp3') as String;
        if (url != null && url.isNotEmpty) {
          QueueService.instance.enqueueUrls([url], mode: mode);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tabIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (v) => setState(() => _tabIndex = v),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.bolt_rounded), label: 'Загрузка и MP3'),
          BottomNavigationBarItem(icon: Icon(Icons.play_circle_fill_rounded), label: 'Плеер и Обрезка'),
          BottomNavigationBarItem(icon: Icon(Icons.folder_rounded), label: 'Файлы'),
          BottomNavigationBarItem(icon: Icon(Icons.tune_rounded), label: 'Настройки'),
        ],
      ),
    );
  }
}
