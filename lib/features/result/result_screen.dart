import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/snip_result.dart';

class ResultScreen extends StatefulWidget {
  final SnipResult result;
  const ResultScreen({super.key, required this.result});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late final TextEditingController _controller;
  bool _justCopied = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.result.text);
    // Keep the live word/character counts in sync as the user edits.
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _controller.text));
    if (!mounted) return;
    setState(() => _justCopied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _justCopied = false);
  }

  Future<void> _share() =>
      SharePlus.instance.share(ShareParams(text: _controller.text));

  int get _charCount => _controller.text.characters.length;

  int get _wordCount {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isEmpty = _controller.text.trim().isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Extracted text')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Recognised text',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  _CountChip(label: '$_wordCount words'),
                  const SizedBox(width: 8),
                  _CountChip(label: '$_charCount chars'),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Stack(
                    children: [
                      TextField(
                        controller: _controller,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isCollapsed: true,
                        ),
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
                      ),
                      if (isEmpty)
                        IgnorePointer(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Spacer(),
                              Icon(Icons.text_fields_rounded,
                                  size: 44, color: scheme.outline),
                              const SizedBox(height: 12),
                              Text(
                                'No text was found',
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Try snipping a tighter region with clearer text.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: scheme.outline),
                              ),
                              const Spacer(flex: 2),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(_justCopied
                      ? Icons.check_rounded
                      : Icons.content_copy_outlined),
                  label: Text(_justCopied ? 'Copied' : 'Copy'),
                  onPressed: isEmpty ? null : _copy,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Share'),
                  onPressed: isEmpty ? null : _share,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  const _CountChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
