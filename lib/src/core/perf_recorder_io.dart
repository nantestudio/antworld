import 'dart:io';

void writeToLogFile(String filename, String line) {
  final file = File('${Directory.systemTemp.path}/$filename');
  file.writeAsStringSync('$line\n', mode: FileMode.append);
}

String getLogPath(String filename) => '${Directory.systemTemp.path}/$filename';
