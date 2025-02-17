import 'dart:io';

import 'package:collection/collection.dart';
import 'package:fehviewer/fehviewer.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart' as pp;
import 'package:shared_storage/saf.dart';
import 'package:shared_storage/shared_storage.dart' as ss;

const kSafCacheDir = 'saf_cache';

const kDocumentFileColumns = <ss.DocumentFileColumn>[
  ss.DocumentFileColumn.displayName,
  ss.DocumentFileColumn.size,
  ss.DocumentFileColumn.lastModified,
  ss.DocumentFileColumn.id,
  ss.DocumentFileColumn.mimeType,
];

Future<String> safCacheSingle(Uri cacheUri, {bool overwrite = false}) async {
  final exists = await ss.exists(cacheUri) ?? false;
  if (!exists) {
    throw Exception('safCacheSingle: $cacheUri not exists');
  }
  final ss.DocumentFile? domFile = await cacheUri.toDocumentFile();
  final domSize = domFile?.size;
  logger.d('dom size: $domSize');

  final cachePath = await _makeExternalStorageTempPath(cacheUri);
  final file = File(cachePath);
  if (!file.existsSync() || overwrite || file.lengthSync() != domSize) {
    final bytes = await domFile?.getContent();
    if (bytes != null) {
      file.writeAsBytesSync(bytes);
    }
  }

  return cachePath;
}

Future<String> safCache(Uri cacheUri, {bool overwrite = false}) async {
  final cachePath = await _makeExternalStorageTempPath(cacheUri);
  logger.d('cache to cachePath: $cachePath');

  final Stream<ss.DocumentFile> onNewFileLoaded =
      ss.listFiles(cacheUri, columns: kDocumentFileColumns);

  await for (final ss.DocumentFile documentFile in onNewFileLoaded) {
    logger.d(
        'documentFile \n${documentFile.uri}\n${documentFile.name} \n${documentFile.size} \n'
        '${documentFile.lastModified} \n${documentFile.id} \n${documentFile.type}');
    try {
      final bytes = await ss.getDocumentContent(documentFile.uri);
      final file = File(path.join(cachePath, documentFile.name));
      if (bytes != null && bytes.isNotEmpty) {
        if (overwrite) {
          await file.writeAsBytes(bytes);
        } else {
          if (!file.existsSync()) {
            await file.writeAsBytes(bytes);
          }
        }
      }
    } catch (e, stack) {
      logger.e('safCache error', e, stack);
    }
  }

  return cachePath;
}

Future<String> _makeExternalStorageTempPath(Uri uri) async {
  final extPath = (await pp.getExternalCacheDirectories())?.firstOrNull;

  final documentFile = await uri.toDocumentFile();
  if (documentFile == null) {
    logger.e('documentFile is null');
    throw Exception('documentFile is null');
  }
  logger.d('documentFile id: ${documentFile.id}');

  if (extPath == null) {
    logger.e('extPath is null');
    throw Exception('getExternalStorageDirectory is null');
  }

  final cachePath = path.join(
    extPath.path,
    kSafCacheDir,
    _makeDirectoryPathToName(documentFile.id ?? ''),
  );

  final parentDir = Directory(path.dirname(cachePath));
  if (!parentDir.existsSync()) {
    parentDir.createSync(recursive: true);
  }

  logger.d('cache to cachePath: $cachePath');

  return cachePath;
}

String _makeDirectoryPathToName(String path) {
  return path.replaceAll('/', '_').replaceAll(':', '_');
}

Uri safMakeUri({String path = '', bool isTreeUri = false}) {
  final fullPath =
      path.replaceAll(RegExp(r'^(/storage/emulated/\d+/|/sdcard/)'), '');
  final directoryPath = fullPath.replaceAll(RegExp(r'[^/]+$'), '');

  const scheme = 'content';
  const host = 'com.android.externalstorage.documents';

  Uri uri = Uri(
    scheme: scheme,
    host: host,
    pathSegments: [
      'tree',
      if (isTreeUri) 'primary:$fullPath' else 'primary:$directoryPath',
      if (!isTreeUri) 'document',
      if (!isTreeUri) 'primary:$fullPath',
    ],
  );

  final url = uri.toString();
  final urlWithReplace = url.replaceAll('primary:', 'primary%3A');

  return Uri.parse(urlWithReplace);
}

