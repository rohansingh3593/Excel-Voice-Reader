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

    final xlsioWorkbook = _buildSyncfusionWorkbook(decodedWorkbook, sheetNames);
    try {
      final rowsBySheet = <String, List<ExcelRowData>>{};
      final sheetErrors = <String, String>{};

      for (var index = 0; index < sheetNames.length; index++) {
        final sheetName = sheetNames[index];
        final worksheet = xlsioWorkbook.worksheets[index];
        try {
          rowsBySheet[sheetName] = _readSheetRows(worksheet);
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
    } finally {
      xlsioWorkbook.dispose();
    }
  }

  xlsio.Workbook _buildSyncfusionWorkbook(
    SpreadsheetDecoder decodedWorkbook,
    List<String> sheetNames,
  ) {
    final workbook = xlsio.Workbook(sheetNames.length);

    for (var sheetIndex = 0; sheetIndex < sheetNames.length; sheetIndex++) {
      final sheetName = sheetNames[sheetIndex];
      final worksheet = workbook.worksheets[sheetIndex];
      worksheet.name = sheetName;

      final decodedTable = decodedWorkbook.tables[sheetName];
      final decodedRows = decodedTable?.rows ?? const <List<dynamic>>[];
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

    return workbook;
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

  List<ExcelRowData> _readSheetRows(xlsio.Worksheet worksheet) {
    final firstRow = worksheet.getFirstRow();
    final lastRow = worksheet.getLastRow();
    final firstColumn = worksheet.getFirstColumn();
    final lastColumn = worksheet.getLastColumn();

    if (firstRow <= 0 || lastRow <= 0 || firstColumn <= 0 || lastColumn <= 0) {
      throw const FormatException(
        'This sheet is empty. Please select a sheet that contains keyword, topic, and content columns.',
      );
    }

    final headerRow = _findHeaderRow(
      worksheet,
      firstRow,
      lastRow,
      firstColumn,
      lastColumn,
    );
    if (headerRow == null) {
      throw const FormatException(
        'Could not find a header row. Expected columns named keyword, topic, and content.',
      );
    }

    final headers = <String, int>{};
    for (var column = firstColumn; column <= lastColumn; column++) {
      final normalizedHeader = _normalizeHeader(
        _cellText(worksheet, headerRow, column),
      );
      if (normalizedHeader.isNotEmpty &&
          !headers.containsKey(normalizedHeader)) {
        headers[normalizedHeader] = column;
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
    for (var rowIndex = headerRow + 1; rowIndex <= lastRow; rowIndex++) {
      final keyword = _cellText(worksheet, rowIndex, keywordIndex);
      final topic = _cellText(worksheet, rowIndex, topicIndex);
      final content = _cellText(worksheet, rowIndex, contentIndex);

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

  int? _findHeaderRow(
    xlsio.Worksheet worksheet,
    int firstRow,
    int lastRow,
    int firstColumn,
    int lastColumn,
  ) {
    for (var row = firstRow; row <= lastRow; row++) {
      final headersInRow = <String>{};
      for (var column = firstColumn; column <= lastColumn; column++) {
        final normalizedHeader = _normalizeHeader(
          _cellText(worksheet, row, column),
        );
        if (normalizedHeader.isNotEmpty) {
          headersInRow.add(normalizedHeader);
        }
      }

      if (_requiredColumns.every(headersInRow.contains)) {
        return row;
      }
    }

    return null;
  }

  String _cellText(xlsio.Worksheet worksheet, int row, int column) {
    final range = worksheet.getRangeByIndex(row, column);
    final displayText = range.displayText.trim();
    if (displayText.isNotEmpty) {
      return displayText;
    }

    final value = range.value;
    if (value == null) {
      return '';
    }

    return value.toString().trim();
  }

  String _normalizeHeader(String value) {
    return value.trim().toLowerCase();
  }
}
