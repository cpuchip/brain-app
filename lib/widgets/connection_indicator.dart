import 'package:flutter/material.dart';
import '../services/brain_service.dart';

class ConnectionIndicator extends StatelessWidget {
  final BrainConnectionState connectionState;
  final bool agentOnline;
  final int queueCount;

  const ConnectionIndicator({
    super.key,
    required this.connectionState,
    required this.agentOnline,
    this.queueCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final (color, label, icon) = _stateInfo(context);

    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Agent status dot
            if (connectionState == BrainConnectionState.connected) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: agentOnline ? Colors.green : Colors.orange,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
            ],
            // Connection icon
            Icon(icon, size: 18, color: color),
            // Queue count badge
            if (queueCount > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.orange.shade700,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$queueCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  (Color, String, IconData) _stateInfo(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return switch (connectionState) {
      BrainConnectionState.disconnected => (
          colorScheme.error,
          'Disconnected',
          Icons.cloud_off,
        ),
      BrainConnectionState.connecting => (
          Colors.orange,
          'Connecting…',
          Icons.cloud_sync,
        ),
      BrainConnectionState.authenticating => (
          Colors.orange,
          'Authenticating…',
          Icons.cloud_sync,
        ),
      BrainConnectionState.connected => (
          colorScheme.primary,
          agentOnline ? 'Connected — agent online' : 'Connected — agent offline',
          agentOnline ? Icons.cloud_done : Icons.cloud_queue,
        ),
    };
  }
}
