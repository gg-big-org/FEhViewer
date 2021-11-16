import 'package:collection/collection.dart';
import 'package:fehviewer/common/service/depth_service.dart';
import 'package:fehviewer/common/service/layout_service.dart';
import 'package:fehviewer/const/const.dart';
import 'package:fehviewer/models/index.dart';
import 'package:fehviewer/network/gallery_request.dart';
import 'package:fehviewer/network/request.dart';
import 'package:fehviewer/pages/gallery/comm.dart';
import 'package:fehviewer/pages/gallery/controller/gallery_page_controller.dart';
import 'package:fehviewer/pages/gallery/view/gallery_page.dart';
import 'package:fehviewer/pages/image_view/common.dart';
import 'package:fehviewer/pages/image_view/view/view_page.dart';
import 'package:fehviewer/pages/tab/controller/search_page_controller.dart';
import 'package:fehviewer/pages/tab/view/tab_base.dart';
import 'package:fehviewer/route/routes.dart';
import 'package:fehviewer/route/second_observer.dart';
import 'package:fehviewer/utils/logger.dart';
import 'package:get/get.dart';

class NavigatorUtil {
  // 带搜索条件打开搜索
  static Future<void> goSearchPageWithText({
    required String simpleSearch,
    bool replace = false,
  }) async {
    String _search = simpleSearch;
    if (simpleSearch.contains(':') &&
        EHConst.translateTagType.keys
            .contains(simpleSearch.split(':')[0].trim())) {
      final List<String> searArr = simpleSearch.split(':');
      String _end = '';
      if (searArr[0] != 'uploader') {
        _end = '\$';
      }
      _search = '${searArr[0]}:"${searArr[1]}$_end"';
    }

    Get.find<DepthService>().pushSearchPageCtrl();
    Get.replace(SearchRepository(searchText: _search));

    Get.put(
      SearchPageController(),
      tag: searchPageCtrlDepth,
    );

    if (replace) {
      await Get.offNamed(
        EHRoutes.search,
        preventDuplicates: false,
      );
    } else {
      await Get.toNamed(
        EHRoutes.search,
        id: isLayoutLarge ? 1 : null,
        preventDuplicates: false,
      );
    }

    Get.find<DepthService>().popSearchPageCtrl();
  }

  /// 打开搜索页面 指定搜索类型
  static Future<void> goSearchPage({
    SearchType searchType = SearchType.normal,
    bool fromTabItem = true,
  }) async {
    logger.d('fromTabItem $fromTabItem');
    Get.find<DepthService>().pushSearchPageCtrl();

    Get.replace(SearchRepository(searchType: searchType));

    Get.put(
      SearchPageController(),
      tag: searchPageCtrlDepth,
    );

    await Get.toNamed(
      EHRoutes.search,
      id: isLayoutLarge ? 1 : null,
    );

    Get.find<DepthService>().popSearchPageCtrl();
  }

  /// 转到画廊页面
  static Future<void> goGalleryPage({
    String? url,
    dynamic tabTag,
    GalleryItem? galleryItem,
    bool replace = false,
  }) async {
    final topRoute =
        SecondNavigatorObserver().history.lastOrNull?.settings.name;
    late final String? _gid;

    // url跳转方式
    if (url != null && url.isNotEmpty) {
      logger.d('goGalleryPage fromUrl $url');

      final RegExp regGalleryUrl =
          RegExp(r'https?://e[-x]hentai.org/g/([0-9]+)/[0-9a-z]+/?');
      final RegExp regGalleryPageUrl =
          RegExp(r'https://e[-x]hentai.org/s/[0-9a-z]+/\d+-\d+');

      if (regGalleryUrl.hasMatch(url)) {
        // url为画廊链接
        Get.replace(GalleryRepository(url: url));
        final matcher = regGalleryUrl.firstMatch(url);
        _gid = matcher?[1];
      } else if (regGalleryPageUrl.hasMatch(url)) {
        // url为画廊某一页的链接
        final _image = await fetchImageInfo(url);

        if (_image == null) {
          return;
        }

        final ser = _image.ser;
        final _galleryUrl =
            '${Api.getBaseUrl()}/g/${_image.gid}/${_image.token}';
        logger.d('jump to $_galleryUrl $ser');

        _gid = _image.gid ?? '0';

        Get.replace(GalleryRepository(url: _galleryUrl, jumpSer: ser));
      }

      if (replace) {
        Get.find<DepthService>().pushPageCtrl();
        await Get.offNamed(
          EHRoutes.galleryPage,
          preventDuplicates: false,
        );
        deletePageController();
        Get.find<DepthService>().popPageCtrl();
      } else {
        if (topRoute == EHRoutes.galleryPage) {
          logger.d('topRoute == EHRoutes.galleryPage');
          if (Get.isRegistered<GalleryPageController>(tag: pageCtrlDepth) &&
              Get.find<GalleryPageController>(tag: pageCtrlDepth).gid == _gid) {
            logger.d('same gallery');
            return;
          }
        }

        Get.find<DepthService>().pushPageCtrl();
        await Get.toNamed(
          EHRoutes.galleryPage,
          id: isLayoutLarge ? 2 : null,
          preventDuplicates: false,
        );
        deletePageController();
        Get.find<DepthService>().popPageCtrl();
      }
    } else {
      // item点击跳转方式
      logger.d('goGalleryPage fromItem tabTag=$tabTag');
      _gid = galleryItem?.gid;

      Get.replace(GalleryRepository(item: galleryItem, tabTag: tabTag));

      //命名路由
      if (isLayoutLarge) {
        Get.find<DepthService>().pushPageCtrl();

        logger.d('topRoute: $topRoute');
        if (topRoute == EHRoutes.galleryPage) {
          logger.d('topRoute == EHRoutes.galleryPage');
          final curTag = (int.parse(pageCtrlDepth) - 1).toString();
          if (Get.isRegistered<GalleryPageController>(tag: curTag) &&
              Get.find<GalleryPageController>(tag: curTag).gid == _gid) {
            logger.d('same gallery');
            Get.find<DepthService>().popPageCtrl();
            return;
          } else {
            await Get.offNamed(
              EHRoutes.galleryPage,
              id: 2,
              preventDuplicates: true,
            );
          }
        } else if (topRoute != EHRoutes.empty) {
          logger.d('Get.offNamed');
          await Get.offNamed(
            EHRoutes.galleryPage,
            id: 2,
            preventDuplicates: true,
          );
        } else {
          await Get.toNamed(
            EHRoutes.galleryPage,
            id: 2,
            preventDuplicates: true,
          );
        }
      } else {
        Get.find<DepthService>().pushPageCtrl();
        await Get.toNamed(
          EHRoutes.galleryPage,
          preventDuplicates: false,
        );
        deletePageController();
        Get.find<DepthService>().popPageCtrl();
      }
    }
    // deletePageController();
  }

  // 转到大图浏览
  static Future<void> goGalleryViewPage(int index, String gid) async {
    // logger.d('goGalleryViewPage $index');
    // 命名路由方式
    await Get.toNamed(EHRoutes.galleryViewExt,
        arguments: ViewRepository(
          index: index,
          loadType: LoadType.network,
          gid: gid,
        ));
  }

  static Future<void> goGalleryViewPageFile(
      int index, List<String> pics, String gid) async {
    // 命名路由方式
    await Get.toNamed(EHRoutes.galleryViewExt,
        arguments: ViewRepository(
          index: index,
          files: pics,
          loadType: LoadType.file,
          gid: gid,
        ));
  }
}
