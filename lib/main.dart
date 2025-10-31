// lib/main.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('users'); // simple user storage
  await Hive.openBox('cart'); // cart storage
  await Hive.openBox('cache'); // product cache
  runApp(BigDealsApp());
}

class BigDealsApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BigDeals',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        scaffoldBackgroundColor: Colors.grey[50],
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: HomePage(), // show Home first as requested
    );
  }
}

/* ---------------------------
   Models (simple Map-based)
   --------------------------- */

class ProductModel {
  final int id;
  final String title;
  final String description;
  final double price;
  final String image;
  final String category;

  ProductModel({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.image,
    required this.category,
  });

  factory ProductModel.fromMap(Map m) => ProductModel(
    id: (m['id'] is int) ? m['id'] : int.parse(m['id'].toString()),
    title: m['title'] ?? '',
    description: m['description'] ?? '',
    price: (m['price'] is num) ? (m['price'] as num).toDouble() : double.tryParse(m['price'].toString()) ?? 0.0,
    image: m['image'] ?? '',
    category: m['category'] ?? '',
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'description': description,
    'price': price,
    'image': image,
    'category': category,
  };
}

/* ---------------------------
   Home Page
   --------------------------- */

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

enum LayoutMode { grid, list }

class _HomePageState extends State<HomePage> {
  List<ProductModel> products = [];
  bool loading = true;
  String error = '';
  final cacheBox = Hive.box('cache');
  final cartBox = Hive.box('cart');

  // UI state
  LayoutMode layoutMode = LayoutMode.grid;
  Set<int> favorites = {};
  bool showOnlyFav = false;
  late SharedPreferences prefs;
  String search = '';

  @override
  void initState() {
    super.initState();
    _initPrefs();
    _loadProducts();
  }

  Future<void> _initPrefs() async {
    prefs = await SharedPreferences.getInstance();
    final favList = prefs.getStringList('favs_v1') ?? [];
    setState(() {
      favorites = favList.map((e) => int.tryParse(e)).whereType<int>().toSet();
      layoutMode = (prefs.getString('layout_v1') == 'list') ? LayoutMode.list : LayoutMode.grid;
      showOnlyFav = prefs.getBool('showOnlyFav_v1') ?? false;
    });
  }

  Future<void> _saveFavs() async {
    await prefs.setStringList('favs_v1', favorites.map((e) => e.toString()).toList());
  }

