import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'dart:io';
import '../../../settings/data/theme_provider.dart';

class ChatBubble extends ConsumerWidget {
  final String content;
  final bool isUser;
  final String name;
  final String? avatarPath;
  final int swipeIndex;
  final int swipeCount;
  final Function(int)? onSwipe;
  final VoidCallback? onRegenerate;
  final Function(String)? onEdit;
  final VoidCallback? onTts;

  const ChatBubble({
    super.key,
    required this.content,
    required this.isUser,
    required this.name,
    this.avatarPath,
    this.swipeIndex = 0,
    this.swipeCount = 1,
    this.onSwipe,
    this.onRegenerate,
    this.onEdit,
    this.onTts,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSettings = ref.watch(themeSettingsProvider);
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      width: double.infinity, // Full width
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center, // Center everything
        children: [
          // Avatar centered above message
          CircleAvatar(
            backgroundImage: (avatarPath != null && avatarPath!.isNotEmpty)
                ? FileImage(File(avatarPath!)) as ImageProvider
                : const NetworkImage('https://via.placeholder.com/150'),
            radius: 25 * themeSettings.fontSizeScale,
          ),
          const SizedBox(height: 8),
          
          // Name and Controls Row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                  fontSize: 14 * themeSettings.fontSizeScale,
                ),
              ),
              if (swipeCount > 1) ...[
                const SizedBox(width: 8),
                _buildSwipeControls(),
              ],
            ],
          ),
          
          const SizedBox(height: 8),

          // Message Content - Stretched Full Screen Width with padding
          GestureDetector(
            onLongPress: () => _showContextMenu(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: (isUser ? themeSettings.userBubbleColor : themeSettings.aiBubbleColor).withOpacity(0.8), // Slightly transparent background
                // No border radius needed for full stretch look, or maybe small one?
                // Let's keep small vertical spacing but full width feel
              ),
              child: MarkdownBody(
                data: content,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(color: Colors.white, fontSize: 16 * themeSettings.fontSizeScale),
                  code: TextStyle(
                    color: Colors.pinkAccent,
                    backgroundColor: Colors.black26, 
                    fontFamily: 'monospace',
                    fontSize: 14 * themeSettings.fontSizeScale
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  blockquote: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 16 * themeSettings.fontSizeScale),
                  blockquoteDecoration: const BoxDecoration(
                     color: Colors.transparent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwipeControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: swipeIndex > 0 ? () => onSwipe?.call(swipeIndex - 1) : null,
            child: Icon(Icons.chevron_left, size: 16, color: swipeIndex > 0 ? Colors.white70 : Colors.white24),
          ),
          Text(
            ' ${swipeIndex + 1}/$swipeCount ',
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
          InkWell(
            onTap: swipeIndex < swipeCount - 1 ? () => onSwipe?.call(swipeIndex + 1) : null,
            child: Icon(Icons.chevron_right, size: 16, color: swipeIndex < swipeCount - 1 ? Colors.white70 : Colors.white24),
          ),
        ],
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a1b26),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.copy, color: Colors.white),
            title: const Text('复制', style: TextStyle(color: Colors.white)),
            onTap: () {
              Clipboard.setData(ClipboardData(text: content));
              Navigator.pop(ctx);
            },
          ),
          if (onEdit != null)
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.white),
              title: const Text('编辑', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showEditDialog(context);
              },
            ),
          if (!isUser && onRegenerate != null)
            ListTile(
              leading: const Icon(Icons.refresh, color: Colors.white),
              title: const Text('重新生成', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                onRegenerate?.call();
              },
            ),
          if (!isUser && onTts != null)
            ListTile(
              leading: const Icon(Icons.volume_up, color: Colors.white),
              title: const Text('朗读', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                onTts?.call();
              },
            ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final controller = TextEditingController(text: content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF24283b),
        title: const Text('编辑消息', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          maxLines: 5,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              onEdit?.call(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
