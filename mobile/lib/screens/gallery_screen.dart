import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../models/trip_extras.dart';
import '../services/trip_extras_store.dart';
import '../theme/app_theme.dart';

/// Travel gallery: store photos & moments for a trip. Images are compressed and
/// kept locally (per trip) as data URLs, so it works offline and for guests.
class GalleryScreen extends StatefulWidget {
  final TripExtrasStore store;
  final String tripName;
  const GalleryScreen({super.key, required this.store, this.tripName = 'My Trip'});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<GalleryPhoto> _photos = [];
  final Map<String, Uint8List> _decoded = {}; // id -> raw bytes (thumbnail cache)
  bool _loading = true;
  bool _busy = false;

  static const int _maxPhotos = 60;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final photos = await widget.store.loadGallery();
    if (!mounted) return;
    for (final p in photos) {
      _decoded[p.id] = _bytesOf(p);
    }
    setState(() {
      _photos = photos;
      _loading = false;
    });
  }

  Uint8List _bytesOf(GalleryPhoto p) {
    try {
      return base64Decode(p.dataUrl.contains(',') ? p.dataUrl.split(',').last : p.dataUrl);
    } catch (_) {
      return Uint8List(0);
    }
  }

  /// Decode → resize to fit 1280px → JPEG (quality 60). Runs off the raw picked
  /// bytes; returns a compact JPEG suitable for local storage.
  Uint8List? _compress(Uint8List raw) {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return null;
    img.Image out = decoded;
    const maxDim = 1280;
    if (decoded.width > maxDim || decoded.height > maxDim) {
      out = decoded.width >= decoded.height
          ? img.copyResize(decoded, width: maxDim)
          : img.copyResize(decoded, height: maxDim);
    }
    return Uint8List.fromList(img.encodeJpg(out, quality: 60));
  }

  Future<void> _addPhotos() async {
    if (_photos.length >= _maxPhotos) {
      _snack('Gallery is full ($_maxPhotos photos). Remove some to add more.');
      return;
    }
    FilePickerResult? res;
    try {
      res = await FilePicker.pickFiles(withData: true, type: FileType.image, allowMultiple: true);
    } catch (_) {
      _snack('Could not open the picker.');
      return;
    }
    if (res == null || res.files.isEmpty) return;

    setState(() => _busy = true);
    final added = <GalleryPhoto>[];
    int failed = 0;
    for (final f in res.files) {
      if (_photos.length + added.length >= _maxPhotos) break;
      final raw = f.bytes;
      if (raw == null) { failed++; continue; }
      Uint8List? jpg;
      try {
        jpg = _compress(raw);
      } catch (_) {
        jpg = null;
      }
      if (jpg == null) { failed++; continue; }
      final photo = GalleryPhoto(
        id: DateTime.now().microsecondsSinceEpoch.toString() + added.length.toString(),
        dataUrl: 'data:image/jpeg;base64,${base64Encode(jpg)}',
      );
      _decoded[photo.id] = jpg;
      added.add(photo);
    }
    if (added.isEmpty) {
      setState(() => _busy = false);
      _snack(failed > 0 ? 'Those images could not be read.' : 'No photos added.');
      return;
    }
    final next = [...added, ..._photos];
    final ok = await widget.store.saveGallery(next);
    if (!mounted) return;
    if (!ok) {
      // Roll back — the device storage is full.
      for (final p in added) {
        _decoded.remove(p.id);
      }
      setState(() => _busy = false);
      _snack('Not enough device storage to save these photos.');
      return;
    }
    setState(() {
      _photos = next;
      _busy = false;
    });
    _snack('Added ${added.length} photo${added.length == 1 ? '' : 's'}.${failed > 0 ? ' ($failed skipped)' : ''}');
  }

  Future<void> _persist() async {
    final ok = await widget.store.saveGallery(_photos);
    if (!ok && mounted) _snack("Couldn't save changes (storage full).");
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openPhoto(int index) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PhotoView(
        photo: _photos[index],
        bytes: _decoded[_photos[index].id] ?? _bytesOf(_photos[index]),
        onCaption: (text) {
          setState(() => _photos[index].caption = text);
          _persist();
        },
        onDelete: () {
          final removed = _photos[index];
          setState(() {
            _photos.removeAt(index);
            _decoded.remove(removed.id);
          });
          _persist();
          Navigator.of(context).pop();
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Voy.bg,
      appBar: AppBar(
        backgroundColor: Voy.surface,
        foregroundColor: Voy.ink,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Travel gallery', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text(widget.tripName, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: Voy.sub, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _addPhotos,
        backgroundColor: Voy.brand,
        foregroundColor: const Color(0xFF04211F),
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF04211F)))
            : const Icon(Icons.add_a_photo_rounded),
        label: Text(_busy ? 'Adding…' : 'Add photos'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _photos.isEmpty
              ? _empty()
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 96),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _photos.length,
                  itemBuilder: (_, i) {
                    final p = _photos[i];
                    final bytes = _decoded[p.id] ?? _bytesOf(p);
                    return GestureDetector(
                      onTap: () => _openPhoto(i),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            bytes.isEmpty
                                ? Container(color: Voy.surface2, child: const Icon(Icons.broken_image_outlined, color: Voy.sub))
                                : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
                            if (p.caption.isNotEmpty)
                              Positioned(
                                left: 0, right: 0, bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                      colors: [Colors.transparent, Colors.black87],
                                    ),
                                  ),
                                  child: Text(p.caption, maxLines: 2, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.photo_library_outlined, size: 56, color: Voy.sub),
              const SizedBox(height: 14),
              const Text('No photos yet', style: TextStyle(color: Voy.ink, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Capture your trip’s moments. Tap “Add photos” to start.\nPhotos are kept on this device.',
                  textAlign: TextAlign.center, style: TextStyle(color: Voy.sub, fontSize: 13)),
            ],
          ),
        ),
      );
}

/// Full-screen single photo with caption editing and delete.
class _PhotoView extends StatelessWidget {
  final GalleryPhoto photo;
  final Uint8List bytes;
  final void Function(String) onCaption;
  final VoidCallback onDelete;
  const _PhotoView({required this.photo, required this.bytes, required this.onCaption, required this.onDelete});

  Future<void> _editCaption(BuildContext context) async {
    final ctrl = TextEditingController(text: photo.caption);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Voy.surface,
        title: const Text('Caption', style: TextStyle(color: Voy.ink)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          style: const TextStyle(color: Voy.ink),
          decoration: const InputDecoration(hintText: 'Add a moment…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (text != null) onCaption(text);
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Voy.surface,
        title: const Text('Delete photo?', style: TextStyle(color: Voy.ink)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Voy.danger))),
        ],
      ),
    );
    if (ok == true) onDelete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Caption', onPressed: () => _editCaption(context)),
          IconButton(icon: const Icon(Icons.delete_outline_rounded), tooltip: 'Delete', onPressed: () => _confirmDelete(context)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: bytes.isEmpty
                ? const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48))
                : InteractiveViewer(minScale: 0.8, maxScale: 4, child: Center(child: Image.memory(bytes, gaplessPlayback: true))),
          ),
          if (photo.caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(photo.caption, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
            ),
        ],
      ),
    );
  }
}
