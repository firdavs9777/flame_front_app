import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/providers/report_provider.dart';
import 'package:flame/services/report_service.dart';

final blockedUsersProvider =
    StateNotifierProvider<BlockedUsersNotifier, AsyncValue<List<BlockedUser>>>(
        (ref) {
  return BlockedUsersNotifier(ref.watch(reportServiceProvider));
});

class BlockedUsersNotifier extends StateNotifier<AsyncValue<List<BlockedUser>>> {
  final ReportService _reportService;

  BlockedUsersNotifier(this._reportService) : super(const AsyncValue.loading());

  /// Loads the blocked users list from the service.
  Future<void> load() async {
    state = const AsyncValue.loading();
    final result = await _reportService.getBlockedUsers();
    if (result.success && result.data != null) {
      state = AsyncValue.data(result.data!);
    } else {
      state = AsyncValue.error(
        result.error ?? 'Failed to load blocked users',
        StackTrace.current,
      );
    }
  }

  /// Re-fetches the blocked users list. Alias for [load].
  Future<void> refresh() => load();

  /// Unblocks [userId] via the service and, on success, removes them from
  /// the current list. Returns whether the unblock succeeded.
  Future<bool> unblock(String userId) async {
    final result = await _reportService.unblockUser(userId);
    if (!result.success) return false;

    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.where((u) => u.id != userId).toList(),
      );
    }
    return true;
  }
}
