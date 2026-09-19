import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../character/domain/models/character.dart';
import '../../frontend_card/domain/frontend_card_payload.dart';
import '../../regex/domain/models/regex_script.dart';
import '../../variables/domain/models/variable_definition.dart';
import '../../world_info/domain/models/world_info.dart';
import '../domain/models/card_project.dart';
import '../domain/models/card_field.dart';
import '../domain/models/project_entry.dart';
import 'frontend_card_packager.dart';
import 'variable_packager.dart';

/// 打包结果：一张可入库的角色卡 + 配套世界书。
class PackedCard {
  PackedCard({
    required this.character,
    this.worldbook,
    this.mountScript,
    this.variables,
  });

  final Character character;

  /// 世界书（没有世界书条目时为 null）。
  final WorldInfo? worldbook;

  /// 前端面板的挂载点正则（没有前端面板时为 null）。
  ///
  /// 调用方要把它存进全局正则池，否则刚导出的卡在 App 内**立刻**用不了
  /// 前端面板 —— 得等一次重新导入才生效。
  final RegexScript? mountScript;

  /// 变量定义（项目里没有变量信息时为 null）。
  final PackedVariables? variables;

  bool get hasWorldbook => worldbook != null && worldbook!.entries.isNotEmpty;
}

/// 把创作项目打包成 SillyTavern 角色卡（chara_card_v2）+ 世界书。
///
/// **整条管道的设计**：
/// ```
/// ProjectEntry(worldbook)
///   → WorldInfo(entries: [WorldInfoEntry(...)])
///   → character.rawCharacterBook = worldInfo.toJson()
///   → CharacterExporter._toV2Json() 输出 data['character_book']
///   → 再次导入时 _parseV2Spec() 自动写进全局池并回填 characterBookId
/// ```
/// 同时我们会**主动**把 WorldInfo 存进全局池并回填 `characterBookId`，
/// 这样刚导出的卡在 App 内立刻就能用世界书，不必等一次重新导入。
class WorldbookPackager {
  const WorldbookPackager._();

  /// 打包。
  ///
  /// [existingCharacterId] 非空时复用它 —— 这让「重复导出」变成幂等更新，
  /// 而不是每次都新建一张重复卡。
  static PackedCard pack(
    CardProject project, {
    String? existingCharacterId,
  }) {
    final worldbook = buildWorldInfo(project);
    final frontend = FrontendCardPackager.build(project);
    final variables = VariablePackager.build(project);
    final character = buildCharacter(
      project,
      existingCharacterId: existingCharacterId,
      worldbook: worldbook,
      frontend: frontend,
      variables: variables,
    );
    return PackedCard(
      character: character,
      worldbook: worldbook,
      mountScript: frontend?.mountScript,
      variables: variables,
    );
  }

  /// 由条目构建世界书。
  static WorldInfo? buildWorldInfo(CardProject project) {
    final entries = project.worldbookEntries;
    if (entries.isEmpty) {
      return null;
    }

    // uid 必须唯一且稳定：用微秒时间戳做基数，逐条递增。
    var uid = DateTime.now().microsecondsSinceEpoch;

    final worldInfoEntries = <WorldInfoEntry>[];
    for (final entry in entries) {
      final content = entry.content.trim();
      if (content.isEmpty) {
        continue;
      }
      final keys = entry.keys
          .map((key) => key.trim())
          .where((key) => key.isNotEmpty)
          .toList();
      final secondaryKeys = entry.secondaryKeys
          .map((key) => key.trim())
          .where((key) => key.isNotEmpty)
          .toList();

      worldInfoEntries.add(
        WorldInfoEntry(
          uid: uid++,
          keys: keys,
          secondaryKeys: secondaryKeys,
          comment: entry.title.trim().isEmpty ? '未命名条目' : entry.title.trim(),
          content: content,
          role: 'system',
          // 没有关键词又不是常驻条目 → 永远触发不了，导入后就是一条死设定。
          // 这里兜底成常驻，避免用户拿到一张「世界书不生效」的卡。
          constant: entry.constant || keys.isEmpty,
          disable: false,
          selective: secondaryKeys.isNotEmpty,
          selectiveLogic: 0,
          position: entry.position,
          depth: entry.depth,
          order: entry.order,
          probability: 100,
          useProbability: true,
        ),
      );
    }

    if (worldInfoEntries.isEmpty) {
      return null;
    }

    return WorldInfo(
      id: const Uuid().v4(),
      name: '${project.characterName} · 世界书',
      disabled: false,
      entries: worldInfoEntries,
    );
  }

