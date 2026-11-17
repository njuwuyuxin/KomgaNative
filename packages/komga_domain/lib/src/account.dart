/// 当前登录的 Komga 账号。
///
/// Komga 的 `UserDto` 没有"用户名"字段，只有 email 与角色，所以展示名就用 email。
class Account {
  const Account({
    required this.id,
    required this.email,
    this.roles = const <String>[],
  });

  final String id;
  final String email;
  final List<String> roles;

  String get displayName => email;

  bool get isAdmin => roles.any((String r) => r.toUpperCase() == 'ADMIN');

  @override
  bool operator ==(Object other) =>
      other is Account && other.id == id && other.email == email;

  @override
  int get hashCode => Object.hash(id, email);

  @override
  String toString() => 'Account($email)';
}
