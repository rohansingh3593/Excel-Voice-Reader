import 'package:flutter/material.dart';

import '../services/excel_service.dart';
import '../services/tts_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ExcelService _excelService = const ExcelService();
  final TtsService _ttsService = TtsService();

  ExcelWorkbookData? _workbook;
  String? _selectedSheet;
  String? _selectedKeyword;
  String? _selectedTopic;
  ExcelRowData? _selectedRow;
  int _topicPlaybackRequestId = 0;
  List<ExcelRowData> _displayedSheetRows = const <ExcelRowData>[];
  String? _loadedSheet;
  AccentOption _selectedAccent = TtsService.accents.first;
  SpeechSpeed _selectedSpeed = SpeechSpeed.normal;
  double _pitch = 1.0;
  bool _isLoading = false;
  String? _errorMessage;

  List<ExcelRowData> get _sheetRows {
    final workbook = _workbook;
    final selectedSheet = _selectedSheet;
    if (workbook == null || selectedSheet == null) {
      return const [];
    }

    if (_loadedSheet != selectedSheet) {
      return const <ExcelRowData>[];
    }

    return _displayedSheetRows;
  }

  List<ExcelRowData> get _selectedTopicRows {
    final sheetRows = _sheetRows;
    if (_selectedKeyword == null || _selectedTopic == null) {
      return const [];
    }

    return sheetRows.where((row) {
      return row.keyword == _selectedKeyword && row.topic == _selectedTopic;
    }).toList(growable: false);
  }

  String? get _selectedSheetError {
    final workbook = _workbook;
    final selectedSheet = _selectedSheet;
    if (workbook == null || selectedSheet == null) {
      return null;
    }

    return workbook.sheetErrors[selectedSheet];
  }

  @override
  void initState() {
    super.initState();
    _ttsService.playbackError.addListener(_showTtsPlaybackError);
  }

  @override
  void dispose() {
    _ttsService.playbackError.removeListener(_showTtsPlaybackError);
    _ttsService.dispose();
    super.dispose();
  }

  void _showTtsPlaybackError() {
    final message = _ttsService.playbackError.value;
    if (message == null || !mounted) {
      return;
    }

    _showSnackBar(message);
    _ttsService.clearPlaybackError();
  }

  Future<void> _selectExcelFile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final workbook = await _excelService.pickAndReadWorkbook();
      if (workbook == null) {
        return;
      }

      final initialSheet =
          workbook.sheetNames.isEmpty ? null : workbook.sheetNames.first;
      setState(() {
        _workbook = workbook;
        _clearSelectedSheetState(initialSheet);
      });
      _reloadSelectedSheetRows(initialSheet);
    } on FormatException catch (error) {
      setState(() {
        _workbook = null;
        _clearSelectedSheetState(null);
        _errorMessage = error.message;
      });
    } catch (error) {
      final message = error.toString().isNotEmpty
          ? error.toString()
          : 'Unable to open this Excel file. Please choose a valid .xlsx or .xlsm file.';
      setState(() {
        _workbook = null;
        _clearSelectedSheetState(null);
        _errorMessage = message;
      });
      debugPrint('Excel load error: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _clearSelectedSheetState(String? sheetName) {
    _topicPlaybackRequestId++;
    _selectedSheet = sheetName;
    _selectedKeyword = null;
    _selectedTopic = null;
    _selectedRow = null;
    _displayedSheetRows = const <ExcelRowData>[];
    _loadedSheet = null;
  }

  void _selectSheet(String? sheetName) {
    setState(() {
      _clearSelectedSheetState(sheetName);
    });
    _reloadSelectedSheetRows(sheetName);
  }

  void _reloadSelectedSheetRows(String? sheetName) {
    final workbook = _workbook;
    if (workbook == null || sheetName == null) {
      return;
    }

    final rows = List<ExcelRowData>.unmodifiable(
      workbook.rowsBySheet[sheetName] ?? const <ExcelRowData>[],
    );

    if (!mounted || _selectedSheet != sheetName) {
      return;
    }

    setState(() {
      _displayedSheetRows = rows;
      _loadedSheet = sheetName;
    });
  }

  void _selectKeyword(String keyword) {
    setState(() {
      _topicPlaybackRequestId++;
      _selectedKeyword = keyword;
      _selectedTopic = null;
      _selectedRow = null;
    });
  }

  Future<void> _selectTopic(String topic) async {
    final playbackRequestId = ++_topicPlaybackRequestId;
    debugPrint(
        'DEBUG: _selectTopic called with topic=$topic, _selectedKeyword=$_selectedKeyword');

    await _ttsService.stop();
    _ttsService.clearQueue();

    if (!mounted || playbackRequestId != _topicPlaybackRequestId) {
      return;
    }

    final rows = _sheetRows
        .where((row) => row.keyword == _selectedKeyword && row.topic == topic)
        .toList(growable: false);
    debugPrint('DEBUG: Found ${rows.length} rows for this topic');
    setState(() {
      _selectedTopic = topic;
      _selectedRow = rows.isNotEmpty ? rows.first : null;
    });

    if (rows.isEmpty) {
      _showSnackBar('No content rows found for this topic.');
      debugPrint('DEBUG: No rows found');
      return;
    }

    final text =
        rows.map((row) => _buildReadableContent(row.content)).join('\n\n');
    debugPrint('DEBUG: Prepared text for speech (length=${text.length})');

    if (text.trim().isEmpty) {
      _showSnackBar('Selected topic has no readable content.');
      debugPrint('DEBUG: Text is empty after cleaning');
      return;
    }

    if (!mounted || playbackRequestId != _topicPlaybackRequestId) {
      return;
    }

    debugPrint('DEBUG: Calling _ttsService.speak()');
    await _ttsService.speak(
      text: text,
      accent: _selectedAccent,
      speed: _selectedSpeed,
      pitch: _pitch,
    );
    debugPrint('DEBUG: speak() returned');
  }

  Future<void> _readRow(ExcelRowData row) async {
    setState(() {
      _selectedRow = row;
    });

    final text = _buildReadableContent(row.content);
    debugPrint('DEBUG: _readRow - prepared text (length=${text.length})');
    if (text.trim().isEmpty) {
      _showSnackBar('This row has no readable content to play.');
      return;
    }

    debugPrint('DEBUG: _readRow - calling speak()');
    await _ttsService.speak(
      text: text,
      accent: _selectedAccent,
      speed: _selectedSpeed,
      pitch: _pitch,
    );
  }

  Future<void> _playSelectedRow() async {
    final row = _selectedRow;
    if (row == null) {
      _showSnackBar('Select a row or tap Read Aloud first.');
      return;
    }

    await _readRow(row);
  }

  Future<void> _pauseSpeech() async {
    await _ttsService.pause();
  }

  Future<void> _stopSpeech() async {
    await _ttsService.stop();
  }

  Future<void> _resumeSpeech() async {
    await _ttsService.resume();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Excel Voice Reader'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _buildHeader(theme),
            const SizedBox(height: 16),
            _buildFileControls(),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _buildErrorBanner(_errorMessage!),
            ],
            const SizedBox(height: 14),
            _buildDropdowns(),
            const SizedBox(height: 14),
            _buildVoiceControls(),
            const SizedBox(height: 18),
            _buildContentSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF0F766E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Excel Voice Reader',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Upload an .xlsx file, select a sheet, and listen to the content column in your preferred English accent.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color.fromRGBO(255, 255, 255, 0.92),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileControls() {
    final fileName = _workbook?.fileName;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: _isLoading ? null : _selectExcelFile,
              icon: _isLoading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_rounded),
              label: Text(
                  _isLoading ? 'Loading Excel File...' : 'Select Excel File'),
            ),
            if (fileName != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.description_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF7F1D1D)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdowns() {
    final workbook = _workbook;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedSheet,
              decoration: const InputDecoration(
                labelText: 'Sheet',
                prefixIcon: Icon(Icons.table_chart_outlined),
                border: OutlineInputBorder(),
              ),
              hint: const Text('Select a sheet'),
              items: workbook?.sheetNames
                      .map(
                        (sheetName) => DropdownMenuItem(
                          value: sheetName,
                          child: Text(sheetName),
                        ),
                      )
                      .toList() ??
                  const [],
              onChanged: workbook == null ? null : _selectSheet,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<AccentOption>(
              initialValue: _selectedAccent,
              decoration: const InputDecoration(
                labelText: 'Accent / Language',
                prefixIcon: Icon(Icons.record_voice_over_outlined),
                border: OutlineInputBorder(),
              ),
              items: TtsService.accents
                  .map(
                    (accent) => DropdownMenuItem(
                      value: accent,
                      child: Text(accent.label),
                    ),
                  )
                  .toList(),
              onChanged: (accent) {
                if (accent == null) {
                  return;
                }

                setState(() {
                  _selectedAccent = accent;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceControls() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Voice Controls',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                ValueListenableBuilder<int>(
                  valueListenable: _ttsService.queueLength,
                  builder: (context, len, child) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: len > 0
                          ? const Color(0xFFEEF2FF)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Text('Queue: $len',
                        style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _selectedRow == null ? null : _playSelectedRow,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _pauseSpeech,
                  icon: const Icon(Icons.pause_rounded),
                  label: const Text('Pause'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _resumeSpeech,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Resume'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _stopSpeech,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Stop'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _ttsService.skip(),
                  icon: const Icon(Icons.skip_next_rounded),
                  label: const Text('Next'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SegmentedButton<SpeechSpeed>(
              segments: SpeechSpeed.values
                  .map(
                    (speed) => ButtonSegment(
                      value: speed,
                      label: Text(speed.label),
                    ),
                  )
                  .toList(),
              selected: {_selectedSpeed},
              onSelectionChanged: (selection) {
                setState(() {
                  _selectedSpeed = selection.first;
                });
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.tune_rounded),
                const SizedBox(width: 10),
                const Text('Pitch'),
                Expanded(
                  child: Slider(
                    value: _pitch,
                    min: 0.5,
                    max: 2.0,
                    divisions: 6,
                    label: _pitch.toStringAsFixed(1),
                    onChanged: (value) {
                      setState(() {
                        _pitch = value;
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentSection() {
    final workbook = _workbook;
    if (workbook == null) {
      return _buildEmptyState(
        icon: Icons.upload_file_outlined,
        title: 'No Excel file selected',
        message:
            'Tap Select Excel File to upload an .xlsx workbook from your phone storage.',
      );
    }

    if (workbook.sheetNames.isEmpty) {
      return _buildEmptyState(
        icon: Icons.table_chart_outlined,
        title: 'No sheets found',
        message:
            'This workbook opened successfully, but it does not contain any sheets to display.',
      );
    }

    final sheetError = _selectedSheetError;
    if (sheetError != null) {
      return _buildEmptyState(
        icon: Icons.error_outline,
        title: 'Required columns missing',
        message: sheetError,
      );
    }

    final rows = _sheetRows;
    if (rows.isEmpty) {
      return _buildEmptyState(
        icon: Icons.table_rows_outlined,
        title: 'No rows to show',
        message:
            'This sheet has the required columns but no readable content rows.',
      );
    }

    final keywords = rows
        .map((row) => row.keyword)
        .where((keyword) => keyword.isNotEmpty)
        .toSet()
        .toList();
    keywords.sort();

    if (_selectedKeyword == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Keywords (${keywords.length})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          ...keywords.map((keyword) => Card(
                child: ListTile(
                  title: Text(keyword),
                  trailing:
                      const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                  onTap: () => _selectKeyword(keyword),
                ),
              )),
        ],
      );
    }

    final topics = rows
        .where((row) => row.keyword == _selectedKeyword)
        .map((row) => row.topic)
        .where((topic) => topic.isNotEmpty)
        .toSet()
        .toList();
    topics.sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () {
                setState(() {
                  _selectedKeyword = null;
                  _selectedTopic = null;
                  _selectedRow = null;
                });
              },
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Topics for "$_selectedKeyword" (${topics.length})',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...topics.map((topic) {
          final isSelected = topic == _selectedTopic;
          return Card(
            color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
            child: ListTile(
              title: Text(topic),
              subtitle:
                  isSelected ? const Text('Tap again to replay content') : null,
              trailing: const Icon(Icons.play_arrow_rounded),
              onTap: () => _selectTopic(topic),
            ),
          );
        }),
        if (_selectedTopic != null && _selectedTopicRows.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            'Content (${_selectedTopicRows.length})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          ..._selectedTopicRows.map(_buildContentCard),
        ],
      ],
    );
  }

  Widget _buildContentCard(ExcelRowData row) {
    final isSelected = identical(row, _selectedRow);
    final cleanedContent = _cleanContent(row.content);
    final displayContent =
        cleanedContent.isEmpty ? row.content.trim() : cleanedContent;

    return Card(
      color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabelValue('Keyword', row.keyword),
            const SizedBox(height: 10),
            _buildLabelValue('Topic', row.topic),
            const SizedBox(height: 10),
            _buildLabelValue('Content', displayContent),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: displayContent.isEmpty ? null : () => _readRow(row),
                icon: const Icon(Icons.volume_up_rounded),
                label: const Text('Read Aloud'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _cleanContent(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    if (!_isHtml(trimmed)) {
      return trimmed;
    }

    var html = trimmed;
    html = html.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    html = html.replaceAll(
        RegExp(r'<style[^>]*>.*?<\/style>', dotAll: true, caseSensitive: false),
        '');
    html = html.replaceAll(
        RegExp(r'<script[^>]*>.*?<\/script>',
            dotAll: true, caseSensitive: false),
        '');
    html = html.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    html = html.replaceAll(
        RegExp(
            r'<\s*(?:p|div|section|article|header|footer|aside|nav|figure|figcaption|li|tr|td|th|h[1-6])[^>]*>',
            caseSensitive: false),
        '');
    html = html.replaceAll(
        RegExp(
            r'<\s*\/\s*(?:p|div|section|article|header|footer|aside|nav|figure|figcaption|li|tr|td|th|h[1-6])\s*>',
            caseSensitive: false),
        '\n');
    html = html.replaceAll(RegExp(r'<[^>]+>'), '');

    var text = _decodeHtmlEntities(html);
    text = text.replaceAll(RegExp(r'\s*\n\s*'), '\n');
    text = text.replaceAll(RegExp(r'\n{2,}'), '\n\n');
    text = text.replaceAll(RegExp(r'[ \t\u00A0]{2,}'), ' ');
    return text.trim();
  }

  String _buildReadableContent(String content) {
    final cleaned = _cleanContent(content);
    return cleaned.isNotEmpty ? cleaned : content.trim();
  }

  String _decodeHtmlEntities(String input) {
    return input
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }

  bool _isHtml(String content) {
    return RegExp(
      r'<\s*(html|body|div|span|p|br|strong|em|b|i|ul|ol|li|table|tr|td|th|header|footer|section|article|h[1-6])',
      caseSensitive: false,
    ).hasMatch(content);
  }

  Widget _buildLabelValue(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 3),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(fontSize: 15, height: 1.35),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
        child: Column(
          children: [
            Icon(icon, size: 44, color: const Color(0xFF64748B)),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: const TextStyle(color: Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
