import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/dragon_theme.dart';

class SshTerminalScreen extends StatefulWidget {
  const SshTerminalScreen({super.key});

  @override
  State<SshTerminalScreen> createState() => _SshTerminalScreenState();
}

class _SshTerminalScreenState extends State<SshTerminalScreen> {
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '22');
  final _userCtrl = TextEditingController(text: 'root');
  final _passCtrl = TextEditingController();
  final _cmdCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  SSHClient? _client;
  SSHSession? _shell;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;

  bool _connecting = false;
  bool _connected = false;
  String _output = 'VPNSOPR SSH Terminal (Termius Mode)\nIP و رمز سرور را وارد کرده و Connect بزنید.\n';

  static final _ansiRegex = RegExp(r'\x1B\[[0-9;?]*[A-Za-z]|\x1B\][^\x07]*\x07');

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hostCtrl.text = prefs.getString('ssh_last_host') ?? '';
      _portCtrl.text = prefs.getString('ssh_last_port') ?? '22';
      _userCtrl.text = prefs.getString('ssh_last_user') ?? 'root';
      _passCtrl.text = prefs.getString('ssh_last_pass') ?? '';
    });
  }

  Future<void> _saveCreds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ssh_last_host', _hostCtrl.text.trim());
    await prefs.setString('ssh_last_port', _portCtrl.text.trim());
    await prefs.setString('ssh_last_user', _userCtrl.text.trim());
    await prefs.setString('ssh_last_pass', _passCtrl.text);
  }

  void _appendOutput(String text) {
    final cleaned = text.replaceAll(_ansiRegex, '').replaceAll('\r', '');
    if (!mounted) return;
    setState(() {
      _output += cleaned;
      if (_output.length > 25000) {
        _output = _output.substring(_output.length - 20000);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _connect() async {
    if (_hostCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('IP و پسورد SSH را وارد کنید')),
      );
      return;
    }
    await _saveCreds();
    setState(() {
      _connecting = true;
      _output += '\n>>> Connecting to ${_userCtrl.text.trim()}@${_hostCtrl.text.trim()}:${_portCtrl.text.trim()}...\n';
    });

    try {
      final socket = await SSHSocket.connect(
        _hostCtrl.text.trim(),
        int.tryParse(_portCtrl.text.trim()) ?? 22,
        timeout: const Duration(seconds: 15),
      );
      final client = SSHClient(
        socket,
        username: _userCtrl.text.trim().isEmpty ? 'root' : _userCtrl.text.trim(),
        onPasswordRequest: () => _passCtrl.text,
        onUserInfoRequest: (req) => req.prompts.map((_) => _passCtrl.text).toList(),
      );
      await client.authenticated;
      final shell = await client.shell(
        pty: const SSHPtyConfig(width: 80, height: 32),
      );

      _stdoutSub = shell.stdout.listen((data) {
        _appendOutput(utf8.decode(data, allowMalformed: true));
      });
      _stderrSub = shell.stderr.listen((data) {
        _appendOutput(utf8.decode(data, allowMalformed: true));
      });
      unawaited(shell.done.then((_) {
        if (mounted) {
          _appendOutput('\n[Session closed]\n');
          _disconnect();
        }
      }));

      setState(() {
        _client = client;
        _shell = shell;
        _connected = true;
        _connecting = false;
      });
    } catch (e) {
      setState(() {
        _connecting = false;
        _output += '\n[SSH Error]: $e\n';
      });
    }
  }

  void _disconnect() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _shell?.close();
    _client?.close();
    _stdoutSub = null;
    _stderrSub = null;
    _shell = null;
    _client = null;
    if (mounted) setState(() => _connected = false);
  }

  void _sendCommand([String? override]) {
    if (_shell == null) return;
    final cmd = override ?? '${_cmdCtrl.text}\n';
    _shell!.write(utf8.encode(cmd));
    if (override == null) _cmdCtrl.clear();
  }

  @override
  void dispose() {
    _disconnect();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _cmdCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SSH Terminal (Termius)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          if (_connected)
            TextButton.icon(
              onPressed: _disconnect,
              icon: const Icon(Icons.link_off_rounded, color: DragonColors.crimsonRed),
              label: const Text('قطع', style: TextStyle(color: DragonColors.crimsonRed)),
            ),
        ],
      ),
      body: Column(
        children: [
          if (!_connected)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _hostCtrl,
                              decoration: const InputDecoration(
                                labelText: 'IP سرور',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _portCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Port',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _userCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Username',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _passCtrl,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Password',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DragonColors.electricBlue,
                            foregroundColor: Colors.black,
                          ),
                          icon: _connecting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.black),
                                )
                              : const Icon(Icons.terminal_rounded),
                          label: Text(_connecting ? 'در حال اتصال...' : 'اتصال به ترمینال سرور'),
                          onPressed: _connecting ? null : _connect,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF05070B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: DragonColors.electricBlue.withOpacity(0.3)),
              ),
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                child: SelectableText(
                  _output,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Color(0xFF00FF9D),
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ),
          if (_connected) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  ActionChip(
                    label: const Text('Ctrl+C', style: TextStyle(fontSize: 11)),
                    onPressed: () => _sendCommand('\x03'),
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    label: const Text('Enter', style: TextStyle(fontSize: 11)),
                    onPressed: () => _sendCommand('\n'),
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    label: const Text('Paste', style: TextStyle(fontSize: 11)),
                    onPressed: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null) {
                        _cmdCtrl.text += data!.text!;
                      }
                    },
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    label: const Text('Clear', style: TextStyle(fontSize: 11)),
                    onPressed: () => setState(() => _output = ''),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cmdCtrl,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'دستور لینوکس را وارد کنید...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _sendCommand(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                        backgroundColor: DragonColors.electricBlue,
                        foregroundColor: Colors.black),
                    icon: const Icon(Icons.send_rounded),
                    onPressed: _sendCommand,
                  ),
                ],
              ),
            ),
          ] else
            const SizedBox(height: 10),
        ],
      ),
    );
  }
}
