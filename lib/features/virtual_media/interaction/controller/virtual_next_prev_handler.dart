import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/playback/vm_playback_controller.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';

/// Next / Previous always cross virtual bodies (§4).
///
/// Clears current virtual cursor, resolves the NEXT/PREV virtual-or-real
/// media via scenario resolver, and feeds it. If the target is virtual and
/// has saved progress, resume from that segment/position; otherwise start
/// from segment 0.
class VirtualNextPrevHandler {
  const VirtualNextPrevHandler();

  /// Returns true when a cross-item advance was performed.
  Future<bool> advanceAcrossItems({required bool forward}) async {
    final ctrl = VirtualMediaController.instance;
    // Clear virtual cursor notion — next/prev never steps inside the item.
    // The actual queue advance is delegated to the scenario provider via
    // the registry; this helper only ensures we don't stay inside.
    if (!ctrl.isActive) return false;
    // Deactivate current session before scenario step so the registry's
    // scenario path isn't short-circuited by vm.isActive. Navigation keeps
    // the body's anchor so returning (prev) resumes the last position —
    // this handler's contract ("has saved progress → resume") requires it.
    // Lightweight: the queue + autoplay stay (the next feed overwrites both),
    // so no empty-queue flash and no autoplay off/on toggle per step.
    await ctrl.deactivateForNavigation();
    // Caller (registry.facade) will invoke scenario next/prev + play().
    return true;
  }

  /// Resolve the virtual queue siblings for the current scenario stream —
  /// used by `ScenarioPlaybackProvider.play` already, exposed here for
  /// cross-item navigation that needs sibling index.
  ///
  /// Scenario-order groups (the resolver's own materialization) so the sibling
  /// queue matches the displayed merged list; base-order grouping diverged for
  /// non-default sort / shuffle / duplicate policy.
  Future<List<VirtualMediaItem>> siblingQueueFor(
      String scenarioId, String ruleId) async {
    final store = usePlaybackScenarioStore();
    final groups = await store.resolver.resolveVmGroupsFor(
      scenarioId,
      playbackVersion: store.state.playbackVersion,
    );
    return groups.inOrder.where((i) => i.ruleId == ruleId).toList();
  }
}
