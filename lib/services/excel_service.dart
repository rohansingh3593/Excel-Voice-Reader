import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

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
  static const List<String> _requiredColumns = ['keyword', 'topic', 'content'];

  Future<ExcelWorkbookData?> pickAndReadWorkbook() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final pickedFile = result.files.first;
    if (!_isXlsxFile(pickedFile)) {
      throw const FormatException('Please choose a valid .xlsx file.');
    }

    final bytes = await _readPickedFile(pickedFile);
    if (bytes == null) {
      throw const FormatException('Unable to read this Excel file.');
    }

    final Excel workbook;
    try {
      workbook = Excel.decodeBytes(bytes);
    } catch (_) {
      throw const FormatException(
        'Unable to open this Excel file. Please choose a valid .xlsx file.',
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
      return extension == 'xlsx';
    }

    return pickedFile.name.toLowerCase().endsWith('.xlsx');
  }

  Future<Uint8List?> _readPickedFile(PlatformFile pickedFile) async {
    final fileBytes = pickedFile.bytes;
    if (fileBytes != null) {
      return fileBytes;
    }

    final path = pickedFile.path;
    if (path != null) {
      try {
        return await File(path).readAsBytes();
      } on FileSystemException {
        return null;
      }
    }

    return null;
  }

  List<ExcelRowData> _readSheetRows(List<List<Data?>> rows) {
    final headerIndex = rows.indexWhere(_rowHasAnyValue);
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
        'Missing required column(s): ${missingColumns.join(', ')}. Expected keyword, topic, and content.',
      );
    }

    final parsedRows = <ExcelRowData>[];
    for (final row in rows.skip(headerIndex + 1)) {
      final keyword = _valueForColumn(row, headers['keyword']!);
      final topic = _valueForColumn(row, headers['topic']!);
      final content = _valueForColumn(row, headers['content']!);

      if (keyword.isEmpty && topic.isEmpty && content.isEmpty) {
        continue;
      }

      parsedRows.add(
        ExcelRowData(keyword: keyword, topic: topic, content: content),
      );
    }

    return parsedRows;
  }

  bool _rowHasAnyValue(List<Data?> row) {
    return row.any((cell) => _cellText(cell).trim().isNotEmpty);
  }

  String _valueForColumn(List<Data?> row, int columnIndex) {
    if (columnIndex >= row.length) {
      return '';
    }

    return _cellText(row[columnIndex]).trim();
  }

  String _cellText(Data? cell) {
    final value = cell?.value;
    if (value == null) {
      return '';
    }

    return value.toString();
  }

  String _normalizeHeader(String value) {
    return value.trim().toLowerCase();
  }
}
