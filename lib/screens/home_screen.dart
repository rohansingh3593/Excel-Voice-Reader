import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/excel_service.dart';
import '../services/tts_service.dart';


class TopicPlaybackItem {
  const TopicPlaybackItem({
    required this.id,
    required this.sheetName,
    required this.keyword,
    required this.topic,
    required this.rows,
    this.playlistName,
  });

  final String id;
  final String sheetName;
  final String keyword;
  final String topic;
  final List<ExcelRowData> rows;
  final String? playlistName;

  TopicPlaybackItem copyWith({String? playlistName}) {
    return TopicPlaybackItem(
      id: id,
      sheetName: sheetName,
      keyword: keyword,
      topic: topic,
      rows: rows,
      playlistName: playlistName ?? this.playlistName,
    );
  }
}

class TopicPlaylist {
  const TopicPlaylist({required this.name, required this.items});

  final String name;
  final List<TopicPlaybackItem> items;

  TopicPlaylist copyWith({List<TopicPlaybackItem>? items}) {
    return TopicPlaylist(name: name, items: items ?? this.items);
  }
}

class ReadingViewScreen extends StatefulWidget {
  const ReadingViewScreen({
    super.key,
    required this.topicTitle,
    required this.sourceLabel,
    required this.segments,
    required this.highlightedIndex,
    required this.progress,
    required this.elapsedLabel,
    required this.remainingLabel,
    required this.settingsLabel,
    required this.onSeekBackward10,
    required this.onSeekForward10,
    required this.onSeekBackward30,
    required this.onSeekForward30,
    required this.onPreviousTopic,
    required this.onNextTopic,
    required this.onPause,
    required this.onResume,
  });

  final String topicTitle;
  final String sourceLabel;
  final List<String> segments;
  final ValueNotifier<int> highlightedIndex;
  final ValueNotifier<double> progress;
  final String Function() elapsedLabel;
  final String Function() remainingLabel;
  final String settingsLabel;
  final Future<void> Function() onSeekBackward10;
  final Future<void> Function() onSeekForward10;
  final Future<void> Function() onSeekBackward30;
  final Future<void> Function() onSeekForward30;
  final Future<void> Function() onPreviousTopic;
  final Future<void> Function() onNextTopic;
  final Future<void> Function() onPause;
  final Future<void> Function() onResume;

  @override
  State<ReadingViewScreen> createState() => _ReadingViewScreenState();
}

