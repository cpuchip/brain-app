import 'package:flutter/material.dart';
import '../services/brain_service.dart';

class ConnectionIndicator extends StatelessWidget {
  final BrainConnectionState connectionState;
  final bool agentOnline;

  const ConnectionIndicator({
    super.key,
    required this.connectionState,
    required this.agentOnline,
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
