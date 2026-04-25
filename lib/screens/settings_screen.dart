import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _githubTokenController = TextEditingController();
  final _customUrlController = TextEditingController();
  int _baudRate = 115200;
  String _eraseOption = 'none';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _githubTokenController.dispose();
    _customUrlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _githubTokenController.text = prefs.getString('githubToken') ?? '';
      _customUrlController.text = prefs.getString('customFirmwareUrl') ?? '';
      _baudRate = prefs.getInt('baudRate') ?? 115200;
      _eraseOption = prefs.getString('eraseOption') ?? 'none';
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('githubToken', _githubTokenController.text.trim());
    await prefs.setString('customFirmwareUrl', _customUrlController.text.trim());
    await prefs.setInt('baudRate', _baudRate);
    await prefs.setString('eraseOption', _eraseOption);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved / 设置已保存')),
    );
  }

  Future<void> _openM5StackFlashMode() async {
    final uri = Uri.parse('https://api.m5stack.com/flash_mode/');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings / 设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Repository / 仓库', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _githubTokenController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'GitHub token (optional) / GitHub 令牌（可选）',
                      helperText: 'Used for private repos or higher rate limits / 用于私有仓库或更高限额',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _customUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Custom firmware URL / 自定义固件 URL',
                      hintText: 'https://example.com/firmware.bin',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Flash options / 刷写选项', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _baudRate,
                    decoration: const InputDecoration(
                      labelText: 'Baud rate / 波特率',
                      border: OutlineInputBorder(),
                    ),
                    items: const [115200, 230400, 460800, 921600]
                        .map((rate) => DropdownMenuItem(value: rate, child: Text('$rate')))
                        .toList(),
                    onChanged: (value) => setState(() => _baudRate = value ?? 115200),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _eraseOption,
                    decoration: const InputDecoration(
                      labelText: 'Erase option / 擦除选项',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('No erase / 不擦除')),
                      DropdownMenuItem(value: 'all', child: Text('Erase all / 全部擦除')),
                      DropdownMenuItem(value: 'sectors', child: Text('Erase sectors / 擦除扇区')),
                    ],
                    onChanged: (value) => setState(() => _eraseOption = value ?? 'none'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Erase options are stored for the flashing workflow; sector erase can be wired to a full esptool erase command later. / 擦除选项已保存，可后续接入完整 esptool 擦除命令。',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Save / 保存'),
          ),
          TextButton.icon(
            onPressed: _openM5StackFlashMode,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open M5Stack Flash Mode / 打开官方刷机目录'),
          ),
        ],
      ),
    );
  }
}