class _ReadingViewScreenState extends State<ReadingViewScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.highlightedIndex.addListener(_scrollToHighlighted);
  }

  @override
  void dispose() {
    widget.highlightedIndex.removeListener(_scrollToHighlighted);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToHighlighted() {
    if (!_scrollController.hasClients || widget.segments.isEmpty) {
      return;
    }

    final maxScroll = _scrollController.position.maxScrollExtent;
    final ratio = widget.segments.length <= 1
        ? 0.0
        : widget.highlightedIndex.value / (widget.segments.length - 1);
    final target = (maxScroll * ratio).clamp(0, maxScroll).toDouble();
    unawaited(_scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reading View')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.topicTitle,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(widget.sourceLabel, style: const TextStyle(color: Color(0xFF64748B))),
              const SizedBox(height: 14),
              ValueListenableBuilder<double>(
                valueListenable: widget.progress,
                builder: (context, progress, child) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(value: progress.clamp(0, 1).toDouble()),
                      const SizedBox(height: 6),
                      Text(
                        'Progress: ${(progress * 100).round()}% • ${widget.elapsedLabel()} elapsed • ${widget.remainingLabel()} remaining',
                        style: const TextStyle(color: Color(0xFF475569)),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Text(widget.settingsLabel, style: const TextStyle(color: Color(0xFF475569))),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(onPressed: () => unawaited(widget.onSeekBackward30()), child: const Text('-30s')),
                  OutlinedButton(onPressed: () => unawaited(widget.onSeekBackward10()), child: const Text('-10s')),
                  FilledButton.tonalIcon(
                    onPressed: () => unawaited(widget.onPause()),
                    icon: const Icon(Icons.pause_rounded),
                    label: const Text('Pause'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => unawaited(widget.onResume()),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Resume'),
                  ),
                  OutlinedButton(onPressed: () => unawaited(widget.onSeekForward10()), child: const Text('+10s')),
                  OutlinedButton(onPressed: () => unawaited(widget.onSeekForward30()), child: const Text('+30s')),
                  OutlinedButton.icon(
                    onPressed: () => unawaited(widget.onPreviousTopic()),
                    icon: const Icon(Icons.skip_previous_rounded),
                    label: const Text('Previous Topic'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => unawaited(widget.onNextTopic()),
                    icon: const Icon(Icons.skip_next_rounded),
                    label: const Text('Next Topic'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Currently Reading',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: widget.highlightedIndex,
                  builder: (context, highlightedIndex, child) {
                    return ListView.builder(
                      controller: _scrollController,
                      itemCount: widget.segments.length,
                      itemBuilder: (context, index) {
                        final isHighlighted = index == highlightedIndex;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isHighlighted
                                ? const Color(0xFFFEF3C7)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: isHighlighted
                                ? Border.all(color: const Color(0xFFF59E0B))
                                : null,
                          ),
                          child: Text(
                            widget.segments[index],
                            style: TextStyle(
                              fontSize: 17,
                              height: 1.4,
                              fontWeight:
                                  isHighlighted ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ExcelService _excelService = const ExcelService();
  static const String _speechRatePreferenceKey = 'speech_rate';

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
  VoiceStyle _selectedVoiceStyle = VoiceStyle.defaultVoice;
  double _pitch = 1.0;
  bool _isLoading = false;
  String? _errorMessage;
  TopicPlaybackItem? _nowPlaying;
  List<TopicPlaybackItem> _playbackQueue = const <TopicPlaybackItem>[];
  final Map<String, TopicPlaylist> _playlists = <String, TopicPlaylist>{};
  final Set<String> _selectedTopicIds = <String>{};
  final ScrollController _readingScrollController = ScrollController();
  final ValueNotifier<int> _highlightedSegmentNotifier = ValueNotifier<int>(0);
  final ValueNotifier<double> _readingProgressNotifier = ValueNotifier<double>(0);
  Timer? _readingProgressTimer;
  List<String> _readingSegments = const <String>[];
  List<double> _segmentStartSeconds = const <double>[];
  double _estimatedDurationSeconds = 0;
  double _currentPlaybackSeconds = 0;
  int _highlightedSegmentIndex = 0;
  bool _isReadingPaused = false;
  final List<TopicPlaybackItem> _topicHistory = <TopicPlaybackItem>[];

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
    unawaited(_loadSavedSpeechSpeed());
  }

  @override
  void dispose() {
    _readingProgressTimer?.cancel();
    _readingScrollController.dispose();
    _highlightedSegmentNotifier.dispose();
    _readingProgressNotifier.dispose();
    _ttsService.playbackError.removeListener(_showTtsPlaybackError);
    _ttsService.dispose();
    super.dispose();
  }

  Future<void> _loadSavedSpeechSpeed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedRate = prefs.getDouble(_speechRatePreferenceKey);
      if (savedRate == null) {
        return;
      }

      final savedSpeed = _speechSpeedForRate(savedRate);
      if (!mounted) {
        return;
      }

      setState(() {
        _selectedSpeed = savedSpeed;
      });
      _applyPlaybackSettings();
    } catch (error) {
      debugPrint('Unable to load saved speech speed: $error');
    }
  }

  Future<void> _saveSpeechSpeed(SpeechSpeed speed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_speechRatePreferenceKey, speed.rate);
    } catch (error) {
      debugPrint('Unable to save speech speed: $error');
    }
  }

  SpeechSpeed _speechSpeedForRate(double rate) {
    return SpeechSpeed.values.reduce((closest, speed) {
      final closestDistance = (closest.rate - rate).abs();
      final speedDistance = (speed.rate - rate).abs();
      return speedDistance < closestDistance ? speed : closest;
    });
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
    _selectedTopicIds.clear();
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
      _selectedTopicIds.clear();
    });
  }

  List<TopicPlaybackItem> _topicItemsForKeyword(String keyword) {
    final sheetName = _selectedSheet;
    if (sheetName == null) {
      return const <TopicPlaybackItem>[];
    }

    final topics = _sheetRows
        .where((row) => row.keyword == keyword)
        .map((row) => row.topic)
        .where((topic) => topic.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return topics
        .map((topic) => _topicItemFor(topic, keyword: keyword))
        .whereType<TopicPlaybackItem>()
        .toList(growable: false);
  }

  List<TopicPlaybackItem> _selectedTopicItems() {
    final keyword = _selectedKeyword;
    if (keyword == null || _selectedTopicIds.isEmpty) {
      return const <TopicPlaybackItem>[];
    }

    return _topicItemsForKeyword(keyword)
        .where((item) => _selectedTopicIds.contains(item.id))
        .toList(growable: false);
  }

  TopicPlaybackItem? _topicItemFor(
    String topic, {
    String? keyword,
    String? playlistName,
  }) {
    final sheetName = _selectedSheet;
    final resolvedKeyword = keyword ?? _selectedKeyword;
    if (sheetName == null || resolvedKeyword == null) {
      return null;
    }

    final rows = _sheetRows
        .where((row) => row.keyword == resolvedKeyword && row.topic == topic)
        .toList(growable: false);
    if (rows.isEmpty) {
      return null;
    }

    return TopicPlaybackItem(
      id: '$sheetName|$resolvedKeyword|$topic',
      sheetName: sheetName,
      keyword: resolvedKeyword,
      topic: topic,
      rows: rows,
      playlistName: playlistName,
    );
  }

  Future<void> _selectTopic(String topic) async {
    final item = _topicItemFor(topic);
    if (item == null) {
      _showSnackBar('No content rows found for this topic.');
      return;
    }

    await _playTopicNow(item);
  }

  Future<void> _playTopicNow(
    TopicPlaybackItem item, {
    int startSegmentIndex = 0,
    bool rememberCurrent = true,
  }) async {
    final current = _nowPlaying;
    if (rememberCurrent && current != null && current.id != item.id) {
      _topicHistory.add(current);
    }

    final playbackRequestId = ++_topicPlaybackRequestId;
    debugPrint('DEBUG: Play Now topic=${item.topic}, keyword=${item.keyword}');

    _stopReadingProgressTimer();
    await _ttsService.stop();
    _ttsService.clearQueue();

    if (!mounted || playbackRequestId != _topicPlaybackRequestId) {
      return;
    }

    setState(() {
      _nowPlaying = item;
      _selectedTopic = item.topic;
      _selectedRow = item.rows.isNotEmpty ? item.rows.first : null;
    });

    await _speakTopicItem(
      item,
      playbackRequestId,
      startSegmentIndex: startSegmentIndex,
    );
  }

  Future<void> _speakTopicItem(
    TopicPlaybackItem item,
    int playbackRequestId, {
    int startSegmentIndex = 0,
  }) async {
    final segments = _segmentsForTopic(item);
    if (segments.isEmpty) {
      _showSnackBar('Selected topic has no readable content.');
      return;
    }

    final safeStartIndex = startSegmentIndex.clamp(0, segments.length - 1).toInt();
    _prepareReadingProgress(segments, safeStartIndex);
    final text = segments.skip(safeStartIndex).join('\n\n');
    debugPrint('DEBUG: Prepared topic text (length=${text.length})');

    if (!mounted || playbackRequestId != _topicPlaybackRequestId) {
      return;
    }

    _startReadingProgressTimer(playbackRequestId);
    await _ttsService.speak(
      text: text,
      accent: _selectedAccent,
      speed: _selectedSpeed,
      pitch: _pitch,
      voiceStyle: _selectedVoiceStyle,
    );

    if (!mounted || playbackRequestId != _topicPlaybackRequestId) {
      return;
    }

    _stopReadingProgressTimer(markComplete: true);
    setState(() {
      _nowPlaying = null;
    });
    await _playNextQueued();
  }

  List<String> _segmentsForTopic(TopicPlaybackItem item) {
    return item.rows
        .expand((row) => _splitReadableSegments(_buildReadableContent(row.content)))
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
  }

  List<String> _splitReadableSegments(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return const <String>[];
    }

    final paragraphSegments = normalized
        .split(RegExp(r'\n{2,}'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (paragraphSegments.length > 1) {
      return paragraphSegments;
    }

    final sentenceMatches = RegExp(r'[^.!?]+[.!?]+|[^.!?]+$')
        .allMatches(normalized)
        .map((match) => match.group(0)?.trim() ?? '')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return sentenceMatches.isEmpty ? <String>[normalized] : sentenceMatches;
  }

  void _prepareReadingProgress(List<String> segments, int startIndex) {
    _readingSegments = segments;
    _segmentStartSeconds = _buildSegmentStartSeconds(segments);
    _estimatedDurationSeconds = _estimateTotalDuration(segments);
    _highlightedSegmentIndex = startIndex;
    _currentPlaybackSeconds = _secondsForSegmentIndex(startIndex);
    _isReadingPaused = false;
    _publishReadingProgress();
  }

  List<double> _buildSegmentStartSeconds(List<String> segments) {
    final starts = <double>[];
    var elapsed = 0.0;
    for (final segment in segments) {
      starts.add(elapsed);
      elapsed += _estimateSegmentDuration(segment);
    }
    return starts;
  }

  double _estimateTotalDuration(List<String> segments) {
    return segments.fold<double>(
      0,
      (total, segment) => total + _estimateSegmentDuration(segment),
    );
  }

  double _estimateSegmentDuration(String segment) {
    final words = segment.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
    final wordsPerSecond = (2.4 * _selectedSpeed.rate).clamp(1.2, 4.5).toDouble();
    return (words / wordsPerSecond).clamp(1.5, 12.0).toDouble();
  }

  double _secondsForSegmentIndex(int index) {
    if (_segmentStartSeconds.isEmpty) {
      return 0;
    }
    return _segmentStartSeconds[index.clamp(0, _segmentStartSeconds.length - 1).toInt()];
  }

  int _segmentIndexForSeconds(double seconds) {
    if (_segmentStartSeconds.isEmpty) {
      return 0;
    }

    for (var index = _segmentStartSeconds.length - 1; index >= 0; index--) {
      if (seconds >= _segmentStartSeconds[index]) {
        return index;
      }
    }
    return 0;
  }

  void _startReadingProgressTimer(int playbackRequestId) {
    _readingProgressTimer?.cancel();
    _readingProgressTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || playbackRequestId != _topicPlaybackRequestId || _isReadingPaused) {
        return;
      }

      _currentPlaybackSeconds = (_currentPlaybackSeconds + 0.5)
          .clamp(0, _estimatedDurationSeconds)
          .toDouble();
      _highlightedSegmentIndex = _segmentIndexForSeconds(_currentPlaybackSeconds);
      _publishReadingProgress();
    });
  }

  void _stopReadingProgressTimer({bool markComplete = false}) {
    _readingProgressTimer?.cancel();
    _readingProgressTimer = null;
    if (markComplete && _estimatedDurationSeconds > 0) {
      _currentPlaybackSeconds = _estimatedDurationSeconds;
      _readingProgressNotifier.value = 1;
    }
  }

  void _publishReadingProgress() {
    _highlightedSegmentNotifier.value = _highlightedSegmentIndex;
    _readingProgressNotifier.value = _estimatedDurationSeconds <= 0
        ? 0
        : (_currentPlaybackSeconds / _estimatedDurationSeconds).clamp(0, 1).toDouble();
    _scrollHighlightedSegmentIntoView();
  }

  void _scrollHighlightedSegmentIntoView() {
    if (!_readingScrollController.hasClients || _readingSegments.isEmpty) {
      return;
    }

    final maxScroll = _readingScrollController.position.maxScrollExtent;
    final ratio = _readingSegments.length <= 1
        ? 0.0
        : _highlightedSegmentIndex / (_readingSegments.length - 1);
    final target = (maxScroll * ratio).clamp(0, maxScroll).toDouble();
    unawaited(_readingScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    ));
  }

  Future<void> _seekBySeconds(int seconds) async {
    final item = _nowPlaying;
    if (item == null || _readingSegments.isEmpty) {
      return;
    }

    final targetSeconds = (_currentPlaybackSeconds + seconds)
        .clamp(0, _estimatedDurationSeconds)
        .toDouble();
    final targetIndex = _segmentIndexForSeconds(targetSeconds);
    await _playTopicNow(
      item,
      startSegmentIndex: targetIndex,
      rememberCurrent: false,
    );
  }

  Future<void> _playPreviousTopic() async {
    if (_topicHistory.isEmpty) {
      _showSnackBar('No previous topic.');
      return;
    }

    final previous = _topicHistory.removeLast();
    await _playTopicNow(previous, rememberCurrent: false);
  }

  Future<void> _addTopicToQueue(TopicPlaybackItem item) async {
    await _addTopicsToQueue([item]);
  }

  Future<void> _addTopicsToQueue(List<TopicPlaybackItem> items) async {
    if (items.isEmpty) {
      _showSnackBar('Select at least one topic first.');
      return;
    }

    setState(() {
      _playbackQueue = [..._playbackQueue, ...items];
    });
    _showSnackBar(
      items.length == 1
          ? 'Added "${items.first.topic}" to queue.'
          : 'Added ${items.length} topics to queue.',
    );

    if (_nowPlaying == null && !_ttsService.isPlaying) {
      await _playNextQueued();
    }
  }

  Future<void> _playKeywordNow(String keyword) async {
    final items = _topicItemsForKeyword(keyword);
    if (items.isEmpty) {
      _showSnackBar('No readable topics found for this keyword.');
      return;
    }

    setState(() {
      _playbackQueue = [...items.skip(1), ..._playbackQueue];
    });
    await _playTopicNow(items.first);
  }

  Future<void> _addKeywordToQueue(String keyword) async {
    await _addTopicsToQueue(_topicItemsForKeyword(keyword));
  }

  Future<void> _playNextQueued() async {
    if (_playbackQueue.isEmpty) {
      return;
    }

    final nextItem = _playbackQueue.first;
    setState(() {
      _playbackQueue = _playbackQueue.skip(1).toList(growable: false);
    });
    await _playTopicNow(nextItem);
  }

  void _removeQueueItem(int index) {
    setState(() {
      _playbackQueue = [
        for (var i = 0; i < _playbackQueue.length; i++)
          if (i != index) _playbackQueue[i],
      ];
    });
  }

  void _moveQueueItem(int index, int delta) {
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= _playbackQueue.length) {
      return;
    }

    final queue = [..._playbackQueue];
    final item = queue.removeAt(index);
    queue.insert(newIndex, item);
    setState(() {
      _playbackQueue = queue;
    });
  }

  void _clearPlaybackQueue() {
    setState(() {
      _playbackQueue = const <TopicPlaybackItem>[];
    });
  }

  Future<void> _playQueueFromBeginning() async {
    if (_playbackQueue.isEmpty) {
      _showSnackBar('Queue is empty.');
      return;
    }

    await _playNextQueued();
  }

  void _toggleTopicSelection(TopicPlaybackItem item, bool selected) {
    setState(() {
      if (selected) {
        _selectedTopicIds.add(item.id);
      } else {
        _selectedTopicIds.remove(item.id);
      }
    });
  }

  void _selectAllVisibleTopics(List<TopicPlaybackItem> items) {
    setState(() {
      _selectedTopicIds
        ..clear()
        ..addAll(items.map((item) => item.id));
    });
  }

  void _clearTopicSelection() {
    setState(() {
      _selectedTopicIds.clear();
    });
  }

  void _removeSelectedFromQueue() {
    final selectedIds = Set<String>.of(_selectedTopicIds);
    if (selectedIds.isEmpty) {
      _showSnackBar('Select at least one topic first.');
      return;
    }

    setState(() {
      _playbackQueue = _playbackQueue
          .where((item) => !selectedIds.contains(item.id))
          .toList(growable: false);
      _selectedTopicIds.clear();
    });
    _showSnackBar('Removed selected topics from queue.');
  }

  Future<void> _showAddToPlaylistDialog(TopicPlaybackItem item) async {
    await _showAddItemsToPlaylistDialog([item]);
  }

  Future<void> _showAddItemsToPlaylistDialog(List<TopicPlaybackItem> items) async {
    if (items.isEmpty) {
      _showSnackBar('Select at least one topic first.');
      return;
    }

    final controller = TextEditingController();
    final selectedPlaylist = await showDialog<String>(
      context: context,
      builder: (context) {
        final playlistNames = _playlists.keys.toList(growable: false)..sort();
        return AlertDialog(
          title: const Text('Add to Playlist'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (playlistNames.isNotEmpty) ...[
                  const Text('Existing playlists'),
                  const SizedBox(height: 8),
                  ...playlistNames.map(
                    (name) => ListTile(
                      title: Text(name),
                      onTap: () => Navigator.of(context).pop(name),
                    ),
                  ),
                  const Divider(),
                ],
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'New playlist name',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: playlistNames.isEmpty,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  Navigator.of(context).pop(name);
                }
              },
              child: const Text('Create / Add'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (!mounted) {
      return;
    }

    final playlistName = selectedPlaylist?.trim();
    if (playlistName == null || playlistName.isEmpty) {
      return;
    }

    _addTopicsToPlaylist(items, playlistName);
  }

  void _addTopicsToPlaylist(List<TopicPlaybackItem> items, String playlistName) {
    if (items.isEmpty) {
      _showSnackBar('Select at least one topic first.');
      return;
    }

    final current = _playlists[playlistName] ??
        TopicPlaylist(name: playlistName, items: const <TopicPlaybackItem>[]);
    final playlistItems = items
        .map((item) => item.copyWith(playlistName: playlistName))
        .toList(growable: false);
    setState(() {
      _playlists[playlistName] = current.copyWith(
        items: [...current.items, ...playlistItems],
      );
    });
    _showSnackBar(
      items.length == 1
          ? 'Added "${items.first.topic}" to $playlistName.'
          : 'Added ${items.length} topics to $playlistName.',
    );
  }

  void _removePlaylistItem(String playlistName, int index) {
    final playlist = _playlists[playlistName];
    if (playlist == null) {
      return;
    }

    final items = [
      for (var i = 0; i < playlist.items.length; i++)
        if (i != index) playlist.items[i],
    ];
    setState(() {
      _playlists[playlistName] = playlist.copyWith(items: items);
    });
  }

  void _clearPlaylist(String playlistName) {
    final playlist = _playlists[playlistName];
    if (playlist == null) {
      return;
    }

    setState(() {
      _playlists[playlistName] = playlist.copyWith(items: const <TopicPlaybackItem>[]);
    });
  }

  void _deletePlaylist(String playlistName) {
    setState(() {
      _playlists.remove(playlistName);
    });
  }

  Future<void> _playPlaylist(TopicPlaylist playlist) async {
    if (playlist.items.isEmpty) {
      return;
    }

    final first = playlist.items.first.copyWith(playlistName: playlist.name);
    final rest = playlist.items
        .skip(1)
        .map((item) => item.copyWith(playlistName: playlist.name))
        .toList(growable: false);
    setState(() {
      _playbackQueue = [...rest, ..._playbackQueue];
    });
    await _playTopicNow(first);
  }

  Future<void> _addPlaylistToQueue(TopicPlaylist playlist) async {
    if (playlist.items.isEmpty) {
      return;
    }

    final items = playlist.items
        .map((item) => item.copyWith(playlistName: playlist.name))
        .toList(growable: false);
    setState(() {
      _playbackQueue = [..._playbackQueue, ...items];
    });
    _showSnackBar('Added ${items.length} topic(s) from ${playlist.name} to queue.');

    if (_nowPlaying == null && !_ttsService.isPlaying) {
      await _playNextQueued();
    }
  }

  Future<void> _readRow(ExcelRowData row) async {
    await _ttsService.stop();
    _ttsService.clearQueue();

    if (!mounted) {
      return;
    }

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
      voiceStyle: _selectedVoiceStyle,
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

  void _applyPlaybackSettings() {
    _ttsService.applyPlaybackSettings(
      accent: _selectedAccent,
      speed: _selectedSpeed,
      pitch: _pitch,
      voiceStyle: _selectedVoiceStyle,
    );
  }

  void _restartPlaybackIfActive() {
    _applyPlaybackSettings();
    if (!_ttsService.isPlaying) {
      return;
    }

    final nowPlaying = _nowPlaying;
    if (nowPlaying != null) {
      unawaited(_playTopicNow(nowPlaying));
      return;
    }

    final selectedRow = _selectedRow;
    if (selectedRow != null) {
      unawaited(_readRow(selectedRow));
    }
  }

  void _changeSpeed(SpeechSpeed speed) {
    setState(() {
      _selectedSpeed = speed;
    });
    unawaited(_saveSpeechSpeed(speed));
    _restartPlaybackIfActive();
  }

  void _changeVoiceStyle(VoiceStyle voiceStyle) {
    setState(() {
      _selectedVoiceStyle = voiceStyle;
    });
    _restartPlaybackIfActive();
  }

  void _changePitch(double pitch) {
    setState(() {
      _pitch = pitch;
    });
    _restartPlaybackIfActive();
  }

  Future<void> _pauseSpeech() async {
    _isReadingPaused = true;
    await _ttsService.pause();
  }

  Future<void> _stopSpeech() async {
    _topicPlaybackRequestId++;
    _stopReadingProgressTimer();
    await _ttsService.stop();
    if (!mounted) {
      return;
    }
    setState(() {
      _nowPlaying = null;
    });
  }

  Future<void> _resumeSpeech() async {
    _isReadingPaused = false;
    await _ttsService.resume();
  }

  Future<void> _skipToNextTopic() async {
    _topicPlaybackRequestId++;
    _stopReadingProgressTimer();
    await _ttsService.stop();
    if (!mounted) {
      return;
    }
    setState(() {
      _nowPlaying = null;
    });
    await _playNextQueued();
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
            const SizedBox(height: 14),
            _buildNowPlayingDashboard(),
            const SizedBox(height: 14),
            _buildQueuePanel(),
            const SizedBox(height: 14),
            _buildPlaylistPanel(),
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
                _restartPlaybackIfActive();
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<VoiceStyle>(
              initialValue: _selectedVoiceStyle,
              decoration: const InputDecoration(
                labelText: 'Voice Style',
                prefixIcon: Icon(Icons.voice_chat_outlined),
                border: OutlineInputBorder(),
              ),
              items: VoiceStyle.values
                  .map(
                    (voiceStyle) => DropdownMenuItem(
                      value: voiceStyle,
                      child: Text(voiceStyle.label),
                    ),
                  )
                  .toList(),
              onChanged: (voiceStyle) {
                if (voiceStyle == null) {
                  return;
                }

                _changeVoiceStyle(voiceStyle);
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
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _playbackQueue.isNotEmpty
                        ? const Color(0xFFEEF2FF)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Text(
                    'Queue: ${_playbackQueue.length}',
                    style: const TextStyle(fontSize: 13),
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
                  onPressed: _skipToNextTopic,
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
                _changeSpeed(selection.first);
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
                    onChanged: _changePitch,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadingProgressSummary() {
    return ValueListenableBuilder<double>(
      valueListenable: _readingProgressNotifier,
      builder: (context, progress, child) {
        final elapsed = _formatDuration(_currentPlaybackSeconds);
        final remaining = _formatDuration(
          (_estimatedDurationSeconds - _currentPlaybackSeconds).clamp(0, double.infinity).toDouble(),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: progress.clamp(0, 1).toDouble()),
            const SizedBox(height: 6),
            Text(
              'Progress: ${(progress * 100).round()}% • $elapsed elapsed • $remaining remaining',
              style: const TextStyle(color: Color(0xFF475569), fontSize: 13),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHighlightedReadingText({ScrollController? controller}) {
    if (_readingSegments.isEmpty) {
      return const Text('No reading content available yet.');
    }

    return ValueListenableBuilder<int>(
      valueListenable: _highlightedSegmentNotifier,
      builder: (context, highlightedIndex, child) {
        return ListView.builder(
          controller: controller,
          shrinkWrap: controller == null,
          physics: controller == null ? const NeverScrollableScrollPhysics() : null,
          itemCount: _readingSegments.length,
          itemBuilder: (context, index) {
            final isHighlighted = index == highlightedIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isHighlighted ? const Color(0xFFFEF3C7) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: isHighlighted
                    ? Border.all(color: const Color(0xFFF59E0B))
                    : null,
              ),
              child: Text(
                _readingSegments[index],
                style: TextStyle(
                  fontSize: 16,
                  height: 1.35,
                  fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openReadingView() async {
    final item = _nowPlaying;
    if (item == null) {
      _showSnackBar('Play a topic before opening Reading View.');
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ReadingViewScreen(
          topicTitle: item.topic,
          sourceLabel:
              '${item.sheetName} • ${item.keyword}${item.playlistName == null ? '' : ' • Playlist: ${item.playlistName}'}',
          segments: _readingSegments,
          highlightedIndex: _highlightedSegmentNotifier,
          progress: _readingProgressNotifier,
          elapsedLabel: () => _formatDuration(_currentPlaybackSeconds),
          remainingLabel: () => _formatDuration(
            (_estimatedDurationSeconds - _currentPlaybackSeconds).clamp(0, double.infinity).toDouble(),
          ),
          settingsLabel:
              'Speed: ${_selectedSpeed.label} • Pitch: ${_pitch.toStringAsFixed(1)} • Accent: ${_selectedAccent.label} • Voice: ${_selectedVoiceStyle.label}',
          onSeekBackward10: () => _seekBySeconds(-10),
          onSeekForward10: () => _seekBySeconds(10),
          onSeekBackward30: () => _seekBySeconds(-30),
          onSeekForward30: () => _seekBySeconds(30),
          onPreviousTopic: _playPreviousTopic,
          onNextTopic: _skipToNextTopic,
          onPause: _pauseSpeech,
          onResume: _resumeSpeech,
        ),
      ),
    );
  }

  String _formatDuration(double seconds) {
    final duration = Duration(seconds: seconds.round());
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${duration.inHours}:$minutes:$secs';
    }
    return '$minutes:$secs';
  }

  Widget _buildNowPlayingDashboard() {
    final item = _nowPlaying;
    final content = item == null
        ? 'No topic is currently playing.'
        : item.rows
            .map((row) => _buildReadableContent(row.content))
            .where((text) => text.trim().isNotEmpty)
            .join('\n\n');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.graphic_eq_rounded),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Now Playing',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                Chip(label: Text('Queue: ${_playbackQueue.length}')),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              item?.topic ?? 'Nothing playing',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              item == null
                  ? 'Choose Play Now on a topic to start.'
                  : '${item.sheetName} • ${item.keyword}${item.playlistName == null ? '' : ' • Playlist: ${item.playlistName}'}',
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 120),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: item == null
                  ? Text(content.isEmpty ? '—' : content)
                  : _buildHighlightedReadingText(
                      controller: _readingScrollController,
                    ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: item == null ? null : () => _playTopicNow(item),
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
                  onPressed: _skipToNextTopic,
                  icon: const Icon(Icons.skip_next_rounded),
                  label: const Text('Next'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _playPreviousTopic,
                  icon: const Icon(Icons.skip_previous_rounded),
                  label: const Text('Previous Topic'),
                ),
                OutlinedButton(
                  onPressed: () => _seekBySeconds(-30),
                  child: const Text('-30s'),
                ),
                OutlinedButton(
                  onPressed: () => _seekBySeconds(-10),
                  child: const Text('-10s'),
                ),
                OutlinedButton(
                  onPressed: () => _seekBySeconds(10),
                  child: const Text('+10s'),
                ),
                OutlinedButton(
                  onPressed: () => _seekBySeconds(30),
                  child: const Text('+30s'),
                ),
                OutlinedButton.icon(
                  onPressed: _skipToNextTopic,
                  icon: const Icon(Icons.skip_next_rounded),
                  label: const Text('Next Topic'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildReadingProgressSummary(),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _readingSegments.isEmpty ? null : _openReadingView,
              icon: const Icon(Icons.menu_book_rounded),
              label: const Text('Open Reading View'),
            ),
            const SizedBox(height: 10),
            Text(
              'Speed: ${_selectedSpeed.label} • Pitch: ${_pitch.toStringAsFixed(1)} • Accent: ${_selectedAccent.label} • Voice: ${_selectedVoiceStyle.label}',
              style: const TextStyle(color: Color(0xFF475569), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueuePanel() {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.queue_music_rounded),
        title: Text('Queue (${_playbackQueue.length})'),
        subtitle: const Text('Queued topics play automatically after the current topic.'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (_playbackQueue.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('No topics in queue.'),
            )
          else ...[
            for (var index = 0; index < _playbackQueue.length; index++)
              _buildQueueItemTile(_playbackQueue[index], index),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _playQueueFromBeginning,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play Queue'),
                  ),
                  TextButton.icon(
                    onPressed: _clearPlaybackQueue,
                    icon: const Icon(Icons.clear_all_rounded),
                    label: const Text('Clear Queue'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQueueItemTile(TopicPlaybackItem item, int index) {
    return Card(
      child: ListTile(
        title: Text(item.topic),
        subtitle: Text('${item.sheetName} • ${item.keyword}'),
        trailing: Wrap(
          spacing: 2,
          children: [
            IconButton(
              tooltip: 'Move up',
              onPressed: index == 0 ? null : () => _moveQueueItem(index, -1),
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
            IconButton(
              tooltip: 'Move down',
              onPressed: index == _playbackQueue.length - 1
                  ? null
                  : () => _moveQueueItem(index, 1),
              icon: const Icon(Icons.arrow_downward_rounded),
            ),
            IconButton(
              tooltip: 'Remove',
              onPressed: () => _removeQueueItem(index),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistPanel() {
    final playlists = _playlists.values.toList(growable: false);
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.playlist_play_rounded),
        title: Text('Playlists (${playlists.length})'),
        subtitle: const Text('Save topics, play a playlist, or add it to queue.'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('No playlists yet. Use Add to Playlist on a topic.'),
            )
          else
            ...playlists.map(_buildPlaylistTile),
        ],
      ),
    );
  }

  Widget _buildPlaylistTile(TopicPlaylist playlist) {
    return Card(
      child: ExpansionTile(
        title: Text(playlist.name),
        subtitle: Text('${playlist.items.length} topic(s)'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: playlist.items.isEmpty
                    ? null
                    : () => _playPlaylist(playlist),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play Playlist'),
              ),
              FilledButton.tonalIcon(
                onPressed: playlist.items.isEmpty
                    ? null
                    : () => _addPlaylistToQueue(playlist),
                icon: const Icon(Icons.queue_rounded),
                label: const Text('Add Playlist to Queue'),
              ),
              OutlinedButton.icon(
                onPressed: playlist.items.isEmpty
                    ? null
                    : () => _clearPlaylist(playlist.name),
                icon: const Icon(Icons.clear_all_rounded),
                label: const Text('Clear Playlist'),
              ),
              OutlinedButton.icon(
                onPressed: () => _deletePlaylist(playlist.name),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete Playlist'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (playlist.items.isEmpty)
            const Text('This playlist is empty.')
          else
            ...playlist.items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return ListTile(
                dense: true,
                title: Text(item.topic),
                subtitle: Text('${item.sheetName} • ${item.keyword}'),
                trailing: IconButton(
                  tooltip: 'Remove from playlist',
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  onPressed: () => _removePlaylistItem(playlist.name, index),
                ),
              );
            }),
        ],
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
          ...keywords.map(_buildKeywordCard),
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
                  _selectedTopicIds.clear();
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
        _buildBulkTopicActions(
          topics
              .map((topic) => _topicItemFor(topic))
              .whereType<TopicPlaybackItem>()
              .toList(growable: false),
        ),
        const SizedBox(height: 12),
        ...topics.map((topic) {
          final item = _topicItemFor(topic);
          if (item == null) {
            return const SizedBox.shrink();
          }

          return _buildTopicCard(item);
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

  Widget _buildKeywordCard(String keyword) {
    final topicCount = _topicItemsForKeyword(keyword).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(keyword),
              subtitle: Text('$topicCount topic(s)'),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
              onTap: () => _selectKeyword(keyword),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: topicCount == 0 ? null : () => _playKeywordNow(keyword),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play Now'),
                ),
                FilledButton.tonalIcon(
                  onPressed: topicCount == 0 ? null : () => _addKeywordToQueue(keyword),
                  icon: const Icon(Icons.queue_rounded),
                  label: const Text('Add to Queue'),
                ),
                FilledButton.tonalIcon(
                  onPressed: topicCount == 0
                      ? null
                      : () => _showAddItemsToPlaylistDialog(
                            _topicItemsForKeyword(keyword),
                          ),
                  icon: const Icon(Icons.playlist_add_rounded),
                  label: const Text('Add to Playlist'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBulkTopicActions(List<TopicPlaybackItem> items) {
    final selectedItems = _selectedTopicItems();
    final selectedCount = selectedItems.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bulk actions${selectedCount == 0 ? '' : ' • $selectedCount selected'}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: items.isEmpty ? null : () => _selectAllVisibleTopics(items),
                  icon: const Icon(Icons.select_all_rounded),
                  label: const Text('Select All'),
                ),
                FilledButton.tonalIcon(
                  onPressed: selectedItems.isEmpty
                      ? null
                      : () => _addTopicsToQueue(selectedItems),
                  icon: const Icon(Icons.queue_rounded),
                  label: const Text('Add Selected to Queue'),
                ),
                FilledButton.tonalIcon(
                  onPressed: selectedItems.isEmpty
                      ? null
                      : () => _showAddItemsToPlaylistDialog(selectedItems),
                  icon: const Icon(Icons.playlist_add_rounded),
                  label: const Text('Add Selected to Playlist'),
                ),
                OutlinedButton.icon(
                  onPressed: selectedItems.isEmpty ? null : _removeSelectedFromQueue,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  label: const Text('Remove Selected'),
                ),
                TextButton.icon(
                  onPressed: selectedItems.isEmpty ? null : _clearTopicSelection,
                  icon: const Icon(Icons.clear_rounded),
                  label: const Text('Clear Selection'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicCard(TopicPlaybackItem item) {
    final isSelected = item.topic == _selectedTopic;
    final isBulkSelected = _selectedTopicIds.contains(item.id);
    return Card(
      color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: isBulkSelected,
                  onChanged: (selected) =>
                      _toggleTopicSelection(item, selected ?? false),
                ),
                Expanded(
                  child: Text(
                    item.topic,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${item.sheetName} • ${item.keyword}',
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
            if (isSelected) ...[
              const SizedBox(height: 4),
              const Text(
                'Currently selected',
                style: TextStyle(color: Color(0xFF2563EB)),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _playTopicNow(item),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play Now'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _addTopicToQueue(item),
                  icon: const Icon(Icons.queue_rounded),
                  label: const Text('Add to Queue'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _showAddToPlaylistDialog(item),
                  icon: const Icon(Icons.playlist_add_rounded),
                  label: const Text('Add to Playlist'),
                ),
              ],
            ),
          ],
        ),
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
