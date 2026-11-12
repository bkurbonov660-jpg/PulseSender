import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/agent_controller.dart';
import '../services/ai_service.dart';
import '../services/automation_service.dart';
import '../services/scenario_service.dart';
import '../services/settings_service.dart';
import '../services/voice_service.dart';
import '../widgets/agent_log_tile.dart';
import '../widgets/confirm_action_dialog.dart';

class AgentScreen extends StatefulWidget {
  const AgentScreen({super.key});

  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> {
  final TextEditingController _goalCtrl = TextEditingController();
  late final TextEditingController _apiKeyCtrl;
  final AgentController _agent = AgentController.instance;
  final VoiceService _voice = VoiceService.instance;
  final SettingsService _settings = SettingsService.instance;
  final ScenarioService _scenarios = ScenarioService.instance;

  bool _showKeyEditor = false;
  bool _obscureKey = true;
  bool _verifyingKey = false;
  String? _keyVerifyMessage;

  @override
  void initState() {
    super.initState();
    _apiKeyCtrl = TextEditingController(text: _settings.customApiKey);
    _showKeyEditor = !_settings.hasValidApiKey;
    _agent.addListener(_onChanged);
    _voice.addListener(_onChanged);
    _settings.addListener(_onChanged);
    _scenarios.addListener(_onChanged);
    _agent.onConfirmDangerousAction = (action) async {
      if (!mounted) return false;
      return ConfirmActionDialog.show(context, action);
    };
  }

  @override
  void dispose() {
    _agent.removeListener(_onChanged);
    _voice.removeListener(_onChanged);
    _settings.removeListener(_onChanged);
    _scenarios.removeListener(_onChanged);
    _goalCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _pasteApiKey() async {
    final data = await Clipboard.getData('text/plain');
    final txt = data?.text?.trim() ?? '';
    if (txt.isNotEmpty) {
      setState(() {
        _apiKeyCtrl.text = txt;
      });
    }
  }

  Future<void> _confirmAndSaveApiKey() async {
    final key = _apiKeyCtrl.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Вставьте ваш API-ключ OpenRouter (sk-or-v1-...)')),
      );
      return;
    }
    setState(() {
      _verifyingKey = true;
      _keyVerifyMessage = null;
    });
    await _settings.updateApiKey(key, confirmed: true);
    final (ok, msg) = await AiService.instance.verifyApiKey(key);
    if (!mounted) return;
    setState(() {
      _verifyingKey = false;
      _keyVerifyMessage = msg;
      if (ok) _showKeyEditor = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _toggleMic() async {
    if (_voice.isListening) {
      await _voice.stopListening();
    } else {
      await _voice.startListening(
        onResult: (words) {
          setState(() {
            _goalCtrl.text = words;
          });
        },
      );
    }
  }

  void _sendToAgent() {
    final t = _goalCtrl.text.trim();
    if (t.isEmpty) return;
    _agent.addUserMessage(t);
    _goalCtrl.clear();
  }

  void _startGoal() {
    final text = _goalCtrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите задачу для агента или нажмите на микрофон')),
      );
      return;
    }
    if (!_settings.hasValidApiKey) {
      setState(() => _showKeyEditor = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала вставьте и подтвердите API-ключ OpenRouter выше')),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    _agent.runAgent(text);
  }

  void _showSavedScenariosSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final list = _scenarios.scenarios;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '⚡ Сохранённые сценарии',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Всего: ${list.length}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Агент автоматически запоминает успешные цепочки шагов и в следующий раз проходит по ним мгновенно.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const Divider(height: 18),
              Expanded(
                child: list.isEmpty
                    ? const Center(
                        child: Text(
                          'Пока нет сохранённых сценариев. Выполните любую задачу — агент запомнит её автоматически!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54),
                        ),
                      )
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final sc = list[i];
                          return ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFFE8EAF6),
                              child: Icon(Icons.bolt, color: Color(0xFF3F51B5)),
                            ),
                            title: Text(
                              sc.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'Шагов: ${sc.actions.length} · Успешных запусков: ${sc.successCount}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.play_arrow, color: Color(0xFF3F51B5)),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _goalCtrl.text = sc.title;
                                _startGoal();
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _scheduleDelayedDialog() async {
    final text = _goalCtrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала напишите задачу в поле "Что сделать?"')),
      );
      return;
    }
    int minutes = 60;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Отложенный запуск (AlarmManager)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Задача: "$text"'),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: minutes,
                decoration: const InputDecoration(
                  labelText: 'Когда выполнить?',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Через 1 минуту')),
                  DropdownMenuItem(value: 15, child: Text('Через 15 минут')),
                  DropdownMenuItem(value: 60, child: Text('Через 1 час')),
                  DropdownMenuItem(value: 540, child: Text('Завтра утром (через 9 часов)')),
                ],
                onChanged: (v) => setSt(() => minutes = v ?? 60),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Запланировать')),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      await AutomationService.instance.scheduleOneShotTask(
        goalPrompt: text,
        delay: Duration(minutes: minutes),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Задача запланирована через $minutes мин.')),
        );
      }
    }
  }

  Widget _buildApiKeyCard() {
    final hasKey = _settings.hasValidApiKey;
    if (hasKey && !_showKeyEditor) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            _apiKeyCtrl.text = _settings.effectiveApiKey;
            setState(() => _showKeyEditor = true);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ключ активен (${_settings.maskedApiKey}) · ${_settings.selectedModel}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Text(
                  'Изменить',
                  style: TextStyle(fontSize: 12, color: Color(0xFF3F51B5), fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: const Color(0xFFE8EAF6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF3F51B5), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.key, color: Color(0xFF3F51B5), size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'API-ключ OpenRouter (ручной ввод)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                if (hasKey)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _showKeyEditor = false),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _apiKeyCtrl,
              obscureText: _obscureKey,
              decoration: InputDecoration(
                hintText: 'Вставьте ключ sk-or-v1-...',
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Показать / скрыть',
                      icon: Icon(_obscureKey ? Icons.visibility_off : Icons.visibility, size: 18),
                      onPressed: () => setState(() => _obscureKey = !_obscureKey),
                    ),
                    IconButton(
                      tooltip: 'Вставить из буфера',
                      icon: const Icon(Icons.content_paste, size: 18),
                      onPressed: _pasteApiKey,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _verifyingKey ? null : _confirmAndSaveApiKey,
                    icon: _verifyingKey
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(_verifyingKey ? 'Проверка...' : 'Подтвердить и сохранить ключ'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF3F51B5),
                    ),
                  ),
                ),
              ],
            ),
            if (_keyVerifyMessage != null) ...[
              const SizedBox(height: 6),
              Text(
                _keyVerifyMessage!,
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActivePlanCard() {
    if (_agent.currentPlan.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EAF6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3F51B5).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.checklist_rtl, size: 16, color: Color(0xFF3F51B5)),
              SizedBox(width: 6),
              Text(
                'План ИИ (3–5 шагов с самопроверкой экрана):',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ..._agent.currentPlan.map(
            (p) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• $p',
                style: const TextStyle(fontSize: 11, color: Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxSteps = _settings.maxSteps;
    final curStep = _agent.currentStepIndex.clamp(0, maxSteps);
    final progress = maxSteps > 0 ? (curStep / maxSteps).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.smart_toy_outlined, color: Color(0xFF3F51B5)),
            SizedBox(width: 8),
            Text('PulseAgent v2.0'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Сохранённые сценарии (${_scenarios.scenarios.length})',
            icon: Badge(
              isLabelVisible: _scenarios.scenarios.isNotEmpty,
              label: Text('${_scenarios.scenarios.length}'),
              child: const Icon(Icons.auto_graph_outlined),
            ),
            onPressed: _showSavedScenariosSheet,
          ),
          IconButton(
            tooltip: 'API-ключ OpenRouter',
            icon: Icon(
              Icons.vpn_key_outlined,
              color: _settings.hasValidApiKey ? Colors.green : Colors.orange,
            ),
            onPressed: () {
              _apiKeyCtrl.text = _settings.effectiveApiKey;
              setState(() => _showKeyEditor = !_showKeyEditor);
            },
          ),
          IconButton(
            tooltip: 'Запланировать по времени',
            icon: const Icon(Icons.schedule),
            onPressed: _scheduleDelayedDialog,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _buildApiKeyCard(),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.indigo.withOpacity(0.25)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      controller: _goalCtrl,
                      maxLines: 3,
                      minLines: 2,
                      decoration: InputDecoration(
                        hintText:
                            'Что сделать? («Сравни цены на барбершоп и запиши меня», «Ответь в MAX», «Найди в интернете где дешевле...»)',
                        border: InputBorder.none,
                        suffixIcon: IconButton.filledTonal(
                          onPressed: _toggleMic,
                          icon: Icon(
                            _voice.isListening ? Icons.mic : Icons.mic_none,
                            color: _voice.isListening ? Colors.red : const Color(0xFF3F51B5),
                          ),
                          tooltip: 'Голосовой ввод',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _agent.isRunning ? _sendToAgent : _startGoal,
                            icon: Icon(_agent.isRunning ? Icons.send : Icons.play_arrow),
                            label: Text(_agent.isRunning ? 'Сказать агенту' : 'Запустить ИИ'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF3F51B5),
                              minimumSize: const Size.fromHeight(44),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _agent.isRunning
                                ? () => _agent.emergencyStop(reason: 'Остановлено кнопкой Стоп')
                                : null,
                            icon: const Icon(Icons.stop),
                            label: const Text('Стоп'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            _buildActivePlanCard(),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _agent.statusBanner,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Шаг $curStep / $maxSteps',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF3F51B5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _agent.isRunning
                          ? progress
                          : (_agent.liveSteps.isNotEmpty ? 1.0 : 0.0),
                      minHeight: 6,
                      color: const Color(0xFF3F51B5),
                      backgroundColor: const Color(0xFFE8EAF6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: _agent.liveSteps.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.psychology_outlined,
                            size: 48,
                            color: Colors.indigo.withOpacity(0.35),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Лог автономного агента: План (3–5 шагов) → Действие → Самопроверка экрана → Сохранение сценария',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _agent.liveSteps.length,
                      itemBuilder: (_, idx) {
                        final step = _agent.liveSteps[_agent.liveSteps.length - 1 - idx];
                        return AgentLogTile(step: step);
                      },
                    ),
            ),
            const SizedBox(height: 6),

            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton.icon(
                onPressed: () =>
                    _agent.emergencyStop(reason: 'Нажата красная кнопка ЭКСТРЕННЫЙ СТОП'),
                icon: const Icon(Icons.dangerous_outlined),
                label: const Text(
                  'ЭКСТРЕННЫЙ СТОП (или потрясите телефон)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD32F2F),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