Future<void> safCreateDirectory(Uri uri, {bool documentToTree = false}) async {
  final List<UriPermission>? persistedUriList =
      await ss.persistedUriPermissions();
  logger.d('persistedUriList:\n\n${persistedUriList?.join('\n')}');
  if (persistedUriList == null || persistedUriList.isEmpty) {
    logger.e('persistedUriList is null');
    showToast('persistedUriList is null');
    return;
  }
  // if (persistedUriList.any((e) => e.uri == uri)) {
  //   logger.d('persistedUriList contains uri');
  //   return;
  // }

  if (uri.scheme != 'content' ||
      uri.host != 'com.android.externalstorage.documents') {
    logger.e('uri is not saf uri');
    throw Exception('uri is not saf uri');
  }

  final pathSegments = uri.pathSegments;
  if (pathSegments[0] != 'tree') {
    logger.e('uri is not saf tree uri');
    throw Exception('uri is not saf tree uri');
  }

  logger.d('pathSegments:\n\n${pathSegments.join('\n')}');

  late final String path;
  if (pathSegments.length == 2) {
    logger.d('from tree uri: [${pathSegments[1]}]');
    path = pathSegments[1];
  } else if (pathSegments.length == 4) {
    logger.d('from tree_document uri: [${pathSegments[1]}]');
    if (!documentToTree) {
      path = pathSegments[1];
    } else {
      path = pathSegments[3];
    }
  } else {
    logger.e('uri is not saf uri');
    throw Exception('uri is not saf uri');
  }

  logger.v('primary path: [$path]');

  final pathList = path.split(':');
  if (pathList.length != 2 || pathList[0] != 'primary') {
    logger.e('uri is not saf tree uri');
    throw Exception('uri is not saf tree uri');
  }

  logger.v('path split:\n\n${pathList.join('\n')}');

  final dirPath = pathList[1];
  final dirPathList = dirPath.split('/');

  logger.d('dirPathList:\n\n${dirPathList.join('\n')}');

  for (int i = dirPathList.length - 1; i > 0; i--) {
    final dirName = dirPathList[i];
    final parentPath = dirPathList.sublist(0, i).join('/');
    final parentUri = safMakeUri(path: parentPath, isTreeUri: true);

    final childDocumentFile = await ss.findFile(parentUri, dirName);
    if (childDocumentFile != null && (childDocumentFile.isDirectory ?? false)) {
      logger.d('childDocumentFile is directory');
      continue;
    }

    logger.v('dirName: $dirName');
    logger.d('parentPath: $parentPath');
    logger.v('parentUri: $parentUri');
    if (!persistedUriList.any(
        (element) => element.uri == parentUri && element.isWritePermission)) {
      if (parentPath == 'Download' || parentPath == 'Android') {
        continue;
      }
      logger.d('parentUri: $parentUri not persisted');
      showToast('parentUri: $parentUri not persisted');
      await openDocumentTree(initialUri: parentUri);
    }

    for (int j = i; j < dirPathList.length; j++) {
      final dirName = dirPathList[j];
      final parentPath = dirPathList.sublist(0, j).join('/');
      final parentUri = safMakeUri(path: parentPath, isTreeUri: true);

      logger.v(
          '#########\nparentUri: ${parentUri.toString()} \nchildDocumentFile dirName: $dirName');

      final documentFile = await ss.findFile(parentUri, dirName);
      if (documentFile != null) {
        // logger.d('isDirectory ${documentFile.isDirectory}');
        // logger.d('safCreateDirectory: ${documentFile.id} exists');
        continue;
      } else {
        logger.d('safCreateDirectory: $parentUri => $dirName not exists');
        if (!persistedUriList.any((element) => element.uri == parentUri)) {
          logger.d('parentUri: $parentUri not persisted');
          showToast('parentUri: $parentUri not persisted');
          return;
        }
        await ss.createDirectory(parentUri, dirName);
      }
    }
  }
}
