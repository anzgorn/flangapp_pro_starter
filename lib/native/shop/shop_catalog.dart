import 'package:flutter/material.dart';

import '../native_ui.dart';
import 'shop_api.dart';
import 'shop_models.dart';
import 'shop_widgets.dart';

/// Sort orders offered on product lists: text key, English label, order.
const _sorts = [
  ['sort_popular', 'Popular', ShopSort.popular],
  ['sort_new', 'Newest', ShopSort.newest],
  ['sort_price_low', 'Price: low to high', ShopSort.priceLow],
  ['sort_price_high', 'Price: high to low', ShopSort.priceHigh],
];

/// `settings.home.sort` from the panel: popular | newest | price_low | price_high
/// (WooCommerce names popularity / date / price are understood too).
int _sortFromSettings(dynamic value) {
  switch (value) {
    case 'newest':
    case 'date':
      return 1;
    case 'price_low':
    case 'price':
      return 2;
    case 'price_high':
      return 3;
    default:
      return 0;
  }
}

/// Shop tab: categories strip + all products.
class ShopHomeScreen extends StatefulWidget {
  final ShopScope scope;
  const ShopHomeScreen({super.key, required this.scope});

  @override
  State<ShopHomeScreen> createState() => _ShopHomeScreenState();
}

class _ShopHomeScreenState extends State<ShopHomeScreen> with AutomaticKeepAliveClientMixin {
  late final ProductPager pager;
  List<ShopCategory> categories = [];
  int sort = 0;

  ShopScope get scope => widget.scope;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final home = scope.native.settings['home'];
    sort = _sortFromSettings(home is Map ? home['sort'] : null);
    pager = ProductPager((cursor) => scope.api.products(cursor: cursor, sort: _sorts[sort][2] as ShopSort));
    _load();
  }

  Future<void> _load() async {
    // `settings.home.categories` (set by Flangapp AI): these ids, in this order;
    // none → every top-level category with products.
    final home = scope.native.settings['home'];
    final chosen = home is Map && home['categories'] is List ? [for (final id in home['categories'] as List) '$id'] : <String>[];
    scope.api.categories().then((all) {
      final byId = {for (final c in all) c.id: c};
      final shown = chosen.isNotEmpty
          ? [for (final id in chosen) if (byId[id] != null) byId[id]!]
          : all.where((c) => c.parent.isEmpty && (c.count ?? 1) > 0).toList();
      if (mounted) setState(() => categories = shown);
    }).catchError((_) {});
    await pager.reload();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(scope.app.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => scope.push(context, ShopSearchScreen(scope: scope)),
          ),
          CartAction(scope: scope),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) => loadMoreOnScroll(n, pager),
          child: CustomScrollView(
            slivers: [
              if (categories.isNotEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 52,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      itemCount: categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) => ActionChip(
                        label: Text(categories[i].name),
                        onPressed: () => scope.push(context, ShopCategoryScreen(scope: scope, category: categories[i])),
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(scope.t(_sorts[sort][0] as String, _sorts[sort][1] as String),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      ),
                      _SortButton(scope: scope, value: sort, onChanged: (s) {
                        setState(() => sort = s);
                        pager.reload();
                      }),
                    ],
                  ),
                ),
              ),
              ProductGridSliver(scope: scope, pager: pager),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  final ShopScope scope;
  final int value;
  final ValueChanged<int> onChanged;

  const _SortButton({required this.scope, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      icon: const Icon(Icons.sort),
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (var i = 0; i < _sorts.length; i++)
          PopupMenuItem(value: i, child: Text(scope.t(_sorts[i][0] as String, _sorts[i][1] as String))),
      ],
    );
  }
}

/// Categories tab: the shop's top-level categories (Shopify: collections).
class ShopCategoriesScreen extends StatefulWidget {
  final ShopScope scope;
  const ShopCategoriesScreen({super.key, required this.scope});

  @override
  State<ShopCategoriesScreen> createState() => _ShopCategoriesScreenState();
}

