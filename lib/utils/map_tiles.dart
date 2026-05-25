import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

const String cartoLightCacheName = 'carto_light';
const String cartoLightUrlTemplate =
    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';
const List<String> cartoLightSubdomains = ['a', 'b', 'c', 'd'];

TileLayer buildCartoLightTileLayer() {
  return TileLayer(
    urlTemplate: cartoLightUrlTemplate,
    subdomains: cartoLightSubdomains,
    userAgentPackageName: 'open_hansard',
    tileProvider: FMTCTileProvider(stores: const {cartoLightCacheName: BrowseStoreStrategy.readUpdateCreate,},),
  );
}
