import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

/// FMTC cache store names. Each tile style gets its own on-disk store; all are
/// created at startup in `main.dart`.
const String cartoLightCacheName = 'carto_light'; // labelled basemap (detail maps)
const String cartoBaseCacheName = 'carto_base'; // label-free basemap (national map)
const String cartoLabelsCacheName = 'carto_labels'; // labels-only overlay

const List<String> _subdomains = ['a', 'b', 'c', 'd'];

/// The `{r}` placeholder is filled with "@2x" on high-density displays to pull
/// native retina tiles from CARTO.
const String _lightUrl =
    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
const String _baseUrl =
    'https://{s}.basemaps.cartocdn.com/light_nolabels/{z}/{x}/{y}{r}.png';
const String _labelsUrl =
    'https://{s}.basemaps.cartocdn.com/light_only_labels/{z}/{x}/{y}{r}.png';

TileLayer _carto(BuildContext context, String url, String store) {
  return TileLayer(
    urlTemplate: url,
    subdomains: _subdomains,
    retinaMode: RetinaMode.isHighDensity(context),
    userAgentPackageName: 'open_hansard', tileDisplay: const TileDisplay.fadeIn(),
    tileProvider: FMTCTileProvider(
      stores: {store: BrowseStoreStrategy.readUpdateCreate},
    ),
  );
}

/// Labelled CARTO light basemap, used by the small detail maps.
TileLayer buildCartoLightTileLayer(BuildContext context) =>
    _carto(context, _lightUrl, cartoLightCacheName);

/// Label-free CARTO basemap, so coloured boundary fills read cleanly. Pair with
/// [buildCartoLabelsTileLayer] placed *above* the polygon layer.
TileLayer buildCartoBaseTileLayer(BuildContext context) =>
    _carto(context, _baseUrl, cartoBaseCacheName);

/// Labels-only overlay drawn on top of the boundary fills so place names stay
/// readable.
TileLayer buildCartoLabelsTileLayer(BuildContext context) =>
    _carto(context, _labelsUrl, cartoLabelsCacheName);
