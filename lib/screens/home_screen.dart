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
  ExcelRowData? _selectedRow;
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

    return workbook.rowsBySheet[selectedSheet] ?? const [];
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

      setState(() {
        _workbook = workbook;
        _selectedSheet =
            workbook.sheetNames.isEmpty ? null : workbook.sheetNames.first;
        _selectedRow = null;
      });
    } on FormatException catch (error) {
      setState(() {
        _workbook = null;
        _selectedSheet = null;
        _selectedRow = null;
        _errorMessage = error.message;
      });
    } catch (error) {
      final message = error.toString().isNotEmpty
          ? error.toString()
          : 'Unable to open this Excel file. Please choose a valid .xlsx or .xlsm file.';
      setState(() {
        _workbook = null;
        _selectedSheet = null;
        _selectedRow = null;
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

  void _selectKeywordRow(ExcelRowData row) {
    setState(() {
      _selectedRow = row;
    });
  }

  Future<void> _readSelectedContent() async {
    final row = _selectedRow;
    if (row == null) {
      _showSnackBar('Select a keyword before using Read Aloud.');
      return;
    }

    final text = _buildReadableContent(row.content);
    if (text.trim().isEmpty) {
      _showSnackBar('Selected keyword has no content to read.');
      return;
    }

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
      _showSnackBar('Select a keyword before using Read Aloud.');
      return;
    }

    await _readSelectedContent();
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
            if (_errorMessage case final errorMessage?) ...[
              const SizedBox(height: 12),
              _buildErrorBanner(errorMessage),
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
              onChanged: workbook == null
                  ? null
                  : (sheetName) {
                      setState(() {
                        _selectedSheet = sheetName;
                        _selectedRow = null;
                      });
                    },
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
                  label: const Text('Read Aloud'),
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

    final selectedSheet = _selectedSheet;
    if (selectedSheet == null || !workbook.sheetNames.contains(selectedSheet)) {
      return _buildEmptyState(
        icon: Icons.table_chart_outlined,
        title: 'Select a sheet',
        message: 'Choose a sheet from the dropdown to load its keyword rows.',
      );
    }

    final sheetError = _selectedSheetError;
    if (sheetError != null) {
      return _buildEmptyState(
        icon: Icons.error_outline,
        title: 'Sheet cannot be read',
        message: sheetError,
      );
    }

    final rows = _sheetRows;
    if (rows.isEmpty) {
      return _buildEmptyState(
        icon: Icons.table_rows_outlined,
        title: 'No rows to show',
        message:
            'This sheet has the required columns but no readable keyword rows.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Keywords (${rows.length})',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        ...rows.map(_buildKeywordCard),
        if (_selectedRow case final selectedRow?) ...[
          const SizedBox(height: 18),
          const Text(
            'Selected Content',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _buildContentCard(selectedRow),
        ],
      ],
    );
  }

  Widget _buildKeywordCard(ExcelRowData row) {
    final isSelected = identical(row, _selectedRow);
    final topic = row.topic.trim();

    return Card(
      color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
      child: ListTile(
        title: Text(row.keyword),
        subtitle: topic.isEmpty ? const Text('No topic provided') : Text(topic),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
        onTap: () => _selectKeywordRow(row),
      ),
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
                onPressed: displayContent.isEmpty ? null : _readSelectedContent,
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