  Future<void> _loadProducts() async {
    setState(() {
      loading = true;
      error = '';
    });

    try {
      final cached = cacheBox.get('products_json') as String?;
      if (cached != null) {
        final List decoded = jsonDecode(cached);
        products = decoded.map((e) => ProductModel.fromMap(Map<String, dynamic>.from(e))).toList();
      }

      final uri = Uri.parse('https://fakestoreapi.com/products');
      final res = await http.get(uri).timeout(Duration(seconds: 12));
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        products = data.map((e) => ProductModel.fromMap(Map<String, dynamic>.from(e))).toList();
        await cacheBox.put('products_json', jsonEncode(data));
      } else {
        if (products.isEmpty) error = 'Failed to fetch products';
      }
    } catch (e) {
      if (products.isEmpty) error = 'Could not fetch products. Check internet.';
    } finally {
      setState(() => loading = false);
    }
  }

  List<ProductModel> get visibleProducts {
    var list = products;
    if (search.trim().isNotEmpty) {
      final s = search.trim().toLowerCase();
      list = list.where((p) => p.title.toLowerCase().contains(s) || p.category.toLowerCase().contains(s)).toList();
    }
    if (showOnlyFav) list = list.where((p) => favorites.contains(p.id)).toList();
    return list;
  }

  void toggleFav(int id) {
    setState(() {
      if (favorites.contains(id)) favorites.remove(id);
      else favorites.add(id);
    });
    _saveFavs();
  }

  void toggleLayout() {
    setState(() {
      layoutMode = (layoutMode == LayoutMode.grid) ? LayoutMode.list : LayoutMode.grid;
      prefs.setString('layout_v1', layoutMode == LayoutMode.list ? 'list' : 'grid');
    });
  }

  void toggleShowFav() {
    setState(() {
      showOnlyFav = !showOnlyFav;
      prefs.setBool('showOnlyFav_v1', showOnlyFav);
    });
  }

  // Add to cart with quantity
  Future<void> addToCart(ProductModel p, int qty) async {
    final exists = cartBox.values.any((e) => Map<String, dynamic>.from(e)['id'] == p.id);
    if (!exists) {
      await cartBox.add({
        'id': p.id,
        'title': p.title,
        'image': p.image,
        'price': p.price,
        'quantity': qty,
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added "${p.title}" to cart')));
    } else {
      // If already exists, update quantity (add)
      final entries = cartBox.values.toList();
      for (int i = 0; i < entries.length; i++) {
        final Map<String, dynamic> m = Map<String, dynamic>.from(entries[i]);
        if (m['id'] == p.id) {
          final current = (m['quantity'] as num).toInt();
          m['quantity'] = current + qty;
          await cartBox.putAt(i, m);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Updated quantity for "${p.title}"')));
          break;
        }
      }
    }
    setState(() {});
  }

  void openLogin() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => LoginPage())).then((_) => setState(() {}));
  }

  void openSignup() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => SignupPage())).then((_) => setState(() {}));
  }

  void openCart() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => CartPage())).then((_) => setState(() {}));
  }

  void logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Logged out')));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cartCount = cartBox.length;
    return Scaffold(
      drawer: AppDrawer(
        onLogin: openLogin,
        onSignup: openSignup,
        onLogout: logout,
        onHome: () {
          Navigator.pop(context);
        },
        onCart: openCart,
      ),
      appBar: AppBar(
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.local_offer_outlined),
            SizedBox(width: 8),
            Text('BigDeals', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: 8.0),
                child: Container(
                  height: 42,
                  child: TextField(
                    onChanged: (v) => setState(() => search = v),
                    decoration: InputDecoration(
                      hintText: 'Search products, categories...',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      filled: true,
                      fillColor: Colors.white,
                      suffixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: layoutMode == LayoutMode.grid ? 'List view' : 'Grid view',
            onPressed: toggleLayout,
            icon: Icon(layoutMode == LayoutMode.grid ? Icons.view_list : Icons.grid_view),
          ),
          IconButton(
            tooltip: showOnlyFav ? 'Show all' : 'Show favorites',
            onPressed: toggleShowFav,
            icon: Icon(showOnlyFav ? Icons.favorite : Icons.favorite_border),
            color: showOnlyFav ? Colors.redAccent : null,
          ),
          Stack(
            children: [
              IconButton(
                icon: Icon(Icons.shopping_cart_outlined),
                onPressed: openCart,
              ),
              if (cartCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: CircleAvatar(radius: 9, backgroundColor: Colors.red, child: Text(cartCount.toString(), style: TextStyle(fontSize: 10, color: Colors.white))),
                )
            ],
          ),
          SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: loading
            ? Center(child: CircularProgressIndicator())
            : error.isNotEmpty
            ? Center(child: Text(error))
            : Column(
          children: [
            HeaderWidget(), // attractive top banner
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: RefreshIndicator(
                  onRefresh: _loadProducts,
                  child: LayoutBuilder(builder: (context, constraints) {
                    // determine columns
                    int columns;
                    final width = constraints.maxWidth;
                    if (width >= 1200) columns = 5;
                    else if (width >= 1000) columns = 4;
                    else if (width >= 700) columns = 3;
                    else if (width >= 500) columns = 2;
                    else columns = 1;

                    final list = visibleProducts;
                    if (list.isEmpty) return ListView(children: [Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No products found')))]);

                    if (layoutMode == LayoutMode.list || columns == 1) {
                      return ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final p = list[i];
                          return ProductListTile(
                            product: p,
                            isFav: favorites.contains(p.id),
                            onFav: () => toggleFav(p.id),
                            onAdd: (qty) => addToCart(p, qty),
                          );
                        },
                      );
                    }

                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.62,
                      ),
                      itemCount: list.length,
                      itemBuilder: (context, idx) {
                        final p = list[idx];
                        return ProductCard(
                          product: p,
                          isFav: favorites.contains(p.id),
                          onFav: () => toggleFav(p.id),
                          onAdd: (qty) => addToCart(p, qty),
                        );
                      },
                    );
                  }),
                ),
              ),
            ),
            FooterWidget()
          ],
        ),
      ),
    );
  }
}

