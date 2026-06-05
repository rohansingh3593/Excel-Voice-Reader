import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

class ExcelRowData {
  const ExcelRowData({
    required this.keyword,
    required this.topic,
    required this.content,
  });

  final String keyword;
  final String topic;
  final String content;
}

class ExcelWorkbookData {
  const ExcelWorkbookData({
    required this.fileName,
    required this.sheetNames,
    required this.rowsBySheet,
    required this.sheetErrors,
  });

  final String fileName;
  final List<String> sheetNames;
  final Map<String, List<ExcelRowData>> rowsBySheet;
  final Map<String, String> sheetErrors;
}

class ExcelService {
  const ExcelService();

  static const List<String> _requiredColumns = ['keyword', 'topic'];
  static const Map<String, String> _headerAliases = {
    'keyword': 'keyword',
    'key word': 'keyword',
    'topic': 'topic',
    'subject': 'topic',
    'content': 'content',
    'description': 'content',
    'text': 'content',
    'message': 'content',
  };

  Future<ExcelWorkbookData?> pickAndReadWorkbook() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xlsm'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final pickedFile = result.files.first;
    if (!_isXlsxFile(pickedFile)) {
      throw const FormatException(
          'Please choose a valid Excel file ending with .xlsx or .xlsm.');
    }

    final bytes = await _readPickedFile(pickedFile);
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException(
        'Unable to read this Excel file. File bytes are unavailable or empty.',
      );
    }

    if (!_isZipArchive(bytes)) {
      throw const FormatException(
        'Unable to open this Excel file. The selected file is not a valid .xlsx/.xlsm archive.',
      );
    }

    final SpreadsheetDecoder workbook;
    try {
      workbook = SpreadsheetDecoder.decodeBytes(bytes);
    } catch (error) {
      throw FormatException(
        'Unable to open this Excel file. ${error.runtimeType}: ${error.toString()}',
      );
    }

    final sheetNames = workbook.tables.keys.toList(growable: false);
    final rowsBySheet = <String, List<ExcelRowData>>{};
    final sheetErrors = <String, String>{};

    for (final sheetName in sheetNames) {
      final sheet = workbook.tables[sheetName];
      if (sheet == null) {
        continue;
      }

      try {
        rowsBySheet[sheetName] = _readSheetRows(sheet.rows);
      } on FormatException catch (error) {
        sheetErrors[sheetName] = error.message;
      }
    }

    return ExcelWorkbookData(
      fileName: pickedFile.name,
      sheetNames: sheetNames,
      rowsBySheet: rowsBySheet,
      sheetErrors: sheetErrors,
    );
  }

  bool _isXlsxFile(PlatformFile pickedFile) {
    final extension = pickedFile.extension?.toLowerCase();
    if (extension != null && extension.isNotEmpty) {
      return extension == 'xlsx' || extension == 'xlsm';
    }

    final lowerName = pickedFile.name.toLowerCase();
    return lowerName.endsWith('.xlsx') || lowerName.endsWith('.xlsm');
  }

  Future<Uint8List?> _readPickedFile(PlatformFile pickedFile) async {
    final fileBytes = pickedFile.bytes;
    if (fileBytes != null && fileBytes.isNotEmpty) {
      return fileBytes;
    }

    final path = pickedFile.path;
    if (path != null) {
      try {
        final fileBytes = await File(path).readAsBytes();
        if (fileBytes.isNotEmpty) {
          return fileBytes;
        }
      } on FileSystemException catch (error) {
        debugPrint('Failed reading Excel file from path: $error');
      }
    }

    return null;
  }

  bool _isZipArchive(Uint8List bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
  }

  List<ExcelRowData> _readSheetRows(List<List> rows) {
    final headerIndex = rows.indexWhere((row) {
      return row
          .map((cell) => _normalizeHeader(_cellText(cell)))
          .any(_requiredColumns.contains);
    });
    if (headerIndex == -1) {
      return const [];
    }

    final headers = <String, int>{};
    for (var index = 0; index < rows[headerIndex].length; index++) {
      final normalizedHeader = _normalizeHeader(
        _cellText(rows[headerIndex][index]),
      );
      if (normalizedHeader.isNotEmpty) {
        headers[normalizedHeader] = index;
      }
    }

    final missingColumns = _requiredColumns
        .where((column) => !headers.containsKey(column))
        .toList(growable: false);
    if (missingColumns.isNotEmpty) {
      throw FormatException(
        'Missing required column(s): ${missingColumns.join(', ')}. Expected keyword and topic.',
      );
    }

    final keywordIndex = headers['keyword']!;
    final topicIndex = headers['topic']!;

    final contentIndices = <int>[];
    if (headers.containsKey('content')) {
      contentIndices.add(headers['content']!);
    } else {
      contentIndices.addAll(headers.entries
          .where((entry) => _isContentLikeHeader(entry.key))
          .map((entry) => entry.value));
    }

    if (contentIndices.isEmpty) {
      throw const FormatException(
        'Missing required content column. Expected content, description, text, message, or a value-style column like file1_value.',
      );
    }

    final parsedRows = <ExcelRowData>[];
    for (final row in rows.skip(headerIndex + 1)) {
      final keyword = _valueForColumn(row, keywordIndex);
      final topic = _valueForColumn(row, topicIndex);
      final content = contentIndices
          .map((index) => _valueForColumn(row, index))
          .where((value) => value.isNotEmpty)
          .join(' | ');

      if (keyword.isEmpty && topic.isEmpty && content.isEmpty) {
        continue;
      }

      parsedRows.add(
        ExcelRowData(keyword: keyword, topic: topic, content: content),
      );
    }

    return parsedRows;
  }

  String _valueForColumn(List row, int columnIndex) {
    if (columnIndex >= row.length) {
      return '';
    }

    return _cellText(row[columnIndex]).trim();
  }

  String _cellText(dynamic cell) {
    if (cell == null) {
      return '';
    }

    return cell.toString();
  }

  bool _isContentLikeHeader(String normalizedHeader) {
    return normalizedHeader == 'content' ||
        normalizedHeader.contains('value') ||
        normalizedHeader.contains('file') ||
        normalizedHeader.contains('text');
  }

  String _normalizeHeader(String value) {
    var cleaned = value.replaceAll(
      RegExp(r'[\u0000-\u001F\u007F\u00A0\uFEFF]'),
      ' ',
    );
    cleaned = cleaned.toLowerCase().trim();
    cleaned = cleaned.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    return _headerAliases[cleaned] ?? cleaned;
  }
}
