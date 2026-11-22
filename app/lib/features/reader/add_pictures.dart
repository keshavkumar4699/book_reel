import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/user_pictures.dart';
import '../../l10n/l10n.dart';
import '../../ui/backdrops.dart';
import '../../ui/haptics.dart';
import '../../ui/kit.dart';

/// Picks pictures from your phone (several at once) and adds them to the
/// backgrounds. Returns the paths added in the order picked, or null when
/// nothing was picked. Says so when some (or all) wouldn't open.
Future<List<String>?> addPicturesFromPhone(BuildContext context, WidgetRef ref) async {
  Haptics.select();
  final List<PlatformFile> files;
  try {
    files = await pickPictures();
  } catch (e) {
    debugPrint('Picture picker unavailable: $e');
    if (context.mounted) showKitToast(context, tr('Those pictures couldn’t be opened'), icon: Icons.broken_image_outlined);
    return null;
  }
  if (files.isEmpty) return null;
  final picked = <({String name, Uint8List bytes})>[];
  for (final f in files) {
    try {
      picked.add((name: f.name, bytes: await f.readAsBytes()));
    } catch (_) {}
  }
  final added = await UserPictures.add(picked);
  ref.invalidate(backdropsProvider);
  if (context.mounted && added.length < files.length) {
    showKitToast(
      context,
      added.isEmpty ? tr('Those pictures couldn’t be opened') : tr('Some pictures couldn’t be opened'),
      icon: Icons.broken_image_outlined,
    );
  }
  return added;
}

/// The phone's picture picker (tests replace it).
Future<List<PlatformFile>> Function() pickPictures = () => FilePicker.pickFiles(type: FileType.image);