  /// 由条目构建角色卡。
  static Character buildCharacter(
    CardProject project, {
    String? existingCharacterId,
    WorldInfo? worldbook,
    PackedFrontend? frontend,
    PackedVariables? variables,
  }) {
    String field(String key) {
      for (final entry in project.entries) {
        if (entry.kind == EntryKind.characterCard &&
            entry.fieldKey == key &&
            entry.hasContent) {
          return entry.content.trim();
        }
      }
      return '';
    }

    List<String> listField(String key) {
      final raw = field(key);
      if (raw.isEmpty) {
        return const <String>[];
      }
      return splitListText(raw);
    }

    final name = field(kNameFieldKey);
    final description = field('description');
    final personality = field('personality');
    final systemPrompt = field('system_prompt');
    final scenario = field('scenario');
    final firstMessage = field('first_mes');
    final exampleDialogue = field('mes_example');
    final creatorNotes = field('creator_notes');

    // 前端面板：产物进 extensions，挂载点正则也随卡带走。
    //
    // 正则放在 `extensions.regex_scripts` 里，重新导入时
    // `_parseV2Spec()` 会自动写进全局池并回填 `regexScriptIds` ——
    // 和角色卡内世界书走的是同一条路。
    var extensions = <String, dynamic>{};
    if (frontend != null) {
      extensions = FrontendCardPayload.attach(extensions, frontend.payload);
      extensions['regex_scripts'] = <Map<String, dynamic>>[
        frontend.mountScript.toJson(),
      ];
    }

    // 变量定义：**修掉「MVU 三件套从来没进过角色卡」这个最大的漏洞**。
    //
    // 之前 `mvuSchemaText` / `mvuInitvarText` / `mvuUpdateRulesText` /
    // `mvuVariablesJson` 只被喂给 AI 当上下文、被本地质检比对、被导出页展示，
    // 打包时一个都没进 `extensions` —— 所以导出的卡在聊天里读不到任何变量，
    // 前端面板只能显示兜底 0。
    //
    // 写进 `extensions.ykx_variables` 之后，它会随 chara_card_v2 一起导出，
    // 再次导入时由 `rawExtensions` 原样带回。
    if (variables != null) {
      extensions = VariableDefinition.attach(extensions, variables.definition);
    }

    return Character(
      id: existingCharacterId?.trim().isNotEmpty == true
          ? existingCharacterId!.trim()
          : const Uuid().v4(),
      name: name.isEmpty ? project.characterName : name,
      description: description,
      personality: personality,
      systemPrompt: systemPrompt,
      creatorNotes: creatorNotes,
      tags: listField('tags'),
      creator: 'yuanKX 创作工坊',
      version: '1.0',
      systemInstruction:
          systemPrompt.isNotEmpty ? systemPrompt : personality,
      scenario: scenario,
      firstMessage: firstMessage,
      alternateGreetings: listField('alternate_greetings'),
      exampleDialogue: exampleDialogue,
      cardSpec: 'chara_card_v2',
      cardSpecVersion: '2.0',
      characterBookId: worldbook?.id,
      rawCharacterBook: worldbook?.toJson(),
      // 角色卡自带的系统提示词槽位是给扮演指令用的，别塞别的东西；
      // 每轮提醒模型吐挂载标记属于「作者注释」，语义上正好。
      authorsNote: frontend?.postHistoryInstruction ?? '',
      regexScriptIds: frontend == null
          ? const <String>[]
          : <String>[frontend.mountScript.id],
      rawExtensions: extensions,
    );
  }

  /// 把数组型字段的文本拆成多项。
  ///
  /// 支持三种写法（按优先级）：
  /// 1. JSON 数组字符串 —— `["第一条","第二条"]`（AI 直接吐数组时用这种）；
  /// 2. 一行一项（界面上的标准写法）；
  /// 3. 顿号/逗号/分号分隔（模型偶尔会这么吐）。
  static List<String> splitListText(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return const <String>[];
    }

    if (text.startsWith('[') && text.endsWith(']')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is List) {
          final items = decoded
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList();
          if (items.isNotEmpty) {
            return items;
          }
        }
      } catch (_) {
        // 不是合法 JSON 就退回按行拆。
      }
    }

    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    // 只有一行时才按分隔符拆（多行说明是标准写法，不该再拆）。
    if (lines.length > 1) {
      return lines;
    }

    return text
        .split(RegExp(r'[,，、;；]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}
