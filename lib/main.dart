import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'sender_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const PulseSenderApp());
}

class PulseSenderApp extends StatelessWidget {
  const PulseSenderApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PulseSender',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF303030)),
        scaffoldBackgroundColor: const Color(0xFFEDEDED),
      ),
      home: const SenderScreen(),
    );
  }
}

class SenderScreen extends StatefulWidget {
  const SenderScreen({super.key});
  @override
  State<SenderScreen> createState() => _SenderScreenState();
}

class _SenderScreenState extends State<SenderScreen> {
  final _svc = SenderService();
  String _status = 'Подготовка…';
  int _sent = 0;
  int _total = 0;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _svc.onProgress = (p) {
      if (!mounted) return;
      setState(() {
        _status = p.status;
        _sent = p.sent;
        _total = p.total;
      });
    };
    _start();
  }

  Future<void> _start() async {
    final ok = await _svc.requestPermissions();
    if (!ok) {
      setState(() { _denied = true; _status = 'Нет доступа к файлам'; });
      return;
    }
    await _svc.run();
  }

  @override
  void dispose() {
    _svc.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pct = _total > 0 ? (_sent * 100 / _total).clamp(0, 100).toInt() : 0;
    return Scaffold(
      backgroundColor: const Color(0xFFEDEDED),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_total == 0 && !_denied)
                  const SizedBox(width: 52, height: 52, child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF606060)))
                else if (_denied)
                  const Icon(Icons.folder_off_outlined, size: 56, color: Color(0xFF909090))
                else
                  SizedBox(
                    width: 130, height: 130,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(width: 130, height: 130, child: CircularProgressIndicator(value: pct / 100, strokeWidth: 4, color: const Color(0xFF202020), backgroundColor: const Color(0xFFD5D5D5))),
                        Text('$pct%', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w300, color: Color(0xFF202020))),
                      ],
                    ),
                  ),
                const SizedBox(height: 30),
                Text(_status, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: Color(0xFF303030))),
                if (_total > 0) ...[
                  const SizedBox(height: 8),
                  Text('$_sent из $_total', style: const TextStyle(fontSize: 13, color: Color(0xFF808080))),
                ],
                if (_denied) ...[
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () { setState(() => _denied = false); _start(); },
                    child: const Text('Разрешить доступ', style: TextStyle(color: Color(0xFF202020))),
                  ),
                ],
                const SizedBox(height: 40),
                Text('Пожалуйста, подождите', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
