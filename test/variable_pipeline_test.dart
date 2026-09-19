/// 变量管道（P1）与质检 diff（P3）的单元测试。
///
/// **为什么这些测试重要**：变量管道的核心假设是「模型输出格式不可控」——
/// 四级降级链、字段名宽容、`add` 退化、裸 JSON 不误剥离，全部是**猜出来的**
/// 格式约定（没有真实 MVU 卡样本）。这里把每条约定钉死，改坏了立刻能发现。
///
/// 这些都是纯逻辑，不依赖 Flutter binding / Hive / 网络。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:silly_tavern_flutter/features/character_workshop/domain/text_diff.dart';
import 'package:silly_tavern_flutter/features/variables/data/variable_command_parser.dart';
import 'package:silly_tavern_flutter/features/variables/domain/models/variable_definition.dart';
import 'package:silly_tavern_flutter/features/variables/domain/models/variable_update.dart';
import 'package:silly_tavern_flutter/features/variables/domain/variable_path.dart';

void main() {
  // ---------------------------------------------------------------------------
  group('VariablePath — 路径规范化与 Pointer 互转', () {
    test('normalize 去掉首尾分隔符与空白，但不动内部', () {
      expect(VariablePath.normalize('  角色.好感度  '), '角色.好感度');
      expect(VariablePath.normalize('.角色.好感度.'), '角色.好感度');
      expect(VariablePath.normalize('..角色..'), '角色');
      // 内部分隔符不合并 —— 保持原样，避免与 JS 垫片行为不一致。
      expect(VariablePath.normalize('a..b'), 'a..b');
    });

    test('isValid 只认非空路径', () {
      expect(VariablePath.isValid('角色.好感度'), isTrue);
      expect(VariablePath.isValid(''), isFalse);
      expect(VariablePath.isValid('   '), isFalse);
      // 全是分隔符 → normalize 后为空。
      expect(VariablePath.isValid('..'), isFalse);
    });

    test('toPointer / fromPointer 往返一致', () {
      expect(VariablePath.toPointer('角色.好感度'), '/角色/好感度');
      expect(VariablePath.fromPointer('/角色/好感度'), '角色.好感度');
      // 不带前导斜杠也接受。
      expect(VariablePath.fromPointer('角色/好感度'), '角色.好感度');
      expect(VariablePath.toPointer(''), '');
      expect(VariablePath.fromPointer(''), '');
    });

    test('Pointer 转义遵循 RFC 6901（~ → ~0，/ → ~1）', () {
      expect(VariablePath.toPointer('a~b.c/d'), '/a~0b/c~1d');
      expect(VariablePath.fromPointer('/a~0b/c~1d'), 'a~b.c/d');
      // 往返必须还原成原路径。
      const original = '角色~1.路径/子项';
      expect(
        VariablePath.fromPointer(VariablePath.toPointer(original)),
        original,
      );
    });

    test('normalizeAny：斜杠开头按 Pointer 解，否则按点分路径', () {
      expect(VariablePath.normalizeAny('/角色/好感度'), '角色.好感度');
      expect(VariablePath.normalizeAny('角色.好感度'), '角色.好感度');
      expect(VariablePath.normalizeAny('  角色.好感度  '), '角色.好感度');
      expect(VariablePath.normalizeAny(''), '');
    });

    test('parentOf / leafOf / join', () {
      expect(VariablePath.parentOf('角色.好感度'), '角色');
      expect(VariablePath.parentOf('a.b.c'), 'a.b');
      // 顶层路径没有父级。
      expect(VariablePath.parentOf('好感度'), '');
      expect(VariablePath.leafOf('角色.好感度'), '好感度');
      expect(VariablePath.leafOf('好感度'), '好感度');
      expect(VariablePath.join('角色', '好感度'), '角色.好感度');
      expect(VariablePath.join('', '好感度'), '好感度');
      expect(VariablePath.join('角色', ''), '角色');
    });
  });

  // ---------------------------------------------------------------------------
  group('VariablePath.readFlat — 平铺优先，再逐层下钻', () {
    test('平铺键直接命中', () {
      expect(
        VariablePath.readFlat(const {'角色.好感度': 30}, '角色.好感度'),
        30,
      );
    });

    test('平铺键不存在时按 . 逐层下钻（兼容卡片自己塞的嵌套对象）', () {
      const nested = {
        '角色': {'好感度': 30, '生命值': 82},
      };
      expect(VariablePath.readFlat(nested, '角色.好感度'), 30);
      expect(VariablePath.readFlat(nested, '角色.生命值'), 82);
    });

    test('平铺键优先于嵌套结构（与 JS 垫片 readPath 的约定一致）', () {
      const both = {
        '角色.好感度': 99,
        '角色': {'好感度': 30},
      };
      expect(VariablePath.readFlat(both, '角色.好感度'), 99);
    });

    test('取不到时返回 null，不抛异常', () {
      const nested = {
        '角色': {'好感度': 30},
      };
      expect(VariablePath.readFlat(nested, '角色.生命值'), isNull);
      expect(VariablePath.readFlat(const {}, '角色.好感度'), isNull);
      expect(VariablePath.readFlat(nested, ''), isNull);
      // 中间节点是标量时不该继续下钻。
      expect(VariablePath.readFlat(const {'角色': 1}, '角色.好感度'), isNull);
    });

    test('containsFlat 只认平铺键，不做下钻', () {
      const nested = {
        '角色': {'好感度': 30},
      };
      expect(VariablePath.containsFlat(nested, '角色.好感度'), isFalse);
      expect(VariablePath.containsFlat(nested, '角色'), isTrue);
      expect(VariablePath.containsFlat(const {}, ''), isFalse);
    });

    test('toNumber 的转换与兜底', () {
      expect(VariablePath.toNumber(35), 35);
      expect(VariablePath.toNumber(3.5), 3.5);
      expect(VariablePath.toNumber('35'), 35);
      expect(VariablePath.toNumber(' 35 '), 35);
      expect(VariablePath.toNumber(true), 1);
      expect(VariablePath.toNumber(false), 0);
      expect(VariablePath.toNumber('abc'), 0);
      expect(VariablePath.toNumber(null), 0);
      // 「当前值不存在」要能和「当前值是 0」区分开，所以允许自定义兜底。
      expect(VariablePath.toNumber('abc', fallback: -1), -1);
    });
  });

  // ---------------------------------------------------------------------------
  group('VariableOp.fromJsonPatch — 字段名宽容', () {
    test('标准 JSON Patch', () {
      final op = VariableOp.fromJsonPatch(const {
        'op': 'replace',
        'path': '/角色/好感度',
        'value': 40,
      });
      expect(op, isNotNull);
      expect(op!.type, VariableOpType.set);
      expect(op.path, '角色.好感度');
      expect(op.value, 40);
    });

    test('increment 映射为 add', () {
      final op = VariableOp.fromJsonPatch(const {
        'op': 'increment',
        'path': '角色.好感度',
        'value': 5,
      });
      expect(op!.type, VariableOpType.add);
      expect(op.value, 5);
    });

    test('remove / delete / del 映射为 delete，且不需要 value', () {
      for (final raw in const ['remove', 'delete', 'del']) {
        final op = VariableOp.fromJsonPatch({
          'op': raw,
          'path': '角色.好感度',
        });
        expect(op, isNotNull, reason: 'op=$raw 应该能解析');
        expect(op!.type, VariableOpType.delete);
        expect(op.value, isNull);
      }
    });

    test('中文字段名与中文操作名', () {
      final op = VariableOp.fromJsonPatch(const {
        '操作': '删除',
        '变量': '角色.好感度',
      });
      expect(op!.type, VariableOpType.delete);
      expect(op.path, '角色.好感度');
    });

    test('无 op 时按「有 value 就 set」推断', () {
      final op = VariableOp.fromJsonPatch(const {'键': '角色.好感度', '值': '35'});
      expect(op!.type, VariableOpType.set);
      expect(op.path, '角色.好感度');
      // 没有声明 op 时不擅自转数字 —— 原样保留。
      expect(op.value, '35');
    });

    test('add 的值能转数字就累加，否则退化为 set', () {
      final numeric = VariableOp.fromJsonPatch(const {
        'op': 'add',
        'path': 'x',
        'value': '5',
      });
      expect(numeric!.type, VariableOpType.add);
      expect(numeric.value, 5);

      final textual = VariableOp.fromJsonPatch(const {
        'op': 'add',
        'path': 'x',
        'value': 'abc',
      });
      expect(textual!.type, VariableOpType.set);
      expect(textual.value, 'abc');
    });

    test('缺 path / 缺 value 时返回 null（跳过而不是瞎写）', () {
      expect(VariableOp.fromJsonPatch(const {'op': 'replace', 'value': 1}), isNull);
      expect(VariableOp.fromJsonPatch(const {'op': 'replace', 'path': '  '}), isNull);
      // 没给值又没说删 —— 无法执行。
      expect(
        VariableOp.fromJsonPatch(const {'op': 'replace', 'path': 'x'}),
        isNull,
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('VariableOp.fromTextLine — 「键: 值」降级路径', () {
    test('冒号 / 等号 / 全角冒号都认', () {
      for (final line in const ['角色.好感度: 35', '角色.好感度 = 35', '角色.好感度：35']) {
        final op = VariableOp.fromTextLine(line);
        expect(op, isNotNull, reason: line);
        expect(op!.type, VariableOpType.set);
        expect(op.path, '角色.好感度');
        expect(op.value, 35);
      }
    });

    test('值前带 + 按累加处理', () {
      final op = VariableOp.fromTextLine('角色.好感度: +5');
      expect(op!.type, VariableOpType.add);
      expect(op.value, 5);
    });

    test('值前带 - 按「设为负数」处理（不是减）', () {
      // 文本行里 `-5` 与 `+5` 不对称是刻意的：`+` 是增量写法，`-` 更像目标值。
      final op = VariableOp.fromTextLine('角色.好感度: -5');
      expect(op!.type, VariableOpType.set);
      expect(op.value, -5);
    });

    test('带引号的字符串会去掉引号', () {
      final op = VariableOp.fromTextLine('时间: "白天"');
      expect(op!.type, VariableOpType.set);
      expect(op.value, '白天');
    });

    test('不像赋值语句的行返回 null', () {
      expect(VariableOp.fromTextLine('这是一句普通的话'), isNull);
      expect(VariableOp.fromTextLine(''), isNull);
      expect(VariableOp.fromTextLine('   '), isNull);
      // ⚠️ 注意：`键:` 后面什么都不写会**返回 null**，而不是 delete。
      // 因为 `fromTextLine` 一进来就 trim 了整行，等号/冒号后已无字符可匹配。
      // 也就是说「空值 → delete」那个分支实际不可达（防御性代码）。
      // 删除操作请走 JSON 的 remove。
      expect(VariableOp.fromTextLine('角色.好感度:'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('VariableCommandParser — 四级降级链', () {
    test('第 1 级：<UpdateVariable> + <JSONPatch> 主格式', () {
      const content = '好的，我来更新。\n\n'
          '<UpdateVariable>\n'
          '<Analysis>好感度提升</Analysis>\n'
          '<JSONPatch>\n'
          '[{"op":"replace","path":"/角色/好感度","value":40}]\n'
          '</JSONPatch>\n'
          '</UpdateVariable>';

      final result = VariableCommandParser.parse(content);
      expect(result.matched, isTrue);
      expect(result.update!.format, 'json_patch');
      expect(result.update!.analysis, '好感度提升');
      expect(result.update!.ops, hasLength(1));
      expect(result.update!.ops.single.type, VariableOpType.set);
      expect(result.update!.ops.single.path, '角色.好感度');
      expect(result.update!.ops.single.value, 40);
      // 命中的整块要能从显示内容里剥掉。
      expect(result.spans, hasLength(1));
      expect(result.spans.single, contains('<UpdateVariable>'));
    });

    test('命中即停：主格式存在时不再看裸 JSON，也不会误剥裸 JSON', () {
      const content = '正文\n'
          '<UpdateVariable><JSONPatch>'
          '[{"op":"replace","path":"/a","value":1}]'
          '</JSONPatch></UpdateVariable>\n'
          '[{"op":"replace","path":"/b","value":2}]';

      final result = VariableCommandParser.parse(content);
      expect(result.update!.format, 'json_patch');
      expect(result.update!.ops, hasLength(1));
      expect(result.update!.ops.single.path, 'a');
      // 裸数组没被当成指令块 —— 它留在正文里，不该被剥掉。
      expect(result.spans, hasLength(1));
      expect(result.spans.single, isNot(contains('/b')));
    });

    test('第 2 级：<变量更新> 中文标签块（键: 值 行）', () {
      const content = '<变量更新>\n'
          '角色.好感度: 40\n'
          '角色.生命值: 82\n'
          '</变量更新>';

      final result = VariableCommandParser.parse(content);
      expect(result.matched, isTrue);
      expect(result.update!.format, 'cn_tag');
      expect(result.update!.ops, hasLength(2));
      expect(result.update!.ops[0].path, '角色.好感度');
      expect(result.update!.ops[0].value, 40);
      expect(result.update!.ops[1].path, '角色.生命值');
    });

    test('第 3 级：正文里的裸 JSON Patch 数组', () {
      const content = '好的。\n'
          '[{"op":"replace","path":"/a/b","value":1}]\n'
          '就这样。';

      final result = VariableCommandParser.parse(content);
      expect(result.matched, isTrue);
      expect(result.update!.format, 'json_array');
      expect(result.update!.ops, hasLength(1));
      expect(result.update!.ops.single.path, 'a.b');
      expect(result.spans.single, contains('/a/b'));
    });

    test('⛔ 安全边界：正文里的普通 JSON 数组不能被误当成指令并剥掉', () {
      const content = '数据如下：[{"name":"x","score":1}]';
      final result = VariableCommandParser.parse(content);
      // 没有任何可识别的操作 → 不认，也不剥。
      expect(result.matched, isFalse);
      expect(result.hasSpans, isFalse);
      expect(result.stripFrom(content), content);
    });

    test('第 4 级：变量宏 setvar / incvar / decvar', () {
      const content = '{{setvar::角色.好感度::45}}'
          '{{incvar::角色.生命值}}'
          '{{decvar::角色.理智}}';

      final result = VariableCommandParser.parse(content);
      expect(result.matched, isTrue);
      expect(result.update!.format, 'macro');
      expect(result.update!.ops, hasLength(3));
      expect(result.update!.ops[0].type, VariableOpType.set);
      expect(result.update!.ops[0].value, 45);
      expect(result.update!.ops[1].type, VariableOpType.add);
      expect(result.update!.ops[1].value, 1);
      expect(result.update!.ops[2].type, VariableOpType.add);
      expect(result.update!.ops[2].value, -1);
      expect(result.spans, hasLength(3));
    });

    test('空数组 = 模型声明「本轮无变化」：命中但不产生操作，仍会被剥掉', () {
      const content = '<UpdateVariable><JSONPatch>[]</JSONPatch></UpdateVariable>';
      final result = VariableCommandParser.parse(content);
      // matched 为 true 很关键：它决定「不必再发一次兜底提取请求」。
      expect(result.matched, isTrue);
      expect(result.hasUpdate, isFalse);
      expect(result.update!.ops, isEmpty);
      expect(result.hasSpans, isTrue);
    });

    test('宽松修补：单引号 + 尾随逗号 + 注释', () {
      const content = '<UpdateVariable><JSONPatch>'
          "[{'op':'replace','path':'/a/b','value':1},]"
          '</JSONPatch></UpdateVariable>';

      final result = VariableCommandParser.parse(content);
      expect(result.update!.ops, hasLength(1));
      expect(result.update!.ops.single.path, 'a.b');
      expect(result.update!.ops.single.value, 1);
    });

    test('⛔ 解析器绝不抛异常（模型吐半截 JSON 是常态）', () {
      const garbage = <String>[
        '<UpdateVariable>{"op":"replace","path":"/a",',
        '<UpdateVariable><JSONPatch>[{"op":"replace",]</JSONPatch></UpdateVariable>',
        '{{{[[[',
        '[{"op":',
        '<变量更新>\n没写完',
        '{{setvar::}}',
      ];
      for (final content in garbage) {
        expect(
          () => VariableCommandParser.parse(content),
          returnsNormally,
          reason: content,
        );
      }
      expect(VariableCommandParser.parse(''), isA<VariableParseResult>());
      expect(VariableCommandParser.parse('普通正文，没有指令').matched, isFalse);
    });

    test('looksLikeCommandBlock 只做轻量探测', () {
      expect(
        VariableCommandParser.looksLikeCommandBlock(
          '<UpdateVariable>x</UpdateVariable>',
        ),
        isTrue,
      );
      expect(
        VariableCommandParser.looksLikeCommandBlock('<变量更新>x</变量更新>'),
        isTrue,
      );
      expect(
        VariableCommandParser.looksLikeCommandBlock('{{incvar::a}}'),
        isTrue,
      );
      // 裸 JSON 不算 —— 探测不解析，避免把正文 JSON 误判成指令。
      expect(
        VariableCommandParser.looksLikeCommandBlock(
          '[{"op":"replace","path":"/a","value":1}]',
        ),
        isFalse,
      );
      expect(VariableCommandParser.looksLikeCommandBlock('普通文本'), isFalse);
      expect(VariableCommandParser.looksLikeCommandBlock(''), isFalse);
    });

    test('stripFrom 剥掉指令块并收拾多余空行', () {
      const content = '正文第一段。\n\n'
          '<UpdateVariable>\n'
          '<JSONPatch>[{"op":"replace","path":"/a/b","value":1}]</JSONPatch>\n'
          '</UpdateVariable>\n\n'
          '正文第二段。';

      final result = VariableCommandParser.parse(content);
      final stripped = result.stripFrom(content);
      expect(stripped, '正文第一段。\n\n正文第二段。');
      expect(stripped, isNot(contains('UpdateVariable')));
      expect(stripped, isNot(contains('JSONPatch')));
    });
  });

  // ---------------------------------------------------------------------------
  group('VariableDefinition — 展平、序列化、向后兼容', () {
    test('isActive：三者全空才不激活（老卡不带此字段 → 变量功能整体短路）', () {
      expect(VariableDefinition.empty.isActive, isFalse);
      expect(const VariableDefinition().isActive, isFalse);
      expect(const VariableDefinition(init: {'a': 1}).isActive, isTrue);
      expect(const VariableDefinition(rules: '规则').isActive, isTrue);
      expect(const VariableDefinition(instruction: '指令').isActive, isTrue);
    });

    test('flattenInit 把嵌套结构展平成平铺键', () {
      final flat = VariableDefinition.flattenInit(const {
        '角色': {'好感度': 30, '生命值': 82},
        '时间': '白天',
      });
      expect(flat, {
        '角色.好感度': 30,
        '角色.生命值': 82,
        '时间': '白天',
      });
    });

    test('flattenInit 不重复展开已经是平铺键的项', () {
      final flat = VariableDefinition.flattenInit(const {'角色.好感度': 30});
      expect(flat, {'角色.好感度': 30});
    });

    test('flattenInit 对空 Map / 非 Map 输入的处理', () {
      // 空 Map 当标量留着（不是叶子但有键）。
      expect(VariableDefinition.flattenInit(const {'角色': <String, dynamic>{}}), {
        '角色': <String, dynamic>{},
      });
      expect(VariableDefinition.flattenInit('不是 Map'), isEmpty);
      expect(VariableDefinition.flattenInit(null), isEmpty);
    });

    test('fromJson 接受 init / variables / 初始值 三种键名与字符串 version', () {
      final a = VariableDefinition.fromJson(const {
        'version': '2',
        'init': {'a': {'b': 1}},
      });
      expect(a.version, 2);
      expect(a.init, {'a.b': 1});

      final b = VariableDefinition.fromJson(const {
        'variables': {'x': 5},
      });
      expect(b.init, {'x': 5});

      final c = VariableDefinition.fromJson(const {
        '初始值': {'y': 6},
        '规则': '随剧情变化',
      });
      expect(c.init, {'y': 6});
      expect(c.rules, '随剧情变化');
    });

    test('fromJson 缺字段时给安全默认值', () {
      final def = VariableDefinition.fromJson(const {});
      expect(def.version, 1);
      expect(def.init, isEmpty);
      expect(def.rules, '');
      expect(def.isActive, isFalse);
    });

    test('toJson / fromJson 往返一致', () {
      const original = VariableDefinition(
        init: {'角色.好感度': 30},
        rules: '好感度随剧情变化',
      );
      final restored = VariableDefinition.fromJson(original.toJson());
      expect(restored.init, original.init);
      expect(restored.rules, original.rules);
    });

    test('attach 写入 / 覆盖 / 移除，且不改动入参', () {
      const active = VariableDefinition(init: {'a': 1});
      const inactive = VariableDefinition();

      expect(VariableDefinition.attach(null, active), {
        'ykx_variables': active.toJson(),
      });

      // 不激活时把键移除（防止老键残留导致误激活）。
      expect(VariableDefinition.attach(const {'ykx_variables': {'x': 1}}, inactive), isEmpty);

      // 其它 extensions 字段必须原样保留。
      final merged = VariableDefinition.attach(const {'foo': 'bar'}, active);
      expect(merged['foo'], 'bar');
      expect(merged[VariableDefinition.extensionsKey], active.toJson());

      // 入参不被修改 —— 返回的必须是新 Map。
      const input = {'foo': 'bar'};
      final returned = VariableDefinition.attach(input, active);
      expect(returned, isNot(same(input)));
      expect(input, {'foo': 'bar'});
    });

    test('of 永远返回定义（没有时给 empty），fromExtensions 才返回 null', () {
      expect(VariableDefinition.of(null).isActive, isFalse);
      expect(VariableDefinition.of(const {}).isActive, isFalse);
      expect(
        VariableDefinition.of(const {
          'ykx_variables': {'init': {'a': 1}},
        }).isActive,
        isTrue,
      );
      expect(VariableDefinition.fromExtensions(null), isNull);
      expect(VariableDefinition.fromExtensions(const {}), isNull);
    });

    test('fromExtensions 也接受存成 JSON 字符串的写法', () {
      final def = VariableDefinition.fromExtensions(const {
        'ykx_variables': '{"init":{"a":1},"rules":"r"}',
      });
      expect(def, isNotNull);
      expect(def!.init, {'a': 1});
      expect(def.rules, 'r');
      // 不是合法 JSON 时当作「没有定义」，不能抛。
      expect(
        VariableDefinition.fromExtensions(const {'ykx_variables': '不是 JSON'}),
        isNull,
      );
    });

    test('buildInstruction 优先用显式 instruction', () {
      const def = VariableDefinition(
        instruction: '  自定义指令  ',
        init: {'a': 1},
      );
      expect(def.buildInstruction(), '自定义指令');
    });

    test('buildInstruction 未激活时返回空串', () {
      expect(VariableDefinition.empty.buildInstruction(), '');
    });

    test('buildInstruction 带上当前值（模型据此算新值）', () {
      const def = VariableDefinition(
        init: {'角色.好感度': 30},
        rules: '好感度随剧情变化',
      );

      // 会话里还没有值 → 回落到卡上的初始值。
      final fromInit = def.buildInstruction();
      expect(fromInit, contains('角色.好感度（当前：30）'));
      expect(fromInit, contains('更新规则：'));
      expect(fromInit, contains('好感度随剧情变化'));
      expect(fromInit, contains('<UpdateVariable>'));

      // 会话里有值 → 用会话值覆盖初始值。
      final fromSession = def.buildInstruction(
        currentValues: const {'角色.好感度': 55},
      );
      expect(fromSession, contains('角色.好感度（当前：55）'));
      expect(fromSession, isNot(contains('（当前：30）')));
    });

    test('buildInstruction withValues=false 时只给路径，省 token', () {
      const def = VariableDefinition(init: {'角色.好感度': 30});
      final text = def.buildInstruction(withValues: false);
      expect(text, contains('- 角色.好感度'));
      expect(text, isNot(contains('（当前：')));
    });

    test('buildInstruction 对 null 值与超长字符串的显示', () {
      const withNull = VariableDefinition(init: {'x': null});
      expect(withNull.buildInstruction(), contains('（当前：未设置）'));

      final long = List.filled(50, 'x').join();
      final withLong = VariableDefinition(init: {'note': long});
      final text = withLong.buildInstruction();
      expect(text, contains('（当前：${List.filled(40, 'x').join()}…）'));
    });
  });

  // ---------------------------------------------------------------------------
  group('TextDiff — 逐条修复前的 diff 预览', () {
    test('单行替换产生 1 增 1 删，上下文行保留', () {
      final lines = TextDiff.compute('a\nb\nc', 'a\nx\nc');
      expect(lines.map((line) => line.kind).toList(), [
        DiffKind.keep,
        DiffKind.remove,
        DiffKind.add,
        DiffKind.keep,
      ]);
      expect(TextDiff.summarize(lines), '+1 行 / -1 行');
    });

    test('行号：remove 只有 oldLine，add 只有 newLine', () {
      final lines = TextDiff.compute('a\nb\nc', 'a\nx\nc');
      final removed = lines.firstWhere((line) => line.kind == DiffKind.remove);
      final added = lines.firstWhere((line) => line.kind == DiffKind.add);
      expect(removed.text, 'b');
      expect(removed.oldLine, 2);
      expect(removed.newLine, isNull);
      expect(added.text, 'x');
      expect(added.newLine, 2);
      expect(added.oldLine, isNull);
    });

    test('纯新增 / 纯删除', () {
      final appended = TextDiff.compute('a', 'a\nb');
      expect(TextDiff.statsOf(appended).added, 1);
      expect(TextDiff.statsOf(appended).removed, 0);

      final deleted = TextDiff.compute('a\nb', 'a');
      expect(TextDiff.statsOf(deleted).added, 0);
      expect(TextDiff.statsOf(deleted).removed, 1);
    });

    test('完全相同 → 没有变化', () {
      final lines = TextDiff.compute('same\ntext', 'same\ntext');
      expect(lines.every((line) => !line.isChange), isTrue);
      expect(TextDiff.summarize(lines), '没有变化');
      expect(TextDiff.statsOf(lines).isEmpty, isTrue);
    });

    test('collapse 折叠掉离变更点很远的未变化行，用省略号标记', () {
      final lines = <DiffLine>[
        for (var i = 1; i <= 6; i++)
          DiffLine(kind: DiffKind.keep, text: 'k$i'),
        const DiffLine(kind: DiffKind.remove, text: 'goneA'),
        for (var i = 7; i <= 12; i++)
          DiffLine(kind: DiffKind.keep, text: 'k$i'),
        const DiffLine(kind: DiffKind.add, text: 'newB'),
        for (var i = 13; i <= 16; i++)
          DiffLine(kind: DiffKind.keep, text: 'k$i'),
      ];

      final collapsed = TextDiff.collapse(lines, context: 2);
      // 两处变更之间隔了很远的未变化行 → 中间插一个省略号。
      expect(
        collapsed.where((line) => line.text == TextDiff.ellipsisMarker),
        hasLength(1),
      );
      // 变更本身必须保留。
      expect(collapsed.any((line) => line.text == 'goneA'), isTrue);
      expect(collapsed.any((line) => line.text == 'newB'), isTrue);
      // 离变更点太远的未变化行被折叠掉。
      expect(collapsed.any((line) => line.text == 'k9'), isFalse);
      expect(collapsed.any((line) => line.text == 'k10'), isFalse);
    });

    test('collapse 在没有变更时只留头部若干行', () {
      final lines = <DiffLine>[
        for (var i = 1; i <= 10; i++)
          DiffLine(kind: DiffKind.keep, text: 'k$i'),
      ];
      expect(TextDiff.collapse(lines, context: 2), hasLength(4));
    });

    test('超过 maxCells 时退化成「全删 + 全增」，不爆内存', () {
      // 1500 × 1500 = 2,250,000 > maxCells(2,000,000)
      const count = 1500;
      final oldText = List.generate(count, (i) => 'a$i').join('\n');
      final newText = List.generate(count, (i) => 'b$i').join('\n');

      expect(count * count > TextDiff.maxCells, isTrue);

      final lines = TextDiff.compute(oldText, newText);
      expect(lines, hasLength(count * 2));
      // 退化路径里没有 keep —— 全是变更。
      expect(lines.every((line) => line.isChange), isTrue);
      expect(TextDiff.statsOf(lines).added, count);
      expect(TextDiff.statsOf(lines).removed, count);
    });

    test('DiffStats 摘要格式', () {
      expect(const DiffStats(added: 5, removed: 2).toString(), '+5 / -2');
      expect(const DiffStats(added: 0, removed: 0).isEmpty, isTrue);
      expect(const DiffStats(added: 1, removed: 0).isEmpty, isFalse);
    });
  });
}
