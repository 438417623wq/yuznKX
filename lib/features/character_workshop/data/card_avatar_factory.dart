import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../character/domain/models/character.dart';

/// 为没有立绘的角色卡生成一张占位头像。
///
/// **为什么需要**：`CharacterExporter.exportAsPng()` 在角色没有 `avatarPath` 时会退回
/// 一张 1×1 的透明 PNG —— 导出的卡在酒馆里就是一片空白，看起来像坏了。
/// 工坊产出的卡天然没有立绘，所以这里画一张带角色名的纯色卡面兜底。
///
/// 用 `dart:ui` 直接绘制 + 编码，不引入新的图片依赖。
class CardAvatarFactory {
  const CardAvatarFactory._();

  /// 占位头像尺寸（竖版，与酒馆角色卡封面的比例接近）。
  static const double canvasWidth = 512;
  static const double canvasHeight = 768;

  static const Size _canvasSize = Size(canvasWidth, canvasHeight);

  /// 确保角色有可用头像，返回头像文件路径。
  ///
  /// 已经有真实头像时原样返回；生成失败时返回 null（调用方应保持原样，不要因此中断导出）。
  static Future<String?> ensureAvatar(Character character) async {
    final existing = character.avatarPath;
    if (existing.isNotEmpty && File(existing).existsSync()) {
      return existing;
    }
    try {
      final bytes = await renderPlaceholder(character.name);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/workshop_avatar_${character.id}.png');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      // 占位图只是锦上添花，失败不该让导出整个挂掉。
      return null;
    }
  }

  /// 把占位头像写进角色卡，返回补好头像的新卡。
  static Future<Character> withPlaceholderAvatar(Character character) async {
    final path = await ensureAvatar(character);
    if (path == null || path == character.avatarPath) {
      return character;
    }
    return character.copyWith(avatarPath: path);
  }

  /// 画一张占位头像并编码成 PNG 字节。
  static Future<Uint8List> renderPlaceholder(String name) async {
    const size = _canvasSize;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & size);

    // 底色：工坊的深蓝渐变。
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, size.height),
          const <Color>[Color(0xFF1E2749), Color(0xFF0F1428)],
        ),
    );

    // 右下角一圈淡淡的强调色，避免纯色板太死。
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.88),
      size.width * 0.5,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.82, size.height * 0.88),
          size.width * 0.5,
          const <Color>[Color(0x338EA1FF), Color(0x008EA1FF)],
        ),
    );

    // 正中的首字。
    final initial = _initialOf(name);
    final painter = TextPainter(
      text: TextSpan(
        text: initial,
        style: const TextStyle(
          color: Color(0xFF8EA1FF),
          fontSize: 200,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        (size.width - painter.width) / 2,
        (size.height - painter.height) / 2,
      ),
    );

    // 底部小字角色名，便于在列表里辨认。
    final trimmed = name.trim();
    if (trimmed.isNotEmpty && trimmed != initial) {
      final namePainter = TextPainter(
        text: TextSpan(
          text: trimmed,
          style: const TextStyle(
            color: Color(0xFFA4B0D3),
            fontSize: 34,
            height: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: size.width * 0.8);
      namePainter.paint(
        canvas,
        Offset((size.width - namePainter.width) / 2, size.height * 0.78),
      );
    }

    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(
        canvasWidth.toInt(),
        canvasHeight.toInt(),
      );
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) {
          throw StateError('PNG 编码失败');
        }
        return data.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  /// 取首个字符。名字为空时用问号兜底。
  static String _initialOf(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return '?';
    }
    // Dart 字符串按 UTF-16 编码，中文与常见符号都落在 BMP，取 1 个 code unit 即可。
    return trimmed.substring(0, 1);
  }
}
