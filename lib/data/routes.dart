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

// NOTE: Border/remote checkpoints use larger radius to avoid misses.
const routes = <AppRoute>[
  AppRoute(
    id: 'kla_nairobi',
    name: 'Kampala → Nairobi',
    checkpoints: [
      RouteCheckpoint(
        name: 'Kampala',
        lat: 0.3475964,
        lng: 32.5825197,
      ), // Kampala

      RouteCheckpoint(name: 'Namanve', lat: 0.3575, lng: 32.694167), // Namanve

      RouteCheckpoint(
        name: 'Mukono',
        lat: 0.3533,
        lng: 32.7553,
      ), // Mukono (approx)

      RouteCheckpoint(name: 'Jinja', lat: 0.43902, lng: 33.2032), // Jinja

      RouteCheckpoint(
        name: 'Iganga',
        lat: 0.6099,
        lng: 33.4686,
      ), // Iganga (approx)

      RouteCheckpoint(
        name: 'Busitema',
        lat: 0.55778,
        lng: 34.03556,
      ), // Busitema (from DMS / approx)

      RouteCheckpoint(
        name: 'Busia (UG Border)',
        lat: 0.4669,
        lng: 34.0900,
        radiusMeters: 2000,
      ), // Busia (UG)

      RouteCheckpoint(name: 'Bumala', lat: 0.38333, lng: 34.35), // Bumala (KE)

      RouteCheckpoint(
        name: 'Kisumu',
        lat: -0.0917,
        lng: 34.7680,
      ), // Kisumu (approx)

      RouteCheckpoint(
        name: 'Nakuru',
        lat: -0.3031,
        lng: 36.0800,
      ), // Nakuru (approx)

      RouteCheckpoint(
        name: 'Nairobi',
        lat: -1.2921,
        lng: 36.8219,
      ), // Nairobi (approx)
    ],
  ),

  AppRoute(
    id: 'kla_juba',
    name: 'Kampala → Juba',
    checkpoints: [
      RouteCheckpoint(name: 'Kampala', lat: 0.3475964, lng: 32.5825197),

      RouteCheckpoint(name: 'Luweero', lat: 0.8383, lng: 32.4917), // approx

      RouteCheckpoint(
        name: 'Karuma',
        lat: 2.2350,
        lng: 32.2560,
      ), // Karuma (approx near falls/bridge)

      RouteCheckpoint(name: 'Gulu', lat: 2.7746, lng: 32.2980), // Gulu (approx)

      RouteCheckpoint(
        name: 'Elegu (Border)',
        lat: 3.566389,
        lng: 32.070556,
        radiusMeters: 2500,
      ), // Elegu

      RouteCheckpoint(
        name: 'Nimule',
        lat: 3.6000,
        lng: 32.0500,
      ), // Nimule (approx)

      RouteCheckpoint(name: 'Magwi', lat: 4.1300, lng: 32.3000), // Magwi

      RouteCheckpoint(
        name: 'Pageri',
        lat: 3.8667486,
        lng: 31.9558431,
      ), // Pageri

      RouteCheckpoint(
        name: 'Lobonok',
        lat: 4.3873,
        lng: 31.5956,
        radiusMeters: 4000,
      ), // Lobonok

      RouteCheckpoint(name: 'Juba', lat: 4.8517, lng: 31.5825), // Juba (approx)
    ],
  ),

  AppRoute(
    id: 'kla_kigali_katuna',
    name: 'Kampala → Kigali (via Katuna)',
    checkpoints: [
      RouteCheckpoint(name: 'Kampala', lat: 0.3475964, lng: 32.5825197),

      RouteCheckpoint(
        name: 'Masaka',
        lat: -0.3333,
        lng: 31.7333,
      ), // Masaka UG (approx)

      RouteCheckpoint(
        name: 'Mbarara',
        lat: -0.6072,
        lng: 30.6545,
      ), // Mbarara (approx)

      RouteCheckpoint(
        name: 'Kabale',
        lat: -1.2490,
        lng: 29.9890,
      ), // Kabale (approx)

      RouteCheckpoint(
        name: 'Katuna (Border)',
        lat: -1.422778,
        lng: 30.010833,
        radiusMeters: 2500,
      ), // Gatuna/Katuna border area

      RouteCheckpoint(
        name: 'Byumba (Gicumbi)',
        lat: -1.5760,
        lng: 30.0670,
      ), // approx

      RouteCheckpoint(name: 'Kigali', lat: -1.9441, lng: 30.0619),
    ],
  ),

  AppRoute(
    id: 'kla_goma',
    name: 'Kampala → Goma',
    checkpoints: [
      RouteCheckpoint(name: 'Kampala', lat: 0.3475964, lng: 32.5825197),
      RouteCheckpoint(name: 'Masaka', lat: -0.3333, lng: 31.7333),
      RouteCheckpoint(name: 'Mbarara', lat: -0.6072, lng: 30.6545),
      RouteCheckpoint(name: 'Kabale', lat: -1.2490, lng: 29.9890),

      RouteCheckpoint(name: 'Kisoro', lat: -1.2850, lng: 29.6850), // approx

      RouteCheckpoint(
        name: 'Kyanika (Border)',
        lat: -1.338889,
        lng: 29.738889,
        radiusMeters: 2500,
      ), // Kyanika

      RouteCheckpoint(name: 'Musanze', lat: -1.4990, lng: 29.6340), // approx

      RouteCheckpoint(
        name: 'Rubavu / Gisenyi',
        lat: -1.6792,
        lng: 29.2629,
      ), // approx

      RouteCheckpoint(name: 'Goma', lat: -1.67944, lng: 29.23361), // Goma
    ],
  ),
];
