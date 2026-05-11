import '../models/checkpoint.dart';

class RouteCheckpoint {
  final String name;
  final double lat;
  final double lng;
  final double radiusMeters;

  const RouteCheckpoint({
    required this.name,
    required this.lat,
    required this.lng,
    this.radiusMeters = 2000,
  });

  Checkpoint toCheckpoint() {
    return Checkpoint(
      name: name,
      lat: lat,
      lng: lng,
      radiusMeters: radiusMeters,
    );
  }
}

class AppRoute {
  final String id;
  final String name;
  final List<RouteCheckpoint> checkpoints;

  const AppRoute({
    required this.id,
    required this.name,
    required this.checkpoints,
  });
}

// Coordinates verified from Wikipedia, official municipal sources, and
// authoritative GPS databases. Border posts use larger radii.
const routes = <AppRoute>[
  // ── Kampala → Nairobi (Northern Corridor) ──────────────────────────────
  AppRoute(
    id: 'kla_nairobi',
    name: 'Kampala → Nairobi',
    checkpoints: [
      RouteCheckpoint(name: 'Kampala', lat: 0.3476, lng: 32.5825),
      RouteCheckpoint(name: 'Mukono', lat: 0.3533, lng: 32.7553),
      RouteCheckpoint(name: 'Jinja', lat: 0.4390, lng: 33.2032),
      RouteCheckpoint(name: 'Iganga', lat: 0.6090, lng: 33.4686),
      RouteCheckpoint(
        name: 'Busia (UG Border)',
        lat: 0.4669,
        lng: 34.0900,
        radiusMeters: 2000,
      ),
      RouteCheckpoint(
        name: 'Busia (KE)',
        lat: 0.4633,
        lng: 34.1053,
        radiusMeters: 2000,
      ),
      RouteCheckpoint(
        name: 'Bumala',
        // Verified: Bumala, Busia County, Kenya — on the B1 highway
        lat: 0.3042,
        lng: 34.2060,
      ),
      RouteCheckpoint(name: 'Kisumu', lat: -0.0917, lng: 34.7680),
      RouteCheckpoint(name: 'Nakuru', lat: -0.3031, lng: 36.0800),
      RouteCheckpoint(name: 'Nairobi', lat: -1.2864, lng: 36.8172),
    ],
  ),

  // ── Kampala → Juba ─────────────────────────────────────────────────────
  AppRoute(
    id: 'kla_juba',
    name: 'Kampala → Juba',
    checkpoints: [
      RouteCheckpoint(name: 'Kampala', lat: 0.3476, lng: 32.5825),
      RouteCheckpoint(
        name: 'Luweero',
        // On the Kampala–Gulu Highway, ~64 km north of Kampala
        lat: 0.8400,
        lng: 32.4850,
      ),
      RouteCheckpoint(
        name: 'Karuma',
        // Verified: New Karuma Bridge coordinates (Wikipedia)
        lat: 2.2431,
        lng: 32.2394,
      ),
      RouteCheckpoint(name: 'Gulu', lat: 2.7746, lng: 32.2990),
      RouteCheckpoint(
        name: 'Elegu (Border)',
        // Verified from Wikipedia: Elegu, Uganda
        lat: 3.5664,
        lng: 32.0706,
        radiusMeters: 2500,
      ),
      RouteCheckpoint(
        name: 'Nimule',
        // Verified: 3.5916, 32.0639
        lat: 3.5916,
        lng: 32.0639,
      ),
      RouteCheckpoint(
        name: 'Magwi',
        // Verified from Wikipedia: Magwi, Eastern Equatoria
        lat: 4.1300,
        lng: 32.3000,
        radiusMeters: 1500,
      ),
      RouteCheckpoint(
        name: 'Pageri',
        // Remote settlement — best available estimate
        lat: 3.8667,
        lng: 31.9558,
        radiusMeters: 2000,
      ),
      RouteCheckpoint(
        name: 'Lobonok',
        // Remote settlement — best available estimate
        lat: 4.3873,
        lng: 31.5956,
        radiusMeters: 4000,
      ),
      RouteCheckpoint(
        name: 'Juba',
        // Verified: Juba city center
        lat: 4.8594,
        lng: 31.5713,
      ),
    ],
  ),

  // ── Kampala → Kigali (via Katuna) ──────────────────────────────────────
  AppRoute(
    id: 'kla_kigali_katuna',
    name: 'Kampala → Kigali (via Katuna)',
    checkpoints: [
      RouteCheckpoint(name: 'Kampala', lat: 0.3476, lng: 32.5825),
      RouteCheckpoint(
        name: 'Masaka',
        // Verified: Masaka city center (Wikipedia)
        lat: -0.3411,
        lng: 31.7361,
      ),
      RouteCheckpoint(
        name: 'Mbarara',
        // Verified: Mbarara CBD (Wikipedia)
        lat: -0.6132,
        lng: 30.6582,
      ),
      RouteCheckpoint(
        name: 'Kabale',
        // Verified: Kabale city center
        lat: -1.2486,
        lng: 29.9899,
      ),
      RouteCheckpoint(
        name: 'Katuna (Border)',
        // Verified from Wikipedia: Katuna, Uganda
        lat: -1.4228,
        lng: 30.0108,
        radiusMeters: 2500,
      ),
      RouteCheckpoint(
        name: 'Byumba (Gicumbi)',
        // Verified: Byumba / Gicumbi coordinates
        lat: -1.5763,
        lng: 30.0675,
      ),
      RouteCheckpoint(
        name: 'Kigali',
        // Verified: Kigali city center
        lat: -1.9500,
        lng: 30.0589,
      ),
    ],
  ),

  // ── Kampala → Goma ─────────────────────────────────────────────────────
  AppRoute(
    id: 'kla_goma',
    name: 'Kampala → Goma',
    checkpoints: [
      RouteCheckpoint(name: 'Kampala', lat: 0.3476, lng: 32.5825),
      RouteCheckpoint(name: 'Masaka', lat: -0.3411, lng: 31.7361),
      RouteCheckpoint(name: 'Mbarara', lat: -0.6132, lng: 30.6582),
      RouteCheckpoint(name: 'Kabale', lat: -1.2486, lng: 29.9899),
      RouteCheckpoint(
        name: 'Kisoro',
        // Verified: Kisoro town center
        lat: -1.2854,
        lng: 29.6850,
      ),
      RouteCheckpoint(
        name: 'Kyanika (Border)',
        // Verified from Wikipedia: Kyanika, Uganda
        lat: -1.3389,
        lng: 29.7389,
        radiusMeters: 2500,
      ),
      RouteCheckpoint(
        name: 'Musanze (Ruhengeri)',
        // Verified: Musanze / Ruhengeri, Rwanda
        lat: -1.4998,
        lng: 29.6350,
      ),
      RouteCheckpoint(
        name: 'Rubavu / Gisenyi',
        // Verified: Gisenyi / Rubavu city center
        lat: -1.7028,
        lng: 29.2564,
      ),
      RouteCheckpoint(
        name: 'Goma',
        // Verified: Goma city center, DRC
        lat: -1.6741,
        lng: 29.2285,
      ),
    ],
  ),
];