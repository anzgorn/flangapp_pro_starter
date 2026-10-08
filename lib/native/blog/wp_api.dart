import 'package:dio/dio.dart';

import '../native_config.dart';
import '../shop/shop_models.dart' show decodeText, toInt;

class BlogException implements Exception {
  final String message;
  BlogException(this.message);

  @override
  String toString() => message;
}

class BlogCategory {
  final int id;
  final String name;
  final int count;
  final int parent;
  const BlogCategory({required this.id, required this.name, required this.count, required this.parent});
}

class BlogPost {
  final int id;
  final String title;
  final DateTime? date;
  final String link;
  /// Plain-text summary for lists.
  final String excerpt;
  final String image;
  final String author;
  /// Full HTML, loaded on the post screen.
  final String content;

  const BlogPost({
    required this.id,
    required this.title,
    this.date,
    required this.link,
    this.excerpt = '',
    this.image = '',
    this.author = '',
    this.content = '',
  });
}

/// One page of posts + the next page number (null = the last page).
class BlogPage {
  final List<BlogPost> posts;
  final int? next;
  const BlogPage(this.posts, this.next);
}

/// WordPress REST API (public, read-only): posts with their featured images,
/// categories and search.
class WpApi {
  final NativeConfig config;
  final Dio _dio;

  WpApi(this.config)
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          headers: {'Accept': 'application/json'},
          validateStatus: (_) => true,
        ));

  static const _pageSize = 10;
  static const _listFields = 'id,date,link,title,excerpt,_links,_embedded';

  /// A route on the WordPress REST root (pretty or ?rest_route= permalinks).
  String _url(String route, Map<String, dynamic> query) {
    final base = config.apiBase;
    final params = query.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent('${e.value}')}').join('&');
    if (base.contains('rest_route=')) {
      final url = base.replaceFirst(RegExp(r'rest_route=[^&]*'), 'rest_route=/wp/v2/$route');
      return params.isEmpty ? url : '$url&$params';
    }
    final url = '${base.replaceFirst(RegExp(r'/+$'), '')}/wp/v2/$route';
    return params.isEmpty ? url : '$url?$params';
  }

  Future<Response> _get(String route, Map<String, dynamic> query) async {
    final res = await _dio.get(_url(route, query));
    final status = res.statusCode ?? 0;
    if (status >= 400 || status == 0) {
      final data = res.data;
      throw BlogException(data is Map && data['message'] != null ? decodeText(data['message']) : 'The site did not answer (HTTP $status).');
    }
    return res;
  }

  Future<List<BlogCategory>> categories() async {
    final res = await _get('categories', {'per_page': 100, 'orderby': 'count', 'order': 'desc', 'hide_empty': 'true', '_fields': 'id,name,count,parent'});
    final list = res.data is List ? res.data as List : [];
    // Biggest first, whatever order the site (or its cache) answers in.
    return [
      for (final c in list)
        if (c is Map) BlogCategory(id: toInt(c['id']), name: decodeText(c['name']), count: toInt(c['count']), parent: toInt(c['parent']))
    ]..sort((a, b) => b.count.compareTo(a.count));
  }

  Future<BlogPage> posts({int page = 1, int? category, String search = ''}) async {
    final res = await _get('posts', {
      'page': page,
      'per_page': _pageSize,
      '_embed': 'wp:featuredmedia,author',
      '_fields': _listFields,
      if (category != null) 'categories': category,
      if (search.isNotEmpty) 'search': search,
    });
    final list = res.data is List ? res.data as List : [];
    final pages = int.tryParse(res.headers.value('x-wp-totalpages') ?? '') ?? 1;
    return BlogPage([for (final p in list) if (p is Map) _post(p)], page < pages ? page + 1 : null);
  }

  Future<BlogPost> post(int id) async {
    final res = await _get('posts/$id', {'_embed': 'wp:featuredmedia,author', '_fields': '$_listFields,content'});
    if (res.data is! Map) throw BlogException('Post not found.');
    return _post(res.data as Map);
  }

  BlogPost _post(Map json) {
    final embedded = json['_embedded'] is Map ? json['_embedded'] as Map : {};
    var image = '';
    final media = embedded['wp:featuredmedia'];
    if (media is List && media.isNotEmpty && media.first is Map) {
      final m = media.first as Map;
      final sizes = m['media_details'] is Map ? (m['media_details'] as Map)['sizes'] : null;
      for (final size in ['medium_large', 'large', 'full']) {
        if (sizes is Map && sizes[size] is Map && sizes[size]['source_url'] != null) {
          image = sizes[size]['source_url'].toString();
          break;
        }
      }
      if (image.isEmpty && m['source_url'] != null) image = m['source_url'].toString();
    }
    final authors = embedded['author'];
    final author = authors is List && authors.isNotEmpty && authors.first is Map ? decodeText(authors.first['name']) : '';
    return BlogPost(
      id: toInt(json['id']),
      title: decodeText(json['title'] is Map ? json['title']['rendered'] : json['title']),
      date: DateTime.tryParse((json['date'] ?? '').toString()),
      link: (json['link'] ?? '').toString(),
      excerpt: decodeText(json['excerpt'] is Map ? json['excerpt']['rendered'] : ''),
      image: image,
      author: author,
      content: json['content'] is Map ? (json['content']['rendered'] ?? '').toString() : '',
    );
  }
}
