import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/accessibility_bridge.dart';
import '../services/ai_service.dart';
import '../services/settings_service.dart';
import '../services/system_actions_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settings = SettingsService.instance;
  final AccessibilityBridge _bridge = AccessibilityBridge();
  final SystemActionsService _sys = SystemActionsService();
  late TextEditingController _apiKeyCtrl;
  bool _a11yEnabled = false;
  bool _overlayShown = false;
  bool _obscureKey = true;
  bool _testingKey = false;
  String? _keyStatusText;

  @override
  void initState() {
    super.initState();
    _apiKeyCtrl = TextEditingController(text: _settings.customApiKey);
    _settings.addListener(_onChanged);
    _checkA11yStatus();
  }

  @override
  void dispose() {
    _settings.removeListener(_onChanged);
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _checkA11yStatus() async {
    final ok = await _bridge.isAccessibilityEnabled();
    if (mounted) setState(() => _a11yEnabled = ok);
  }

  Future<void> _pasteKey() async {
    final data = await Clipboard.getData('text/plain');
    final txt = data?.text?.trim() ?? '';
    if (txt.isNotEmpty) {
      setState(() => _apiKeyCtrl.text = txt);
    }
  }

  Future<void> _confirmAndVerifyKey() async {
    final key = _apiKeyCtrl.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите или вставьте ваш API-ключ OpenRouter')),
      );
      return;
    }
    setState(() {
      _testingKey = true;
      _keyStatusText = null;
    });
    await _settings.updateApiKey(key, confirmed: true);
    final (_, msg) = await AiService.instance.verifyApiKey(key);
    if (!mounted) return;
    setState(() {
      _testingKey = false;
      _keyStatusText = msg;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _requestRuntimePermissions() async {
    await _sys.requestRuntimePermissions();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Открыт системный запрос разрешений Android')),
      );
    }
  }

  Future<void> _editBlacklistDialog() async {
    final ctrl = TextEditingController(
      text: _settings.blacklistedPackages.join('\n'),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Чёрный список пакетов (Банки / Защита)'),
        content: TextField(
          controller: ctrl,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'По одному package name на строку',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok == true) {
      final list = ctrl.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      await _settings.updateBlacklistedPackages(list);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки агента'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkA11yStatus,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.key, color: Color(0xFF3F51B5)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'ИИ-Бэкенд (OpenRouter Free + Vision)',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _settings.hasValidApiKey
                              ? Colors.green.withOpacity(0.15)
                              : Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _settings.hasValidApiKey ? 'Подтверждён' : 'Не задан',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color:
                                _settings.hasValidApiKey ? Colors.green[800] : Colors.orange[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _settings.selectedModel,
                    decoration: const InputDecoration(
                      labelText: 'Бесплатная модель LLM',
                      border: OutlineInputBorder(),
                    ),
                    items: SettingsService.availableModels
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(m, style: const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) _settings.updateModel(v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyCtrl,
                    obscureText: _obscureKey,
                    decoration: InputDecoration(
                      labelText: 'OpenRouter API-ключ (sk-or-v1-...)',
                      hintText: 'Вставьте ваш ключ OpenRouter и нажмите Подтвердить',
                      border: const OutlineInputBorder(),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Показать / скрыть',
                            icon: Icon(_obscureKey ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscureKey = !_obscureKey),
                          ),
                          IconButton(
                            tooltip: 'Вставить из буфера',
                            icon: const Icon(Icons.content_paste),
                            onPressed: _pasteKey,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _testingKey ? null : _confirmAndVerifyKey,
                      icon: _testingKey
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.verified_outlined),
                      label: Text(_testingKey
                          ? 'Проверка ключа в OpenRouter...'
                          : 'Подтвердить и сохранить ключ'),
                    ),
                  ),
                  if (_keyStatusText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _keyStatusText!,
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Автономность: План, Самопроверка и Сценарии',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('План (3–5 шагов) и самопроверка экрана'),
                    subtitle: const Text(
                      'Проверять после каждого шага, изменился ли экран, и менять маршрут при застревании',
                    ),
                    value: _settings.selfVerificationEnabled,
                    onChanged: _settings.updateSelfVerification,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Сохранённые сценарии'),
                    subtitle: const Text(
                      'Запоминать успешные задачи и выполнять их по шагам без лишних запросов к модели',
                    ),
                    value: _settings.useSavedScenarios,
                    onChanged: _settings.updateUseSavedScenarios,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Лимиты и Безопасность',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('Лимит шагов на задачу: ${_settings.maxSteps}'),
                  Slider(
                    value: _settings.maxSteps.toDouble(),
                    min: 10,
                    max: 50,
                    divisions: 8,
                    label: '${_settings.maxSteps}',
                    onChanged: (v) => _settings.updateMaxSteps(v.round()),
                  ),
                  Text('Таймаут задачи: ${_settings.maxMinutes} мин.'),
                  Slider(
                    value: _settings.maxMinutes.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: '${_settings.maxMinutes} мин.',
                    onChanged: (v) => _settings.updateMaxMinutes(v.round()),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Подтверждать опасные действия'),
                    subtitle: const Text('Звонки, SMS, удаление приложений'),
                    value: _settings.confirmDangerousActions,
                    onChanged: _settings.updateConfirmDangerous,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.shield_outlined, color: Color(0xFF3F51B5)),
                    title: const Text('Белый / чёрный список приложений'),
                    subtitle:
                        Text('Заблокировано пакетов: ${_settings.blacklistedPackages.length}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _editBlacklistDialog,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          Card(
            elevation: 0,
            child: Column(
              children: [
                SwitchListTile(
                  secondary:
                      const Icon(Icons.record_voice_over_outlined, color: Color(0xFF3F51B5)),
                  title: const Text('Голосовые ответы (TTS)'),
                  subtitle: const Text('Озвучивать результат выполнения задач и разговор секретаря'),
                  value: _settings.voiceResponsesEnabled,
                  onChanged: _settings.updateVoiceResponses,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.hearing_outlined, color: Color(0xFF3F51B5)),
                  title: const Text('Wake-word «Джарвис»'),
                  subtitle: const Text('Активация голосовых команд по ключевому слову'),
                  value: _settings.wakeWordJarvisEnabled,
                  onChanged: _settings.updateWakeWordJarvis,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        _a11yEnabled ? Icons.check_circle : Icons.warning_amber_rounded,
                        color: _a11yEnabled ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _a11yEnabled
                              ? 'AccessibilityService активен'
                              : 'AccessibilityService выключен (включите в настройках)',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _bridge.openAccessibilitySettings,
                    icon: const Icon(Icons.accessibility_new),
                    label: const Text('Открыть Accessibility настройки'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await _bridge.requestOverlayPermission();
                      _overlayShown = !_overlayShown;
                      await _bridge.toggleFloatingOverlay(_overlayShown);
                      setState(() {});
                    },
                    icon: const Icon(Icons.layers_outlined),
                    label: Text(_overlayShown
                        ? 'Скрыть плавающую кнопку Overlay'
                        : 'Разрешить и показать плавающую кнопку Overlay'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _bridge.openNotificationListenerSettings,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Доступ к уведомлениям (для Умного ответа)'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _requestRuntimePermissions,
                    icon: const Icon(Icons.security_outlined),
                    label: const Text(
                        'Запросить разрешения (Звонки, Антиспам, SMS, Календарь, Микрофон)'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
