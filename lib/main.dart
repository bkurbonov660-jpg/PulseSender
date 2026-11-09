import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
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
    statusBarIconBrightness: Brightness.dark,
  ));
  try {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'v2m',
        channelName: 'Video→MP3',
        channelDescription: 'Конвертация видео',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  } catch (_) {}
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video→MP3',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF212121),
          elevation: 0,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Color(0xFF2E7D32),
          unselectedItemColor: Color(0xFF9E9E9E),
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
  int i = 0;
  static const _pages = [ConvertScreen(), PlayerScreen(), FilesScreen(), ProfileScreen()];

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
          if (mounted) setState(() => i = 1);
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
          if (mounted) setState(() => i = 1);
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
      body: IndexedStack(index: i, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: i,
        onTap: (v) => setState(() => i = v),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.swap_horiz), label: 'Конвертер'),
          BottomNavigationBarItem(icon: Icon(Icons.play_circle_outline), label: 'Плеер'),
          BottomNavigationBarItem(icon: Icon(Icons.folder_open), label: 'Файлы'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Профиль'),
        ],
      ),
    );
  }
}
