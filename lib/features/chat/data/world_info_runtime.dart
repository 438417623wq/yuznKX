import '../../world_info/data/world_info_provider.dart';
import '../../world_info/domain/models/world_info.dart';

class WorldInfoOrderingEntry {
  final WorldInfoEntry entry;
  final String sourceKind;
  final int sourceOrder;
  final bool isSticky;

  const WorldInfoOrderingEntry({
    required this.entry,
    required this.sourceKind,
    required this.sourceOrder,
    this.isSticky = false,
  });
}

String buildWorldInfoScanSource({
  required int requestedDepth,
  required List<String> historyBuffer,
  String personaDescription = '',
  String characterDescription = '',
  String characterPersonality = '',
  String characterDepthPrompt = '',
  String scenario = '',
  String creatorNotes = '',
  List<String> injectionTexts = const <String>[],
  List<String> recursionBuffer = const <String>[],
  bool includeRecursionBuffer = false,
}) {
  final historySlice = requestedDepth <= 0
      ? const <String>[]
      : historyBuffer.take(requestedDepth).toList(growable: false);

  const matcher = '\x01';
  const joiner = '\n\x01';
  final blocks = <String>[
    if (historySlice.isNotEmpty) '$matcher${historySlice.join(joiner)}',
    if (personaDescription.trim().isNotEmpty) personaDescription,
    if (characterDescription.trim().isNotEmpty) characterDescription,
    if (characterPersonality.trim().isNotEmpty) characterPersonality,
    if (characterDepthPrompt.trim().isNotEmpty) characterDepthPrompt,
    if (scenario.trim().isNotEmpty) scenario,
    if (creatorNotes.trim().isNotEmpty) creatorNotes,
    if (injectionTexts.isNotEmpty) injectionTexts.join(joiner),
    if (includeRecursionBuffer && recursionBuffer.isNotEmpty)
      recursionBuffer.join(joiner),
  ];

  return blocks.where((block) => block.trim().isNotEmpty).join(joiner);
}

int compareWorldInfoActivationOrder(
  WorldInfoOrderingEntry a,
  WorldInfoOrderingEntry b,
  WorldInfoCharacterStrategy strategy,
) {
  final stickyCmp = (b.isSticky ? 1 : 0).compareTo(a.isSticky ? 1 : 0);
  if (stickyCmp != 0) {
    return stickyCmp;
  }

  final constantCmp =
      (b.entry.constant ? 1 : 0).compareTo(a.entry.constant ? 1 : 0);
  if (constantCmp != 0) {
    return constantCmp;
  }

  final sourceCmp = _worldInfoSourceTier(a.sourceKind, strategy).compareTo(
    _worldInfoSourceTier(b.sourceKind, strategy),
  );
  if (sourceCmp != 0) {
    return sourceCmp;
  }

  final orderCmp = b.entry.order.compareTo(a.entry.order);
  if (orderCmp != 0) {
    return orderCmp;
  }

  final sourceOrderCmp = a.sourceOrder.compareTo(b.sourceOrder);
  if (sourceOrderCmp != 0) {
    return sourceOrderCmp;
  }

  return a.entry.uid.compareTo(b.entry.uid);
}

int compareWorldInfoPromptOrder(
  WorldInfoOrderingEntry a,
  WorldInfoOrderingEntry b,
  WorldInfoCharacterStrategy strategy,
) {
  final posCmp = a.entry.position.compareTo(b.entry.position);
  if (posCmp != 0) {
    return posCmp;
  }

  final depthCmp = a.entry.depth.compareTo(b.entry.depth);
  if (depthCmp != 0) {
    return depthCmp;
  }

  final sourceCmp = _worldInfoSourceTier(a.sourceKind, strategy).compareTo(
    _worldInfoSourceTier(b.sourceKind, strategy),
  );
  if (sourceCmp != 0) {
    return sourceCmp;
  }

  final orderCmp = a.entry.order.compareTo(b.entry.order);
  if (orderCmp != 0) {
    return orderCmp;
  }

  final sourceOrderCmp = a.sourceOrder.compareTo(b.sourceOrder);
  if (sourceOrderCmp != 0) {
    return sourceOrderCmp;
  }

  return a.entry.uid.compareTo(b.entry.uid);
}

int _worldInfoSourceTier(
  String sourceKind,
  WorldInfoCharacterStrategy strategy,
) {
  switch (sourceKind.trim().toLowerCase()) {
    case 'session':
      return 0;
    case 'persona':
      return 1;
    case 'character':
      if (strategy == WorldInfoCharacterStrategy.evenly) {
        return 2;
      }
      return strategy == WorldInfoCharacterStrategy.globalFirst ? 3 : 2;
    case 'global':
      if (strategy == WorldInfoCharacterStrategy.evenly) {
        return 2;
      }
      return strategy == WorldInfoCharacterStrategy.globalFirst ? 2 : 3;
    default:
      return 4;
  }
}
