import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// 远端文件信息
class RemoteFileInfo {
  final String path;
  final int length;
  final String? mtime;

  const RemoteFileInfo({required this.path, required this.length, this.mtime});
}

/// 轻量 WebDAV 客户端（MKCOL / PUT / GET / PROPFIND），
/// 用于坚果云 / Nextcloud / NAS 的手动备份与恢复。
class WebDavService {
  final String baseUrl; // 例如 https://dav.jianguoyun.com/dav
  final String username;
  final String password;
  final String prefix; // 例如 /steplife
  final bool allowSelfSigned;

  WebDavService({
    required this.baseUrl,
    required this.username,
    required this.password,
    this.prefix = '/steplife',
    this.allowSelfSigned = false,
  });

  http.Client _createClient() {
    if (!allowSelfSigned) return http.Client();
    final io = HttpClient()
      ..badCertificateCallback = ((cert, host, port) => true);
    return IOClient(io);
  }

  Map<String, String> _headers({String? contentType}) {
    final auth = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
    return {
      'Authorization': auth,
      'Content-Type': ?contentType,
    };
  }

  String _join(String a, String b) {
    final left = a.endsWith('/') ? a.substring(0, a.length - 1) : a;
    final right = b.startsWith('/') ? b : '/$b';
    return left + right;
  }

  Uri _url(String remotePath) => Uri.parse(_join(baseUrl, _join(prefix, remotePath)));

  /// 确保远程目录存在（逐级 MKCOL，已存在忽略错误）
  Future<void> ensureRemoteDirs() async {
    for (final rel in ['', '/db', '/images']) {
      final uri = _url(rel == '' ? '' : rel);
      final req = http.Request('MKCOL', uri);
      req.headers.addAll(_headers());
      final streamed = await _createClient().send(req);
      await streamed.stream.drain<void>();
      // 201 创建成功；405/301/409 表示已存在，均可接受
    }
  }

  /// 上传本地文件到远端（返回是否成功）
  Future<bool> uploadFile(String localPath, String remoteRelPath) async {
    final file = File(localPath);
    if (!await file.exists()) return false;
    final bytes = await file.readAsBytes();
    return uploadBytes(bytes, remoteRelPath);
  }

  Future<bool> uploadBytes(List<int> bytes, String remoteRelPath) async {
    final client = _createClient();
    try {
      final resp = await client.put(
        _url(remoteRelPath),
        headers: _headers(contentType: 'application/octet-stream'),
        body: bytes,
      );
      return resp.statusCode == 200 ||
          resp.statusCode == 201 ||
          resp.statusCode == 204;
    } finally {
      client.close();
    }
  }

  /// 下载远端文件到本地
  Future<bool> downloadFile(String remoteRelPath, String localPath) async {
    final client = _createClient();
    try {
      final resp = await client.get(_url(remoteRelPath), headers: _headers());
      if (resp.statusCode != 200) return false;
      final file = File(localPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(resp.bodyBytes, flush: true);
      return true;
    } finally {
      client.close();
    }
  }

  /// PROPFIND 列出远端目录下的文件信息（含子目录深度 1）
  Future<List<RemoteFileInfo>> listFiles(String remoteDirRel) async {
    final client = _createClient();
    try {
      final req = http.Request('PROPFIND', _url(remoteDirRel));
      req.headers.addAll(_headers(contentType: 'application/xml'));
      req.headers['Depth'] = '1';
      final reqBody = '''
<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:getcontentlength/>
    <d:getlastmodified/>
    <d:resourcetype/>
  </d:prop>
</d:propfind>''';
      req.body = reqBody;
      final streamed = await client.send(req);
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode != 207 && resp.statusCode != 200) {
        return [];
      }
      return _parsePropfind(resp.body);
    } finally {
      client.close();
    }
  }

  List<RemoteFileInfo> _parsePropfind(String xml) {
    final result = <RemoteFileInfo>[];
    // 极简 XML 解析：按 <response> 块提取 href / getcontentlength / getlastmodified
    final responseBlocks = RegExp(r'<d:response>(.*?)</d:response>', dotAll: true)
        .allMatches(xml)
        .map((m) => m.group(1) ?? '')
        .toList();
    for (final block in responseBlocks) {
      final hrefMatch = RegExp(r'<d:href>(.*?)</d:href>', dotAll: true).firstMatch(block);
      if (hrefMatch == null) continue;
      final href = hrefMatch.group(1)!.trim();
      final isCollection = block.contains('<d:collection/>');
      if (isCollection) continue;
      final lenMatch =
          RegExp(r'<d:getcontentlength>(\d+)</d:getcontentlength>').firstMatch(block);
      final mtimeMatch =
          RegExp(r'<d:getlastmodified>(.*?)</d:getlastmodified>', dotAll: true)
              .firstMatch(block);
      result.add(RemoteFileInfo(
        path: Uri.decodeComponent(href.split('/').last),
        length: int.tryParse(lenMatch?.group(1) ?? '') ?? 0,
        mtime: mtimeMatch?.group(1)?.trim(),
      ));
    }
    return result;
  }
}
