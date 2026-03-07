import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  final String initialUrl;
  final String initialToken;
  final String initialBrainUrl;
  final Future<void> Function(String url, String token, String brainUrl) onSaved;
  final bool firstRun;

  const SettingsScreen({
    super.key,
    required this.initialUrl,
    required this.initialToken,
    this.initialBrainUrl = '',
    required this.onSaved,
    this.firstRun = false,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlController;
  late TextEditingController _tokenController;
  late TextEditingController _brainUrlController;
  bool _saving = false;
  bool _obscureToken = true;
  bool _autoSend = true;
  bool _drivingMode = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl);
    _tokenController = TextEditingController(text: widget.initialToken);
    _brainUrlController = TextEditingController(text: widget.initialBrainUrl);
    _loadSttPrefs();
  }

  Future<void> _loadSttPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoSend = prefs.getBool('stt_auto_send') ?? true;
      _drivingMode = prefs.getBool('stt_driving_mode') ?? false;
    });
  }

  Future<void> _saveSttPref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    _brainUrlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _urlController.text.trim();
    final token = _tokenController.text.trim();
    final brainUrl = _brainUrlController.text.trim();

    if (url.isEmpty || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL and token are required')),
      );
      return;
    }

    setState(() => _saving = true);
    await widget.onSaved(url, token, brainUrl);
    setState(() => _saving = false);

    if (mounted && !widget.firstRun) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved — restart app to reconnect'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.firstRun ? 'Welcome to Brain' : 'Settings'),
        automaticallyImplyLeading: !widget.firstRun,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.firstRun) ...[
              Icon(
                Icons.psychology,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Connect to your brain',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your ibeco.me server URL and API token to get started.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 32),
            ],
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'https://ibeco.me',
                prefixIcon: Icon(Icons.link),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tokenController,
              decoration: InputDecoration(
                labelText: 'API Token',
                hintText: 'bec_...',
                prefixIcon: const Icon(Icons.key),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureToken ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _obscureToken = !_obscureToken),
                ),
              ),
              obscureText: _obscureToken,
              autocorrect: false,
            ),
            const SizedBox(height: 24),
            // Brain URL (optional) — direct connection to local brain.exe
            Text(
              'Local Brain (optional)',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Connect directly to brain.exe on your network for real-time data and full management.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _brainUrlController,
              decoration: const InputDecoration(
                labelText: 'Brain URL',
                hintText: 'http://192.168.1.x:8445',
                prefixIcon: Icon(Icons.psychology),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: 24),
            // Voice settings
            Text(
              'Voice Settings',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              title: const Text('Auto-send on speech'),
              subtitle: const Text('Automatically send when you stop talking'),
              value: _autoSend,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) {
                setState(() => _autoSend = v);
                _saveSttPref('stt_auto_send', v);
              },
            ),
            SwitchListTile(
              title: const Text('Driving mode'),
              subtitle: const Text('Keep mic hot after sending, always read back results'),
              value: _drivingMode,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) {
                setState(() => _drivingMode = v);
                _saveSttPref('stt_driving_mode', v);
                if (v && !_autoSend) {
                  setState(() => _autoSend = true);
                  _saveSttPref('stt_auto_send', true);
                }
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(widget.firstRun ? 'Connect' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
