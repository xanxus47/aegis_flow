import 'offline_store.dart';
import 'sync_manager.dart';

class OfflineBootstrap {
  OfflineBootstrap._();

  static bool _bootstrapped = false;

  static Future<void> init() async {
    if (_bootstrapped) return;
    await OfflineStore.instance.init();
    await SyncManager.instance.start();
    _bootstrapped = true;
  }
}
