// Ключ OpenRouter не зашит в репозиторий (чтобы GitHub Push Protection никогда не блокировал push).
// Пользователь вводит и подтверждается ключ вручную в блоке «API-ключ OpenRouter» внутри приложения,
// либо передаёт при сборке через --dart-define=OPENROUTER_API_KEY=...
class Secrets {
  static const String openRouterKey = String.fromEnvironment(
    'OPENROUTER_API_KEY',
    defaultValue: '',
  );
}