class _ShopCategoriesScreenState extends State<ShopCategoriesScreen> with AutomaticKeepAliveClientMixin {
  List<ShopCategory>? all;
  String? error;

  ShopScope get scope => widget.scope;

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
    final top = (all ?? []).where((c) => c.parent.isEmpty && (c.count ?? 1) > 0).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(scope.t('categories', 'Categories')),
        actions: [CartAction(scope: scope)],
      ),
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
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 84),
                        itemBuilder: (context, i) => _CategoryTile(scope: scope, category: top[i], all: all!),
                      ),
                    ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final ShopScope scope;
  final ShopCategory category;
  final List<ShopCategory> all;

  const _CategoryTile({required this.scope, required this.category, required this.all});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(width: 52, height: 52, child: NetImage(category.image?.thumbnail ?? '')),
      ),
      title: Text(category.name, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: category.count != null ? Text('${category.count} ${scope.t('products', 'products')}') : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => scope.push(context, ShopCategoryScreen(scope: scope, category: category, all: all)),
    );
  }
}

/// Products of one category, with its sub-categories on top.
class ShopCategoryScreen extends StatefulWidget {
  final ShopScope scope;
  final ShopCategory category;
  final List<ShopCategory>? all;

  const ShopCategoryScreen({super.key, required this.scope, required this.category, this.all});

  @override
  State<ShopCategoryScreen> createState() => _ShopCategoryScreenState();
}

class _ShopCategoryScreenState extends State<ShopCategoryScreen> {
  late final ProductPager pager;
  int sort = 0;

  ShopScope get scope => widget.scope;

  @override
  void initState() {
    super.initState();
    pager = ProductPager((cursor) => scope.api.products(
          cursor: cursor,
          category: widget.category.id,
          sort: _sorts[sort][2] as ShopSort,
        ));
    pager.reload();
  }

  @override
  Widget build(BuildContext context) {
    final children = (widget.all ?? []).where((c) => c.parent == widget.category.id && (c.count ?? 1) > 0).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category.name),
        actions: [
          _SortButton(scope: scope, value: sort, onChanged: (s) {
            setState(() => sort = s);
            pager.reload();
          }),
          CartAction(scope: scope),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) => loadMoreOnScroll(n, pager),
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
                        ActionChip(
                          label: Text(c.name),
                          onPressed: () => scope.push(context, ShopCategoryScreen(scope: scope, category: c, all: widget.all)),
                        ),
                    ],
                  ),
                ),
              ),
            ProductGridSliver(scope: scope, pager: pager),
          ],
        ),
      ),
    );
  }
}

class ShopSearchScreen extends StatefulWidget {
  final ShopScope scope;
  const ShopSearchScreen({super.key, required this.scope});

  @override
  State<ShopSearchScreen> createState() => _ShopSearchScreenState();
}

class _ShopSearchScreenState extends State<ShopSearchScreen> {
  String query = '';
  ProductPager? pager;

  ShopScope get scope => widget.scope;

  void _search(String text) {
    final q = text.trim();
    if (q.isEmpty) return;
    setState(() {
      query = q;
      pager = ProductPager((cursor) => scope.api.products(cursor: cursor, search: q, sort: ShopSort.relevance));
    });
    pager!.reload();
  }

  @override
  Widget build(BuildContext context) {
    final onBar = Theme.of(context).appBarTheme.foregroundColor;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          style: TextStyle(color: onBar),
          cursorColor: onBar,
          decoration: InputDecoration(
            hintText: scope.t('search_hint', 'Search products'),
            hintStyle: TextStyle(color: onBar?.withValues(alpha: 0.6)),
            border: InputBorder.none,
          ),
        ),
      ),
      body: pager == null
          ? EmptyView(icon: Icons.search, message: scope.t('search_prompt', 'Type what you are looking for'))
          : NotificationListener<ScrollNotification>(
              onNotification: (n) => loadMoreOnScroll(n, pager!),
              child: CustomScrollView(slivers: [ProductGridSliver(key: ValueKey(query), scope: scope, pager: pager!)]),
            ),
    );
  }
}
