import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/data/local/archive_password_store.dart';

export 'package:yomu/src/data/local/archive_password_store.dart';

/// 加密压缩包 / 加密 PDF 密码安全存储 Provider（LMB-13）。
final Provider<ArchivePasswordStore> archivePasswordStoreProvider =
    Provider<ArchivePasswordStore>((Ref _) => ArchivePasswordStore());

/// 常用解压密码词典控制器（支持增删与立即持久化到系统钥匙串）。
class CommonPasswordsController extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() =>
      ref.watch(archivePasswordStoreProvider).loadCommonPasswords();

  Future<void> add(String password) async {
    final trimmed = password.trim();
    if (trimmed.isEmpty) return;
    final next = await ref
        .read(archivePasswordStoreProvider)
        .addCommonPassword(trimmed);
    state = AsyncValue<List<String>>.data(next);
  }

  Future<void> remove(String password) async {
    final next = await ref
        .read(archivePasswordStoreProvider)
        .removeCommonPassword(password);
    state = AsyncValue<List<String>>.data(next);
  }
}

final AsyncNotifierProvider<CommonPasswordsController, List<String>>
commonPasswordsProvider =
    AsyncNotifierProvider<CommonPasswordsController, List<String>>(
      CommonPasswordsController.new,
    );
