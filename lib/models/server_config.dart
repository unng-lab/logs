import 'dart:convert';

/// Конфигурация подключения к удалённому серверу по SSH.
class ServerConfig {
  ServerConfig({
    String? id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.password,
    this.privateKey,
    this.passphrase,
    this.defaultService,
  }) : id = id ?? _generateId();

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKey;
  final String? passphrase;
  final String? defaultService;

  /// Создаёт копию конфигурации с возможностью переопределения полей.
  ServerConfig copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    String? privateKey,
    String? passphrase,
    String? defaultService,
  }) {
    return ServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      privateKey: privateKey ?? this.privateKey,
      passphrase: passphrase ?? this.passphrase,
      defaultService: defaultService ?? this.defaultService,
    );
  }

  /// Сериализует объект в JSON для сохранения в SharedPreferences.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'privateKey': privateKey,
      'passphrase': passphrase,
      'defaultService': defaultService,
    };
  }

  /// Восстанавливает конфигурацию из JSON-структуры.
  static ServerConfig fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      id: json['id'] as String?,
      name: json['name'] as String? ?? 'Server',
      host: json['host'] as String? ?? 'localhost',
      port: (json['port'] as num?)?.toInt() ?? 22,
      username: json['username'] as String? ?? 'root',
      password: json['password'] as String?,
      privateKey: json['privateKey'] as String?,
      passphrase: json['passphrase'] as String?,
      defaultService: json['defaultService'] as String?,
    );
  }

  /// Кодирует список конфигураций в строку JSON.
  static String encodeList(List<ServerConfig> servers) {
    final items = servers.map((server) => server.toJson()).toList();
    return jsonEncode(items);
  }

  /// Декодирует строку JSON в список конфигураций.
  static List<ServerConfig> decodeList(String? value) {
    if (value == null || value.isEmpty) {
      return <ServerConfig>[];
    }
    final decoded = jsonDecode(value) as List<dynamic>;
    return decoded
        .map((dynamic item) => ServerConfig.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Генерирует уникальный идентификатор на основе текущего времени.
  static String _generateId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return timestamp.toRadixString(16);
  }
}
