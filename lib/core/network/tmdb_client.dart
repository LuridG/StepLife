import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// TMDB 影片信息（搜索/详情合并）
class TmdbMovie {
  final int id;
  final String title;
  final String? releaseDate;
  final String? overview;
  final String? posterPath;
  final List<String> genres;
  final int? runtime; // 分钟
  final List<String> directors;
  final List<String> cast;
  final bool isTv; // true = 电视剧/综艺，false = 电影

  const TmdbMovie({
    required this.id,
    required this.title,
    this.releaseDate,
    this.overview,
    this.posterPath,
    this.genres = const [],
    this.runtime,
    this.directors = const [],
    this.cast = const [],
    this.isTv = false,
  });

  int? get year {
    if (releaseDate == null || releaseDate!.length < 4) return null;
    return int.tryParse(releaseDate!.substring(0, 4));
  }

  String get posterFullUrl =>
      posterPath == null ? '' : 'https://image.tmdb.org/t/p/w500$posterPath';
}

/// 极简 TMDB v3 客户端（可选接入，填 Key 才启用）
class TmdbClient {
  final String apiKey;
  final http.Client _client;

  TmdbClient(this.apiKey, {http.Client? client}) : _client = client ?? http.Client();

  /// v4 Read Access Token 以 eyJ 开头（JWT），需走 Bearer 头；
  /// 其余视为 v3 API Key（32 位十六进制），走 api_key 查询参数。
  bool get _useBearer => apiKey.startsWith('eyJ');

  Map<String, String> get _authHeaders =>
      _useBearer ? {'Authorization': 'Bearer $apiKey'} : const {};

  Map<String, String> get _authParams =>
      _useBearer ? const {} : {'api_key': apiKey};

  static const String _base = 'https://api.themoviedb.org/3';

  /// 搜索影片（中文优先）
  Future<List<TmdbMovie>> searchMovies(String query) async {
    final uri = Uri.parse('$_base/search/movie').replace(queryParameters: {
      ..._authParams,
      'query': query,
      'language': 'zh-CN',
      'include_adult': 'false',
      'page': '1',
    });
    final resp = await _client.get(uri, headers: _authHeaders);
    if (resp.statusCode != 200) {
      throw Exception('TMDB 搜索失败: HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final results = json['results'] as List? ?? [];
    return results
        .whereType<Map>()
        .map((e) => TmdbMovie(
              id: (e['id'] as num?)?.toInt() ?? 0,
              title: e['title'] as String? ?? e['name'] as String? ?? '',
              releaseDate: e['release_date'] as String?,
              overview: e['overview'] as String?,
              posterPath: e['poster_path'] as String?,
            ))
        .where((m) => m.id > 0)
        .toList();
  }

  /// 影片详情 + 演职员（导演/主演/类型/片长）
  Future<TmdbMovie> movieDetails(int id) async {
    final uri = Uri.parse('$_base/movie/$id').replace(queryParameters: {
      ..._authParams,
      'language': 'zh-CN',
      'append_to_response': 'credits',
    });
    final resp = await _client.get(uri, headers: _authHeaders);
    if (resp.statusCode != 200) {
      throw Exception('TMDB 详情失败: HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final credits = json['credits'] as Map<String, dynamic>? ?? {};
    final crew = credits['crew'] as List? ?? [];
    final cast = credits['cast'] as List? ?? [];
    final directors = crew
        .whereType<Map>()
        .where((c) => c['job'] == 'Director')
        .map((c) => c['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    final genres = (json['genres'] as List? ?? [])
        .whereType<Map>()
        .map((g) => g['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList();

    return TmdbMovie(
      id: id,
      title: json['title'] as String? ?? json['name'] as String? ?? '',
      releaseDate: json['release_date'] as String?,
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      genres: genres,
      runtime: (json['runtime'] as num?)?.toInt(),
      directors: directors,
      cast: cast
          .whereType<Map>()
          .take(5)
          .map((c) => c['name'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .toList(),
    );
  }

  /// 搜索电视剧/综艺（中文优先）
  Future<List<TmdbMovie>> searchTv(String query) async {
    final uri = Uri.parse('$_base/search/tv').replace(queryParameters: {
      ..._authParams,
      'query': query,
      'language': 'zh-CN',
      'include_adult': 'false',
      'page': '1',
    });
    final resp = await _client.get(uri, headers: _authHeaders);
    if (resp.statusCode != 200) {
      throw Exception('TMDB 电视剧搜索失败: HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final results = json['results'] as List? ?? [];
    return results
        .whereType<Map>()
        .map((e) => TmdbMovie(
              id: (e['id'] as num?)?.toInt() ?? 0,
              title: e['name'] as String? ?? e['original_name'] as String? ?? '',
              releaseDate: e['first_air_date'] as String?,
              overview: e['overview'] as String?,
              posterPath: e['poster_path'] as String?,
              isTv: true,
            ))
        .where((m) => m.id > 0)
        .toList();
  }

  /// 电视剧/综艺详情 + 演职员（导演/主演/类型/单集时长）
  Future<TmdbMovie> tvDetails(int id) async {
    final uri = Uri.parse('$_base/tv/$id').replace(queryParameters: {
      ..._authParams,
      'language': 'zh-CN',
      'append_to_response': 'credits',
    });
    final resp = await _client.get(uri, headers: _authHeaders);
    if (resp.statusCode != 200) {
      throw Exception('TMDB 电视剧详情失败: HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final credits = json['credits'] as Map<String, dynamic>? ?? {};
    final crew = credits['crew'] as List? ?? [];
    final cast = credits['cast'] as List? ?? [];
    final directors = crew
        .whereType<Map>()
        .where((c) => c['job'] == 'Director')
        .map((c) => c['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    final genres = (json['genres'] as List? ?? [])
        .whereType<Map>()
        .map((g) => g['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    // episode_run_time 是数组（可能多集时长），取第一个
    final runtimes = (json['episode_run_time'] as List? ?? [])
        .whereType<num>()
        .map((n) => n.toInt())
        .toList();

    return TmdbMovie(
      id: id,
      isTv: true,
      title: json['name'] as String? ?? json['original_name'] as String? ?? '',
      releaseDate: json['first_air_date'] as String?,
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      genres: genres,
      runtime: runtimes.isNotEmpty ? runtimes.first : null,
      directors: directors,
      cast: cast
          .whereType<Map>()
          .take(5)
          .map((c) => c['name'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .toList(),
    );
  }

  /// 从 TMDB 海报 URL 下载到本地缓存目录，返回本地路径
  Future<String> downloadPoster(String url, {required String cacheDir}) async {
    final resp = await _client.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw Exception('海报下载失败: HTTP ${resp.statusCode}');
    }
    final d = Directory(cacheDir);
    if (!await d.exists()) await d.create(recursive: true);
    final ext = url.contains('.png')
        ? '.png'
        : url.contains('.webp')
            ? '.webp'
            : '.jpg';
    final name = 'poster_${DateTime.now().millisecondsSinceEpoch}$ext';
    final path = '$cacheDir/$name';
    await File(path).writeAsBytes(resp.bodyBytes, flush: true);
    return path;
  }
}
