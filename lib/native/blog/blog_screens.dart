import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/app_config.dart';
import '../native_config.dart';
import '../native_ui.dart';
import '../site_page.dart';
import 'wp_api.dart';

/// Bottom tab positions of the WordPress app.
class BlogTabs {
  static const home = 0;
  static const categories = 1;
  static const search = 2;
  static const more = 3;
}

/// Everything the WordPress screens share.
class BlogScope {
  final AppConfig app;
  final NativeConfig native;
  final WpApi api;
  final NativeColors colors;

  BlogScope({required this.app, required this.native, required this.api, required this.colors});

  String t(String key, String fallback) => native.text(key, fallback);

  /// Open a screen over the tabs, in the app's colours.
  Future<T?> push<T>(BuildContext context, Widget page) {
    return Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => Theme(data: colors.theme(), child: page)));
  }

  void openPost(BuildContext context, BlogPost post) => push(context, BlogPostScreen(scope: this, post: post));

  void openCategory(BuildContext context, BlogCategory category, List<BlogCategory> all) =>
      push(context, BlogFeedScreen(scope: this, category: category, all: all));

  void openSite(BuildContext context, String url, String title) =>
      push(context, SitePage(appConfig: app, url: url, title: title));
}

String formatDate(DateTime? date) {
  if (date == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year}';
}

/// Pages of posts that load as the list scrolls.
class PostPager extends ChangeNotifier {
  final Future<BlogPage> Function(int page) fetch;

  final List<BlogPost> items = [];
  int? _next = 1;
  bool loading = false;
  String? error;

  PostPager(this.fetch);

  bool get done => _next == null;
  bool get firstLoad => loading && items.isEmpty;

  Future<void> reload() async {
    items.clear();
    _next = 1;
    error = null;
    await more();
  }

  Future<void> more() async {
    if (loading || done) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await fetch(_next!);
      _next = page.next;
      items.addAll(page.posts);
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

class PostCard extends StatelessWidget {
  final BlogScope scope;
  final BlogPost post;

  const PostCard({super.key, required this.scope, required this.post});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => scope.openPost(context, post),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (post.image.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(aspectRatio: 16 / 9, child: NetImage(post.image)),
                ),
              ),
            Text(post.title, maxLines: 3, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.3)),
            const SizedBox(height: 4),
            Text(formatDate(post.date), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            if (post.excerpt.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(post.excerpt, maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, height: 1.4, color: Colors.grey.shade800)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A list of posts for a CustomScrollView, fed by a PostPager.
class PostListSliver extends StatelessWidget {
  final BlogScope scope;
  final PostPager pager;

  const PostListSliver({super.key, required this.scope, required this.pager});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: pager,
      builder: (context, _) {
        if (pager.firstLoad) {
          return const SliverFillRemaining(hasScrollBody: false, child: Padding(padding: EdgeInsets.all(48), child: LoadingView()));
        }
        if (pager.items.isEmpty && pager.error != null) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorView(message: pager.error!, retryLabel: scope.t('retry', 'Try again'), onRetry: pager.reload),
          );
        }
        if (pager.items.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyView(icon: Icons.article_outlined, message: scope.t('no_posts', 'No posts here yet')),
          );
        }
        // A centred column on tablets; full width on phones.
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              if (i == pager.items.length) return const Padding(padding: EdgeInsets.all(16), child: LoadingView());
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(children: [PostCard(scope: scope, post: pager.items[i]), const Divider(height: 1, indent: 16, endIndent: 16)]),
                ),
              );
            },
            childCount: pager.items.length + (pager.loading ? 1 : 0),
          ),
        );
      },
    );
  }
}

bool loadMorePosts(ScrollNotification n, PostPager pager) {
  if (n.metrics.pixels > n.metrics.maxScrollExtent - 800) pager.more();
  return false;
}

/// Home tab: category chips + the latest posts.
class BlogHomeScreen extends StatefulWidget {
  final BlogScope scope;
  final VoidCallback onSearch;
  const BlogHomeScreen({super.key, required this.scope, required this.onSearch});

  @override
  State<BlogHomeScreen> createState() => _BlogHomeScreenState();
}

class _BlogHomeScreenState extends State<BlogHomeScreen> with AutomaticKeepAliveClientMixin {
  late final PostPager pager;
  List<BlogCategory> all = [];
  List<BlogCategory> chips = [];

  BlogScope get scope => widget.scope;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    pager = PostPager((page) => scope.api.posts(page: page));
    _load();
  }

  Future<void> _load() async {
    // `settings.home.categories` (set by Flangapp AI): these ids, in this order;
    // none → the 10 biggest top-level categories.
    final home = scope.native.settings['home'];
    final chosen = home is Map && home['categories'] is List ? [for (final id in home['categories'] as List) '$id'] : <String>[];
    scope.api.categories().then((list) {
      final byId = {for (final c in list) '${c.id}': c};
      final shown = chosen.isNotEmpty
          ? [for (final id in chosen) if (byId[id] != null) byId[id]!]
          : list.where((c) => c.parent == 0 && c.count > 0).take(10).toList();
      if (mounted) {
        setState(() {
          all = list;
          chips = shown;
        });
      }
    }).catchError((_) {});
    await pager.reload();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(scope.app.appName),
        actions: [IconButton(icon: const Icon(Icons.search), onPressed: widget.onSearch)],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) => loadMorePosts(n, pager),
          child: CustomScrollView(
            slivers: [
              if (chips.isNotEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 52,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      itemCount: chips.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) => ActionChip(
                        label: Text(chips[i].name),
                        onPressed: () => scope.openCategory(context, chips[i], all),
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(scope.t('latest', 'Latest'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ),
              ),
              PostListSliver(scope: scope, pager: pager),
            ],
          ),
        ),
      ),
    );
  }
}

