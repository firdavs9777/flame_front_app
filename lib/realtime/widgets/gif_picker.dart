import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_client.dart';

/// Tenor GIF picker. Calls `GET /v1/media/gif/search?q=&limit=` and renders
/// results in a 2-column grid. Tapping a result invokes [onPick] with the
/// Tenor URL plus width/height (whitelisted by the backend's media regex).
class GifPicker extends ConsumerStatefulWidget {
  final void Function(String url, int width, int height) onPick;
  const GifPicker({super.key, required this.onPick});

  @override
  ConsumerState<GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends ConsumerState<GifPicker> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      if (mounted) setState(() => _results = []);
      return;
    }
    if (mounted) setState(() => _loading = true);
    final api = ApiClient();
    final resp = await api.get(
      '/media/gif/search',
      queryParams: {'q': q, 'limit': '24'},
    );
    if (!mounted) return;
    if (resp.success && resp.data is Map) {
      final list = ((resp.data as Map)['results'] as List?) ?? const [];
      _results = list
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    } else {
      _results = [];
    }
    setState(() => _loading = false);
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 320,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                hintText: 'Search GIFs',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _results.isEmpty
                ? const Center(
                    child: Text(
                      'Type to search GIFs',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(4),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                    itemCount: _results.length,
                    itemBuilder: (ctx, i) {
                      final g = _results[i];
                      final url = (g['url'] as String?) ?? '';
                      final w = (g['width'] as num?)?.toInt() ?? 0;
                      final h = (g['height'] as num?)?.toInt() ?? 0;
                      if (url.isEmpty) return const SizedBox.shrink();
                      return GestureDetector(
                        onTap: () => widget.onPick(url, w, h),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            placeholder: (c, _) =>
                                Container(color: Colors.grey.shade200),
                            errorWidget: (c, _, e) =>
                                Container(color: Colors.grey.shade300),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