/* ---------------------------
   Product Card (Grid)
   --------------------------- */

class ProductCard extends StatefulWidget {
  final ProductModel product;
  final bool isFav;
  final VoidCallback onFav;
  final Function(int qty) onAdd;

  const ProductCard({required this.product, required this.isFav, required this.onFav, required this.onAdd});

  @override
  _ProductCardState createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  int qty = 1;

  void inc() => setState(() => qty++);
  void dec() => setState(() { if (qty > 1) qty--; });

  void showDetailModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, sc) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              controller: sc,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Container(width: 60, height: 6, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(6))),
                    SizedBox(height: 12),
                    Text(widget.product.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    SizedBox(height: 12),
                    SizedBox(height: 220, child: Image.network(widget.product.image, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(Icons.broken_image, size: 80))),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Text('\$${widget.product.price.toStringAsFixed(2)}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Spacer(),
                        IconButton(
                          icon: Icon(widget.isFav ? Icons.favorite : Icons.favorite_border, color: widget.isFav ? Colors.red : null),
                          onPressed: widget.onFav,
                        )
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(widget.product.description),
                    SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                          child: Row(children: [
                            IconButton(icon: Icon(Icons.remove), onPressed: dec),
                            Text(qty.toString()),
                            IconButton(icon: Icon(Icons.add), onPressed: inc),
                          ]),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              widget.onAdd(qty);
                              Navigator.pop(context);
                            },
                            icon: Icon(Icons.shopping_cart_outlined),
                            label: Text('Add to cart'),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return InkWell(
      onTap: showDetailModal,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // image container - fixed height and fitted
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                child: Container(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Image.network(p.image, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(Icons.broken_image, size: 48)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text('\$${p.price.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(children: [
                // qty control
                Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                  child: Row(children: [
                    IconButton(icon: Icon(Icons.remove), onPressed: dec),
                    Text(qty.toString()),
                    IconButton(icon: Icon(Icons.add), onPressed: inc),
                  ]),
                ),
                Spacer(),
                IconButton(
                  icon: Icon(widget.isFav ? Icons.favorite : Icons.favorite_border, color: widget.isFav ? Colors.red : null),
                  onPressed: widget.onFav,
                ),
                ElevatedButton.icon(
                  onPressed: () => widget.onAdd(qty),
                  icon: Icon(Icons.shopping_cart_outlined),
                  label: Text('Add'),
                  style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                )
              ]),
            ),
            SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/* ---------------------------
   Product List Tile (for list layout)
   --------------------------- */

class ProductListTile extends StatefulWidget {
  final ProductModel product;
  final bool isFav;
  final VoidCallback onFav;
  final Function(int qty) onAdd;

  const ProductListTile({required this.product, required this.isFav, required this.onFav, required this.onAdd});

  @override
  _ProductListTileState createState() => _ProductListTileState();
}

class _ProductListTileState extends State<ProductListTile> {
  int qty = 1;
  void inc() => setState(() => qty++);
  void dec() => setState(() { if (qty > 1) qty--; });

  void showDetailModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, sc) {
          return Container(
            decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            child: SingleChildScrollView(
              controller: sc,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(children: [
                  Container(width: 60, height: 6, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(6))),
                  SizedBox(height: 12),
                  Text(widget.product.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),
                  SizedBox(height: 200, child: Image.network(widget.product.image, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(Icons.broken_image, size: 80))),
                  SizedBox(height: 12),
                  Row(children: [
                    Text('\$${widget.product.price.toStringAsFixed(2)}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Spacer(),
                    IconButton(icon: Icon(widget.isFav ? Icons.favorite : Icons.favorite_border, color: widget.isFav ? Colors.red : null), onPressed: widget.onFav),
                  ]),
                  SizedBox(height: 8),
                  Text(widget.product.description),
                  SizedBox(height: 12),
                  Row(children: [
                    Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)), child: Row(children: [IconButton(icon: Icon(Icons.remove), onPressed: dec), Text(qty.toString()), IconButton(icon: Icon(Icons.add), onPressed: inc)])),
                    SizedBox(width: 12),
                    Expanded(child: ElevatedButton(onPressed: () { widget.onAdd(qty); Navigator.pop(context); }, child: Text('Add to cart'))),
                  ]),
                  SizedBox(height: 20),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return InkWell(
      onTap: showDetailModal,
      child: Card(
        margin: EdgeInsets.symmetric(vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Row(children: [
            SizedBox(width: 100, height: 100, child: Image.network(p.image, fit: BoxFit.contain)),
            SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(height: 6),
                Text('\$${p.price.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Row(children: [
                  Container(
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
                    child: Row(children: [
                      IconButton(icon: Icon(Icons.remove), onPressed: dec),
                      Text(qty.toString()),
                      IconButton(icon: Icon(Icons.add), onPressed: inc),
                    ]),
                  ),
                  SizedBox(width: 10),
                  ElevatedButton(onPressed: () => widget.onAdd(qty), child: Text('Add to cart')),
                  SizedBox(width: 8),
                  IconButton(icon: Icon(widget.isFav ? Icons.favorite : Icons.favorite_border, color: widget.isFav ? Colors.red : null), onPressed: widget.onFav),
                ])
              ]),
            )
          ]),
        ),
      ),
    );
  }
}

