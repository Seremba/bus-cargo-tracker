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
    this.radiusMeters = 800,
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

/// 4 fixed routes (no Google Maps needed).
/// IMPORTANT: Verify/adjust coords for smaller places using the guide below.
const routes = <AppRoute>[
  // ============================================================
  // Route 1: Kampala -> Nairobi
  // ============================================================
  AppRoute(
    id: 'kla_nairobi',
    name: 'Kampala → Nairobi',
    checkpoints: [
      RouteCheckpoint(name: 'Kampala', lat: 0.3475964, lng: 32.5825197), // Kampala
      RouteCheckpoint(name: 'Namanve', lat: 0.3783, lng: 32.6794), // Namanve (approx)
      RouteCheckpoint(name: 'Mukono', lat: 0.3533, lng: 32.7553), // Mukono (approx)
      RouteCheckpoint(name: 'Jinja', lat: 0.4244, lng: 33.2042), // Jinja (approx)
      RouteCheckpoint(name: 'Iganga', lat: 0.6099, lng: 33.4686), // Iganga (approx)
      RouteCheckpoint(name: 'Busitema', lat: 0.55778, lng: 34.03556), // Busitema (from DMS)
      RouteCheckpoint(name: 'Busia (UG Border)', lat: 0.42231, lng: 34.0297), // Busia (UG)
      RouteCheckpoint(name: 'Bumala', lat: 0.38333, lng: 34.35), // Bumala (KE)
      RouteCheckpoint(name: 'Kisumu', lat: -0.0917, lng: 34.7680), // Kisumu (approx)
      RouteCheckpoint(name: 'Nakuru', lat: -0.3031, lng: 36.0800), // Nakuru (approx)
      RouteCheckpoint(name: 'Nairobi', lat: -1.2921, lng: 36.8219), // Nairobi (approx)
    ],
  ),

  // ============================================================
  // Route 2: Kampala -> Juba
  // ============================================================
  AppRoute(
    id: 'kla_juba',
    name: 'Kampala → Juba',
    checkpoints: [
      RouteCheckpoint(name: 'Kampala', lat: 0.3475964, lng: 32.5825197),
      RouteCheckpoint(name: 'Luweero', lat: 0.8383, lng: 32.4917), // approx
      RouteCheckpoint(name: 'Karuma', lat: 2.2350, lng: 32.2560), // Karuma (approx near falls/bridge)
      RouteCheckpoint(name: 'Gulu', lat: 2.7746, lng: 32.2980), // Gulu (approx)
      RouteCheckpoint(name: 'Elegu (Border)', lat: 3.6040, lng: 32.9280), // Elegu (approx)
      RouteCheckpoint(name: 'Nimule', lat: 3.6000, lng: 32.0500), // Nimule (approx)
      RouteCheckpoint(name: 'Magwi', lat: 3.5200, lng: 31.8400), // Magwi (approx)
      RouteCheckpoint(name: 'Pageri', lat: 3.9167, lng: 31.8167), // Pageri (approx)
      RouteCheckpoint(
        name: 'Lobonok',
        lat: 0.0,
        lng: 0.0,
      ), // TODO: Replace with confirmed Lobonok coords
      RouteCheckpoint(name: 'Juba', lat: 4.8517, lng: 31.5825), // Juba (approx)
    ],
  ),

  // ============================================================
  // Route 3: Kampala -> Kigali (via Katuna)
  // ============================================================
  AppRoute(
    id: 'kla_kigali_katuna',
    name: 'Kampala → Kigali (via Katuna)',
    checkpoints: [
      RouteCheckpoint(name: 'Kampala', lat: 0.3475964, lng: 32.5825197),
      RouteCheckpoint(name: 'Masaka', lat: -0.3333, lng: 31.7333), // Masaka UG (approx)
      RouteCheckpoint(name: 'Mbarara', lat: -0.6072, lng: 30.6545), // Mbarara (approx)
      RouteCheckpoint(name: 'Kabale', lat: -1.2490, lng: 29.9890), // Kabale (approx)
      RouteCheckpoint(name: 'Katuna (Border)', lat: -1.3990, lng: 30.0770), // Gatuna/Katuna border area (approx)
      RouteCheckpoint(name: 'Byumba (Gicumbi)', lat: -1.5760, lng: 30.0670), // approx
      RouteCheckpoint(name: 'Kigali', lat: -1.9441, lng: 30.0619), // Kigali (approx)
    ],
  ),

  // ============================================================
  // Route 4: Kampala -> Goma
  // ============================================================
  AppRoute(
    id: 'kla_goma',
    name: 'Kampala → Goma',
    checkpoints: [
      RouteCheckpoint(name: 'Kampala', lat: 0.3475964, lng: 32.5825197),
      RouteCheckpoint(name: 'Masaka', lat: -0.3333, lng: 31.7333),
      RouteCheckpoint(name: 'Mbarara', lat: -0.6072, lng: 30.6545),
      RouteCheckpoint(name: 'Kabale', lat: -1.2490, lng: 29.9890),
      RouteCheckpoint(name: 'Kisoro', lat: -1.2850, lng: 29.6850), // approx
      RouteCheckpoint(name: 'Kyanika (Border)', lat: -1.4370, lng: 29.6060), // approx
      RouteCheckpoint(name: 'Musanze', lat: -1.4990, lng: 29.6340), // approx
      RouteCheckpoint(name: 'Rubavu / Gisenyi', lat: -1.6792, lng: 29.2629), // approx
      RouteCheckpoint(name: 'Goma', lat: -1.6790, lng: 29.2220), // approx
    ],
  ),
];
