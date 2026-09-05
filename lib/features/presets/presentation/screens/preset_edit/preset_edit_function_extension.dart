part of '../preset_edit_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _PresetEditFunctionExtension on _PresetEditScreenState {
  Widget _buildFunctionTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      children: [
        _buildFunctionCard(
          'Impersonation Prompt',
          '用于生成“代替用户发言”时的附加指令。',
          _impersonationPromptCtrl,
        ),
        _buildFunctionCard(
          'New Chat Prompt',
          '普通单聊在新会话开始时注入的起始提示。',
          _newChatPromptCtrl,
        ),
        _buildFunctionCard(
          'New Group Chat Prompt',
          '群聊新建时注入的起始提示，对应酒馆的 new_group_chat_prompt。',
          _newGroupChatPromptCtrl,
        ),
        _buildFunctionCard(
          'Continue Nudge',
          '继续生成时追加在被续写消息后的提示，对应 continue_nudge_prompt。',
          _continueNudgeCtrl,
        ),
        _buildFunctionCard(
          'Group Nudge Prompt',
          '群聊每轮尾部的控制提示，对应 group_nudge_prompt。',
          _groupNudgePromptCtrl,
        ),
      ],
    );
  }

  Widget _buildFunctionCard(
    String title,
    String subtitle,
    TextEditingController controller,
  ) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      color: _PresetEditScreenState._surfaceColor,
      shape: _sectionShape(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                color: _PresetEditScreenState._textSecondaryColor,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              maxLines: 4,
              decoration: const InputDecoration(),
            ),
          ],
        ),
      ),
    );
  }
}
