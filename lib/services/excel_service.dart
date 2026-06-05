import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

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

  static const List<String> _requiredColumns = ['keyword', 'topic', 'content'];
  static const Map<String, String> _headerAliases = {
    'keyword': 'keyword',
    'key word': 'keyword',
    'keywords': 'keyword',
    'topic': 'topic',
    'topics': 'topic',
    'subject': 'topic',
    'content': 'content',
    'contents': 'content',
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
        'Please choose a valid Excel file ending with .xlsx or .xlsm.',
      );
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

    final SpreadsheetDecoder decodedWorkbook;
    try {
      decodedWorkbook = SpreadsheetDecoder.decodeBytes(bytes);
    } catch (error) {
      throw FormatException(
        'Unable to open this Excel file. Please choose a valid .xlsx or .xlsm workbook.',
      );
    }

    final sheetNames = decodedWorkbook.tables.keys.toList(growable: false);
    if (sheetNames.isEmpty) {
      throw const FormatException(
        'This Excel file is empty. Please choose a workbook with at least one sheet.',
      );
    }

    _warmUpSyncfusionWorkbook(decodedWorkbook, sheetNames);

    final rowsBySheet = <String, List<ExcelRowData>>{};
    final sheetErrors = <String, String>{};

    for (final sheetName in sheetNames) {
      final decodedTable = decodedWorkbook.tables[sheetName];
      if (decodedTable == null) {
        sheetErrors[sheetName] = 'This sheet could not be found in the workbook.';
        continue;
      }

      try {
        rowsBySheet[sheetName] = _readSheetRows(decodedTable.rows);
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

  void _warmUpSyncfusionWorkbook(
    SpreadsheetDecoder decodedWorkbook,
    List<String> sheetNames,
  ) {
    xlsio.Workbook? workbook;
    try {
      workbook = xlsio.Workbook(sheetNames.length);
      for (var sheetIndex = 0; sheetIndex < sheetNames.length; sheetIndex++) {
        final sheetName = sheetNames[sheetIndex];
        final worksheet = workbook.worksheets[sheetIndex];
        worksheet.name = sheetName;

        final decodedTable = decodedWorkbook.tables[sheetName];
        final decodedRows = decodedTable?.rows ?? const <List>[];
        for (var rowIndex = 0; rowIndex < decodedRows.length; rowIndex++) {
          final row = decodedRows[rowIndex];
          for (var columnIndex = 0; columnIndex < row.length; columnIndex++) {
            final cellValue = row[columnIndex];
            if (cellValue == null) {
              continue;
            }
            worksheet
                .getRangeByIndex(rowIndex + 1, columnIndex + 1)
                .setValue(cellValue);
          }
        }
      }
    } catch (error) {
      debugPrint('Syncfusion workbook staging skipped: $error');
    } finally {
      workbook?.dispose();
    }
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
    if (rows.isEmpty) {
      throw const FormatException(
        'This sheet is empty. Please select a sheet that contains keyword, topic, and content columns.',
      );
    }

    final headerIndex = _findHeaderIndex(rows);
    if (headerIndex == null) {
      final detectedHeaders = _detectedHeaderPreview(rows);
      final suffix = detectedHeaders.isEmpty
          ? ''
          : ' Detected possible headers: ${detectedHeaders.join(', ')}.';
      throw FormatException(
        'Could not find a header row. Expected columns named keyword, topic, and content.$suffix',
      );
    }

    final headers = <String, int>{};
    final headerRow = rows[headerIndex];
    for (var columnIndex = 0; columnIndex < headerRow.length; columnIndex++) {
      final normalizedHeader = _normalizeHeader(
        _cellText(headerRow[columnIndex]),
      );
      if (normalizedHeader.isNotEmpty &&
          !headers.containsKey(normalizedHeader)) {
        headers[normalizedHeader] = columnIndex;
      }
    }

    final missingColumns = _requiredColumns
        .where((column) => !headers.containsKey(column))
        .toList(growable: false);
    if (missingColumns.isNotEmpty) {
      throw FormatException(
        'Missing required column(s): ${missingColumns.join(', ')}. Expected keyword, topic, and content headers.',
      );
    }

    final keywordIndex = headers['keyword'];
    final topicIndex = headers['topic'];
    final contentIndex = headers['content'];
    if (keywordIndex == null || topicIndex == null || contentIndex == null) {
      throw const FormatException(
        'Missing required column(s). Expected keyword, topic, and content headers.',
      );
    }

    final parsedRows = <ExcelRowData>[];
    for (final row in rows.skip(headerIndex + 1)) {
      final keyword = _valueForColumn(row, keywordIndex);
      final topic = _valueForColumn(row, topicIndex);
      final content = _valueForColumn(row, contentIndex);

      if (keyword.isEmpty && topic.isEmpty && content.isEmpty) {
        continue;
      }

      if (keyword.isEmpty) {
        continue;
      }

      parsedRows.add(ExcelRowData(
        keyword: keyword,
        topic: topic,
        content: content,
      ));
    }

    if (parsedRows.isEmpty) {
      throw const FormatException(
        'This sheet has the required columns, but no keyword rows were found.',
      );
    }

    return parsedRows;
  }

  int? _findHeaderIndex(List<List> rows) {
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final headersInRow = rows[rowIndex]
          .map((cell) => _normalizeHeader(_cellText(cell)))
          .where((header) => header.isNotEmpty)
          .toSet();

      if (_requiredColumns.every(headersInRow.contains)) {
        return rowIndex;
      }
    }

    return null;
  }

  List<String> _detectedHeaderPreview(List<List> rows) {
    final detected = <String>{};
    for (final row in rows.take(10)) {
      for (final cell in row) {
        final normalizedHeader = _normalizeHeader(_cellText(cell));
        if (normalizedHeader.isNotEmpty) {
          detected.add(normalizedHeader);
        }
      }
      if (detected.length >= 8) {
        break;
      }
    }

    return detected.take(8).toList(growable: false);
  }

  String _valueForColumn(List row, int columnIndex) {
    if (columnIndex >= row.length) {
      return '';
    }

    return _cellText(row[columnIndex]);
  }

  String _cellText(dynamic cell) {
    if (cell == null) {
      return '';
    }

    return cell.toString().trim();
  }

  String _normalizeHeader(String value) {
    var cleaned = value.replaceAll(
      RegExp(r'[\u0000-\u001F\u007F\u00A0\uFEFF]'),
      ' ',
    );
    cleaned = cleaned.toLowerCase().trim();
    cleaned = cleaned.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    return _headerAliases[cleaned] ?? cleaned;
  }
}
