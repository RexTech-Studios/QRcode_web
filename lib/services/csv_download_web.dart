import 'export_service.dart';

void downloadCsv({required String content, required String fileName}) {
  ExportService.downloadCsv(content: content, fileName: fileName);
}
