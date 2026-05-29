import 'package:flutter/material.dart';

import '../services/excel_service.dart';
import '../services/tts_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ExcelService _excelService = ExcelService();
  final TtsService _ttsService = TtsService();

  ExcelWorkbookData? _workbook;
  String? _selectedSheet;
  ExcelRowData? _selectedRow;
  AccentOption _selectedAccent = TtsService.accents.first;
  SpeechSpeed _selectedSpeed = SpeechSpeed.normal;
  double _pitch = 1.0;
  bool _isLoading = false;
  String? _errorMessage;

  List<ExcelRowData> get _visibleRows {
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
  void dispose() {
    _ttsService.dispose();
    super.dispose();
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
        _selectedSheet = workbook.rowsBySheet.keys.first;
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
      setState(() {
        _workbook = null;
        _selectedSheet = null;
        _selectedRow = null;
        _errorMessage = 'Unable to open this Excel file. Please choose a valid .xlsx file.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _readRow(ExcelRowData row) async {
    setState(() {
      _selectedRow = row;
    });

    await _ttsService.speak(
      text: row.content,
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
              color: Colors.white.withOpacity(0.92),
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
              label: Text(_isLoading ? 'Loading Excel File...' : 'Select Excel File'),
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
              value: _selectedSheet,
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
              value: _selectedAccent,
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
            const Text(
              'Voice Controls',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _visibleRows.isEmpty ? null : _playSelectedRow,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _pauseSpeech,
                  icon: const Icon(Icons.pause_rounded),
                  label: const Text('Pause'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _stopSpeech,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Stop'),
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
    final rows = _visibleRows;

    if (_workbook == null) {
      return _buildEmptyState(
        icon: Icons.upload_file_outlined,
        title: 'No Excel file selected',
        message: 'Tap Select Excel File to upload an .xlsx workbook from your phone storage.',
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

    if (rows.isEmpty) {
      return _buildEmptyState(
        icon: Icons.table_rows_outlined,
        title: 'No rows to show',
        message: 'This sheet has the required columns but no readable content rows.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Content (${rows.length})',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        ...rows.map(_buildContentCard),
      ],
    );
  }

  Widget _buildContentCard(ExcelRowData row) {
    final isSelected = identical(row, _selectedRow);

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
            _buildLabelValue('Content', row.content),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: row.content.trim().isEmpty ? null : () => _readRow(row),
                icon: const Icon(Icons.volume_up_rounded),
                label: const Text('Read Aloud'),
              ),
            ),
          ],
        ),
      ),
    );
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
        Text(
          value.isEmpty ? '—' : value,
          style: const TextStyle(fontSize: 15, height: 1.35),
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