/// Categories tab.
class BlogCategoriesScreen extends StatefulWidget {
  final BlogScope scope;
  const BlogCategoriesScreen({super.key, required this.scope});

  @override
  State<BlogCategoriesScreen> createState() => _BlogCategoriesScreenState();
}

class _BlogCategoriesScreenState extends State<BlogCategoriesScreen> with AutomaticKeepAliveClientMixin {
  List<BlogCategory>? all;
  String? error;

  BlogScope get scope => widget.scope;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      final list = await scope.api.categories();
      if (mounted) setState(() => all = list);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final top = (all ?? []).where((c) => c.parent == 0 && c.count > 0).toList();
    return Scaffold(
      appBar: AppBar(title: Text(scope.t('categories', 'Categories'))),
      body: error != null
          ? ErrorView(message: error!, retryLabel: scope.t('retry', 'Try again'), onRetry: _load)
          : all == null
              ? const LoadingView()
              : top.isEmpty
                  ? EmptyView(icon: Icons.category_outlined, message: scope.t('no_categories', 'No categories yet'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: top.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
                        itemBuilder: (context, i) => ListTile(
                          title: Text(top[i].name, style: const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: Text('${top[i].count} ${scope.t('posts', 'posts')}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => scope.openCategory(context, top[i], all!),
                        ),
                      ),
                    ),
    );
  }
}

/// Posts of one category, with its sub-categories on top.
class BlogFeedScreen extends StatefulWidget {
  final BlogScope scope;
  final BlogCategory category;
  final List<BlogCategory> all;

  const BlogFeedScreen({super.key, required this.scope, required this.category, required this.all});

  @override
  State<BlogFeedScreen> createState() => _BlogFeedScreenState();
}

class _BlogFeedScreenState extends State<BlogFeedScreen> {
  late final PostPager pager;

  @override
  void initState() {
    super.initState();
    pager = PostPager((page) => widget.scope.api.posts(page: page, category: widget.category.id));
    pager.reload();
  }

  @override
  Widget build(BuildContext context) {
    final children = widget.all.where((c) => c.parent == widget.category.id && c.count > 0).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.category.name)),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) => loadMorePosts(n, pager),
        child: CustomScrollView(
          slivers: [
            if (children.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in children)
                        ActionChip(label: Text(c.name), onPressed: () => widget.scope.openCategory(context, c, widget.all)),
                    ],
                  ),
                ),
              ),
            PostListSliver(scope: widget.scope, pager: pager),
          ],
        ),
      ),
    );
  }
}

class BlogPostScreen extends StatefulWidget {
  final BlogScope scope;
  /// From a list: shown at once, then completed with the full text.
  final BlogPost post;

  const BlogPostScreen({super.key, required this.scope, required this.post});

  @override
  State<BlogPostScreen> createState() => _BlogPostScreenState();
}

class _BlogPostScreenState extends State<BlogPostScreen> {
  late BlogPost post = widget.post;
  String? error;

  BlogScope get scope => widget.scope;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      final full = await scope.api.post(post.id);
      if (mounted) setState(() => post = full);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = [formatDate(post.date), if (post.author.isNotEmpty) post.author].where((s) => s.isNotEmpty).join(' · ');
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: scope.t('share', 'Share'),
            onPressed: () => Share.share('${post.title} ${post.link}'),
          ),
          IconButton(
            icon: const Icon(Icons.public),
            tooltip: scope.t('open_on_site', 'Open on the site'),
            onPressed: () => scope.openSite(context, post.link, post.title),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (post.image.isNotEmpty) AspectRatio(aspectRatio: 16 / 9, child: NetImage(post.image)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(post.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.3)),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(meta, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                        ],
                        const SizedBox(height: 16),
                        if (post.content.isNotEmpty)
                          HtmlWidget(
                            post.content,
                            textStyle: TextStyle(fontSize: 16, height: 1.55, color: Colors.grey.shade900),
                            onTapUrl: (url) {
                              scope.openSite(context, url, post.title);
                              return true;
                            },
                          )
                        else if (error != null)
                          ErrorView(message: error!, retryLabel: scope.t('retry', 'Try again'), onRetry: _load)
                        else
                          const Padding(padding: EdgeInsets.all(32), child: LoadingView()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Search tab.
class BlogSearchScreen extends StatefulWidget {
  final BlogScope scope;
  const BlogSearchScreen({super.key, required this.scope});

  @override
  State<BlogSearchScreen> createState() => _BlogSearchScreenState();
}

class _BlogSearchScreenState extends State<BlogSearchScreen> with AutomaticKeepAliveClientMixin {
  String query = '';
  PostPager? pager;

  BlogScope get scope => widget.scope;

  @override
  bool get wantKeepAlive => true;

  void _search(String text) {
    final q = text.trim();
    if (q.isEmpty) return;
    setState(() {
      query = q;
      pager = PostPager((page) => scope.api.posts(page: page, search: q));
    });
    pager!.reload();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final onBar = Theme.of(context).appBarTheme.foregroundColor;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          style: TextStyle(color: onBar),
          cursorColor: onBar,
          decoration: InputDecoration(
            hintText: scope.t('search_hint', 'Search'),
            hintStyle: TextStyle(color: onBar?.withValues(alpha: 0.6)),
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search, color: onBar),
          ),
        ),
      ),
      body: pager == null
          ? EmptyView(icon: Icons.search, message: scope.t('search_prompt', 'Type what you are looking for'))
          : NotificationListener<ScrollNotification>(
              onNotification: (n) => loadMorePosts(n, pager!),
              child: CustomScrollView(slivers: [PostListSliver(key: ValueKey(query), scope: scope, pager: pager!)]),
            ),
    );
  }
}