/* ---------------------------
   Cart Page
   --------------------------- */

class CartPage extends StatefulWidget {
  @override
  _CartPageState createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final box = Hive.box('cart');

  void removeAt(int i) {
    box.deleteAt(i);
    setState(() {});
  }

  void updateQty(int index, int qty) {
    final Map<String, dynamic> item = Map<String, dynamic>.from(box.getAt(index));
    item['quantity'] = qty;
    box.putAt(index, item);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = box.values.map((e) => Map<String, dynamic>.from(e)).toList();
    final total = items.fold<double>(0, (sum, e) => sum + (e['price'] as num).toDouble() * (e['quantity'] as num).toInt());
    return Scaffold(
      appBar: AppBar(title: Text('Cart (${items.length})')),
      body: items.isEmpty
          ? Center(child: Text('Your cart is empty'))
          : ListView.separated(
        padding: EdgeInsets.all(12),
        separatorBuilder: (_, __) => SizedBox(height: 8),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final it = items[i];
          final qty = (it['quantity'] as num).toInt();
          return Card(
            child: ListTile(
              leading: SizedBox(width: 60, child: Image.network(it['image'], fit: BoxFit.contain)),
              title: Text(it['title'], maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('\$${(it['price'] as num).toDouble().toStringAsFixed(2)}'),
              trailing: SizedBox(
                width: 140,
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  IconButton(icon: Icon(Icons.remove), onPressed: () { if (qty > 1) updateQty(i, qty - 1); }),
                  Text(qty.toString()),
                  IconButton(icon: Icon(Icons.add), onPressed: () => updateQty(i, qty + 1)),
                  IconButton(icon: Icon(Icons.delete, color: Colors.red), onPressed: () => removeAt(i)),
                ]),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: items.isEmpty ? null : Padding(
        padding: EdgeInsets.all(12),
        child: ElevatedButton.icon(
          icon: Icon(Icons.payment),
          label: Text('Checkout (\$${total.toStringAsFixed(2)})'),
          onPressed: () {
            // Simulate checkout -> clear cart
            showDialog(context: context, builder: (_) => AlertDialog(
              title: Text('Checkout'),
              content: Text('Simulated checkout. Clear cart?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
                ElevatedButton(onPressed: () {
                  Hive.box('cart').clear();
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Order placed (simulated)')));
                }, child: Text('Yes'))
              ],
            ));
          },
        ),
      ),
    );
  }
}

/* ---------------------------
   Login & Signup Pages
   --------------------------- */

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  String email = '';
  String password = '';
  bool loading = false;

  void doLogin() async {
    if (!_form.currentState!.validate()) return;
    setState(() => loading = true);
    final users = Hive.box('users');
    final user = users.get(email);
    await Future.delayed(Duration(milliseconds: 600));
    if (user != null && user['password'] == password) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('logged_in', true);
      await prefs.setString('email', email);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login successful')));
      Navigator.pop(context); // go back to home
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid credentials')));
    }
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock, size: 80, color: Colors.deepPurple),
                SizedBox(height: 12),
                TextFormField(decoration: InputDecoration(labelText: 'Email'), onChanged: (v) => email = v.trim(), validator: (v) => v!.isEmpty ? 'Enter email' : null),
                TextFormField(decoration: InputDecoration(labelText: 'Password'), obscureText: true, onChanged: (v) => password = v.trim(), validator: (v) => v!.length < 3 ? 'Min 3 chars' : null),
                SizedBox(height: 16),
                ElevatedButton(onPressed: loading ? null : doLogin, child: loading ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text('Login')),
                SizedBox(height: 8),
                TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SignupPage())), child: Text('Create an account'))
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SignupPage extends StatefulWidget {
  @override
  _SignupPageState createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _form = GlobalKey<FormState>();
  String email = '';
  String password = '';
  bool loading = false;

  void doSignup() async {
    if (!_form.currentState!.validate()) return;
    final users = Hive.box('users');
    if (users.containsKey(email)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('User already exists')));
      return;
    }
    setState(() => loading = true);
    await users.put(email, {'password': password});
    await Future.delayed(Duration(milliseconds: 600));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Signup successful')));
    Navigator.pop(context);
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signup')),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_add, size: 80, color: Colors.deepPurple),
                SizedBox(height: 12),
                TextFormField(decoration: InputDecoration(labelText: 'Email'), onChanged: (v) => email = v.trim(), validator: (v) => v!.isEmpty ? 'Enter email' : null),
                TextFormField(decoration: InputDecoration(labelText: 'Password'), obscureText: true, onChanged: (v) => password = v.trim(), validator: (v) => v!.length < 3 ? 'Min 3 chars' : null),
                SizedBox(height: 16),
                ElevatedButton(onPressed: loading ? null : doSignup, child: loading ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text('Signup')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ---------------------------
   Header & Footer & Drawer
   --------------------------- */

class HeaderWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade200]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('BigDeals', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text('Best deals on electronics, fashion & more', style: TextStyle(color: Colors.white70)),
            ])),
        ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CartPage())),
            icon: Icon(Icons.shopping_cart_outlined, color: Colors.deepPurple),
            label: Text('My Cart', style: TextStyle(color: Colors.deepPurple)))
      ]),
    );
  }
}

class FooterWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[100],
      padding: EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      child: Column(children: [
        Divider(),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('About', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text('BigDeals is a demo e-commerce app built with Flutter.', style: TextStyle(fontSize: 12)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Contact', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text('support@bigdeals.demo', style: TextStyle(fontSize: 12)),
          ]),
        ]),
        SizedBox(height: 10),
        Text('© BigDeals 2025 • Built with ❤️ in Flutter', style: TextStyle(fontSize: 12, color: Colors.black54)),
      ]),
    );
  }
}

class AppDrawer extends StatelessWidget {
  final VoidCallback onHome;
  final VoidCallback onLogin;
  final VoidCallback onSignup;
  final VoidCallback onLogout;
  final VoidCallback onCart;

  const AppDrawer({required this.onHome, required this.onLogin, required this.onSignup, required this.onLogout, required this.onCart});

  Future<bool> _isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('logged_in') ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: FutureBuilder<bool>(
        future: _isLoggedIn(),
        builder: (context, snap) {
          final logged = snap.data ?? false;
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.deepPurple, Colors.deepPurpleAccent])),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('BigDeals', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('Shop the best deals', style: TextStyle(color: Colors.white70)),
                ]),
              ),
              ListTile(leading: Icon(Icons.home), title: Text('Home'), onTap: onHome),
              if (!logged) ListTile(leading: Icon(Icons.login), title: Text('Login'), onTap: onLogin),
              if (!logged) ListTile(leading: Icon(Icons.person_add), title: Text('Signup'), onTap: onSignup),
              ListTile(leading: Icon(Icons.shopping_cart), title: Text('Cart'), onTap: onCart),
              if (logged) ListTile(leading: Icon(Icons.logout), title: Text('Logout'), onTap: onLogout),
              Divider(),
              ListTile(leading: Icon(Icons.info_outline), title: Text('About'), onTap: () => showAboutDialog(context: context, applicationName: 'BigDeals', applicationVersion: '1.0', children: [Text('Demo e-commerce app')]))
            ],
          );
        },
      ),
    );
  }
}
