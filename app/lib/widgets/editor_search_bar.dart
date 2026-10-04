import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

class EditorSearchBar extends StatefulWidget {
  final CodeController controller;
  final VoidCallback onClose;

  const EditorSearchBar({
    required this.controller,
    required this.onClose,
    Key? key,
  }) : super(key: key);

  @override
  State<EditorSearchBar> createState() => _EditorSearchBarState();
}

class _EditorSearchBarState extends State<EditorSearchBar> {
  final _findCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();
  List<int> _matches = [];
  int _current = -1;
  bool _showReplace = false;

  @override
  void initState() {
    super.initState();
    _findCtrl.addListener(_updateMatches);
  }

  @override
  void dispose() {
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    super.dispose();
  }

  void _updateMatches() {
    final query = _findCtrl.text;
    if (query.isEmpty) {
      setState(() {
        _matches = [];
        _current = -1;
      });
      return;
    }
    final text = widget.controller.text;
    final matches = <int>[];
    var idx = 0;
    while (true) {
      final found = text.indexOf(query, idx);
      if (found == -1) break;
      matches.add(found);
      idx = found + query.length;
    }
    setState(() {
      _matches = matches;
      _current = matches.isEmpty ? -1 : 0;
    });
    if (matches.isNotEmpty) _selectMatch(0);
  }

  void _selectMatch(int i) {
    final query = _findCtrl.text;
    final start = _matches[i];
    widget.controller.selection = TextSelection(
      baseOffset: start,
      extentOffset: start + query.length,
    );
    setState(() => _current = i);
  }

  void _next() {
    if (_matches.isEmpty) return;
    _selectMatch((_current + 1) % _matches.length);
  }

  void _prev() {
    if (_matches.isEmpty) return;
    _selectMatch((_current - 1 + _matches.length) % _matches.length);
  }

  void _replaceCurrent() {
    if (_current < 0 || _matches.isEmpty) return;
    final query = _findCtrl.text;
    final replacement = _replaceCtrl.text;
    final text = widget.controller.text;
    final start = _matches[_current];
    final newText = text.replaceRange(start, start + query.length, replacement);
    widget.controller.text = newText;
    widget.controller.selection = TextSelection.collapsed(
      offset: start + replacement.length,
    );
    _updateMatches();
  }

  void _replaceAll() {
    final query = _findCtrl.text;
    if (query.isEmpty) return;
    final newText = widget.controller.text.replaceAll(query, _replaceCtrl.text);
    widget.controller.text = newText;
    _updateMatches();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _findCtrl,
                      autofocus: true,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Tìm...',
                        prefixIcon: const Icon(Icons.search, size: 16),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        suffixText: _matches.isEmpty
                            ? null
                            : '${_current + 1}/${_matches.length}',
                      ),
                      onSubmitted: (_) => _next(),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                  tooltip: 'Trước',
                  visualDensity: VisualDensity.compact,
                  onPressed: _matches.isEmpty ? null : _prev,
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                  tooltip: 'Sau',
                  visualDensity: VisualDensity.compact,
                  onPressed: _matches.isEmpty ? null : _next,
                ),
                IconButton(
                  icon: Icon(
                      _showReplace ? Icons.expand_less : Icons.expand_more,
                      size: 20),
                  tooltip: _showReplace ? 'Ẩn thay thế' : 'Hiện thay thế',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _showReplace = !_showReplace),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Đóng',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onClose,
                ),
              ],
            ),
            if (_showReplace) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _replaceCtrl,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Thay bằng...',
                          prefixIcon: Icon(Icons.find_replace, size: 16),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _current < 0 ? null : _replaceCurrent,
                    child: const Text('Thay'),
                  ),
                  TextButton(
                    onPressed: _matches.isEmpty ? null : _replaceAll,
                    child: const Text('Tất cả'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}