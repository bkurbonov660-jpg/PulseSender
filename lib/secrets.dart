// 🔐 Ключ OpenRouter не зашит в репозиторий (чтобы GitHub Push Protection никогда не блокировал push).
// Пользователь вводит и подтверждает ключ вручную прямо в блоке «🔑 API-ключ OpenRouter» внутри приложения
// (на главном экране Агента или в Настройках), либо передаёт при сборке через --dart-define=OPENROUTER_API_KEY=...
class Secrets {
  static const String openRouterKey = String.fromEnvironment(
    'OPENROUTER_API_KEY',
    defaultValue: '',
  );
}
