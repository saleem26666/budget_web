import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../utils/app_lock_biometric.dart';
import '../utils/app_lock_prefs.dart';

/// Full-screen unlock when app lock PIN is enabled.
class AppLockGate extends StatefulWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  bool _loading = true;
  bool _locked = false;
  String _entered = '';
  bool _error = false;
  bool _checking = false;
  bool _bioAvailable = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final set = await AppLockPrefs.isPinSet();
    var bio = false;
    if (set) {
      bio = await AppLockBiometric.canUse();
      if (bio) {
        final ok = await AppLockBiometric.authenticate();
        if (ok && mounted) {
          setState(() {
            _loading = false;
            _locked = false;
            _bioAvailable = true;
          });
          return;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _locked = set;
      _bioAvailable = bio;
    });
  }

  Future<void> _onDigit(String d) async {
    if (_checking || _entered.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entered += d;
      _error = false;
    });
    if (_entered.length == 4) await _verify();
  }

  Future<void> _verify() async {
    setState(() => _checking = true);
    final ok = await AppLockPrefs.verify(_entered);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _locked = false;
        _checking = false;
        _entered = '';
      });
    } else {
      setState(() {
        _error = true;
        _entered = '';
        _checking = false;
      });
    }
  }

  Future<void> _tryBio() async {
    setState(() => _checking = true);
    final ok = await AppLockBiometric.authenticate();
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (ok) _locked = false;
    });
  }

  void _backspace() {
    if (_entered.isEmpty) return;
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _error = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_locked) return widget.child;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline,
                      size: 48, color: AppTheme.primary),
                  const SizedBox(height: 16),
                  const Text(
                    'Budget Web locked',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error ? 'Wrong PIN — try again' : 'Enter your PIN',
                    style: TextStyle(
                      color: _error ? AppTheme.expense : AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (i) {
                      final filled = i < _entered.length;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: filled
                              ? AppTheme.primary
                              : const Color(0xFFCBD5E1),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 28),
                  if (_bioAvailable) ...[
                    FilledButton.tonalIcon(
                      onPressed: _checking ? null : _tryBio,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Use fingerprint / Face ID'),
                    ),
                    const SizedBox(height: 20),
                  ],
                  _pad(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pad() {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];
    return Column(
      children: keys
          .map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: row.map((k) {
                  if (k.isEmpty) return const Expanded(child: SizedBox());
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: AspectRatio(
                        aspectRatio: 1.4,
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: _checking
                                ? null
                                : () {
                                    if (k == '⌫') {
                                      _backspace();
                                    } else {
                                      _onDigit(k);
                                    }
                                  },
                            child: Center(
                              child: k == '⌫'
                                  ? const Icon(Icons.backspace_outlined)
                                  : Text(
                                      k,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          )
          .toList(),
    );
  }
}
