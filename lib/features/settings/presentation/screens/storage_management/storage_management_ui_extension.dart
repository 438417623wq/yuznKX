part of '../storage_management_screen.dart';

extension _StorageManagementUiExtension on _StorageManagementScreenState {
  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E4FB8), Color(0xFF2669C7), Color(0xFF1B3A6D)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66313E76),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '总存储占用',
            style: TextStyle(
              color: Color(0xFFDBE1FF),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _formatSize(_totalBytes),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildMetaChip(
                icon: Icons.category_outlined,
                text: '模块 ${_sections.length}',
              ),
              _buildMetaChip(
                icon: Icons.inventory_2_outlined,
                text: '记录 $_totalRecords',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetaChip({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupActions() {
    return Row(
      children: [
        Expanded(
          child: _buildActionButton(
            icon: Icons.backup_outlined,
            title: '一键备份',
            subtitle: '导出当前数据快照',
            onTap: _isBusy ? null : _exportBackup,
            gradient: const LinearGradient(
              colors: [Color(0xFF4D6BFF), Color(0xFF4C8EFF)],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildActionButton(
            icon: Icons.file_download_outlined,
            title: '导入备份',
            subtitle: '覆盖并恢复全部数据',
            onTap: _isBusy ? null : _importBackup,
            gradient: const LinearGradient(
              colors: [Color(0xFF2D9A6F), Color(0xFF3CB37A)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    required Gradient gradient,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: gradient,
          boxShadow: const [
            BoxShadow(
              color: Color(0x33254ACC),
              blurRadius: 14,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xE6FFFFFF),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required _StorageSectionConfig config,
    required _StorageSectionStat stat,
  }) {
    final ratio = _totalBytes == 0
        ? 0.0
        : (stat.bytes / _totalBytes).clamp(0.0, 1.0).toDouble();

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _stroke),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: config.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: config.color.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Icon(config.icon, color: config.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        config.title,
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        config.subtitle,
                        style: TextStyle(
                          color: _textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (config.clearable)
                  TextButton.icon(
                    onPressed: _isBusy ? null : () => _clearSection(config),
                    style: TextButton.styleFrom(
                      foregroundColor: config.dangerousClear
                          ? Colors.redAccent
                          : const Color(0xFFFFB86B),
                      backgroundColor: config.dangerousClear
                          ? Colors.red.withValues(alpha: 0.13)
                          : const Color(0x33FFB86B),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text(
                      '清理',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '占用 ${_formatSize(stat.bytes)}',
                    style: TextStyle(
                      color: config.color,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '记录 ${stat.records}',
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 7,
                value: ratio,
                backgroundColor: _surfaceSoft,
                valueColor: AlwaysStoppedAnimation<Color>(config.color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
