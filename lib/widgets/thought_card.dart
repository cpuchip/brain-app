import 'package:flutter/material.dart';
import '../services/brain_service.dart';
import 'package:intl/intl.dart';

class ThoughtCard extends StatelessWidget {
  final PendingThought thought;

  const ThoughtCard({super.key, required this.thought});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final timeFormat = DateFormat('h:mm a');
    final result = thought.result;

    return Card(
      elevation: 0,
      color: result != null
          ? colorScheme.surfaceContainerLow
          : colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The thought text
            Text(
              thought.text,
              style: theme.textTheme.bodyMedium,
            ),

            const SizedBox(height: 8),

            // Result or pending state
            if (result != null) _buildResult(theme, colorScheme, result)
            else if (thought.error != null)
              _buildError(theme, colorScheme)
            else
              _buildPending(theme, colorScheme),

            // Timestamp
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                timeFormat.format(thought.timestamp.toLocal()),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(
      ThemeData theme, ColorScheme colorScheme, BrainResult result) {
    final categoryColor = _categoryColor(result.category, colorScheme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category badge + confidence + title
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: categoryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                result.category,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: categoryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${(result.confidence * 100).toInt()}%',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
            if (result.needsReview)
              Icon(Icons.flag, size: 14, color: Colors.orange.shade600),
          ],
        ),

        // Title
        if (result.title.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            result.title,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],

        // Tags
        if (result.tags.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: result.tags.map((tag) {
              return Chip(
                label: Text(tag),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                labelStyle: theme.textTheme.labelSmall,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildPending(ThemeData theme, ColorScheme colorScheme) {
    return Row(
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Classifying…',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.outline,
          ),
        ),
      ],
    );
  }

  Widget _buildError(ThemeData theme, ColorScheme colorScheme) {
    return Row(
      children: [
        Icon(Icons.error_outline, size: 14, color: colorScheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            thought.error!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }

  Color _categoryColor(String category, ColorScheme colorScheme) {
    return switch (category) {
      'insight' => Colors.amber.shade700,
      'question' => Colors.blue.shade600,
      'action' => Colors.green.shade600,
      'reflection' => Colors.purple.shade500,
      'connection' => Colors.teal.shade600,
      'inbox' => colorScheme.outline,
      _ => colorScheme.outline,
    };
  }
}
