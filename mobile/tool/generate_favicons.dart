import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final pinPath = '../web/images/brand/voyplan-pin.png';
  final fallbackPath = 'assets/icon/voyplan.png';
  final sourceFile = File(pinPath).existsSync() ? File(pinPath) : File(fallbackPath);

  if (!sourceFile.existsSync()) {
    print('Error: Source icon not found at $pinPath or $fallbackPath');
    exit(1);
  }

  print('Generating favicons and icons from: ${sourceFile.path}');
  final bytes = sourceFile.readAsBytesSync();
  final image = img.decodeImage(bytes);

  if (image == null) {
    print('Error: Could not decode source image');
    exit(1);
  }

  final sizes = <int, String>{
    16: 'web/favicon-16x16.png',
    32: 'web/favicon-32x32.png',
    48: 'web/favicon-48x48.png',
    96: 'web/favicon-96x96.png',
    180: 'web/apple-touch-icon.png',
    192: 'web/favicon-192x192.png',
    512: 'web/favicon.png',
  };

  for (final entry in sizes.entries) {
    final resized = img.copyResize(image, width: entry.key, height: entry.key, interpolation: img.Interpolation.cubic);
    final pngBytes = img.encodePng(resized);
    File(entry.value).writeAsBytesSync(pngBytes);
    print('Generated ${entry.value} (${entry.key}x${entry.key})');
  }

  // Generate icons/Icon-192.png, Icon-512.png, Icon-maskable-192.png, Icon-maskable-512.png
  final icon192 = img.copyResize(image, width: 192, height: 192, interpolation: img.Interpolation.cubic);
  final icon512 = img.copyResize(image, width: 512, height: 512, interpolation: img.Interpolation.cubic);
  File('web/icons/Icon-192.png').writeAsBytesSync(img.encodePng(icon192));
  File('web/icons/Icon-512.png').writeAsBytesSync(img.encodePng(icon512));
  File('web/icons/Icon-maskable-192.png').writeAsBytesSync(img.encodePng(icon192));
  File('web/icons/Icon-maskable-512.png').writeAsBytesSync(img.encodePng(icon512));
  print('Generated PWA icons in web/icons/');

  // Generate favicon.ico (can be a 32x32 or multi-resolution png encoded as ico)
  final ico32 = img.copyResize(image, width: 32, height: 32, interpolation: img.Interpolation.cubic);
  File('web/favicon.ico').writeAsBytesSync(img.encodeIco(ico32));
  print('Generated web/favicon.ico');

  // Copy to root web/ directory if needed
  if (Directory('../web').existsSync()) {
    File('web/favicon.ico').copySync('../web/favicon.ico');
    File('web/favicon.png').copySync('../web/favicon.png');
    File('web/favicon-32x32.png').copySync('../web/favicon-32x32.png');
    print('Copied favicons to root web/ directory');
  }

  print('Favicon and icon generation complete!');
}
