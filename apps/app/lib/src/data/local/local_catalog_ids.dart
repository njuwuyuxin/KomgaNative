int _localIdSeq = 0;

/// 生成本机书库实体 ID（统一收敛在本机数据层，UI 与业务层不得嗅探该前缀）。
String generateLocalEntityId(String prefix) {
  final micros = DateTime.now().microsecondsSinceEpoch;
  _localIdSeq = (_localIdSeq + 1) & 0xFFFF;
  return 'local:${prefix}_${micros}_$_localIdSeq';
}
