import 'package:flutter_test/flutter_test.dart';
import 'package:homeserver_client/features/home/network_route_classifier.dart';

void main() {
  group('networkRouteLabel', () {
    test('recognizes Tailscale IPv4 and IPv6', () {
      expect(networkRouteLabel('100.100.10.2'), 'Tailscale');
      expect(networkRouteLabel('fd7a:115c:a1e0::1234'), 'Tailscale');
    });

    test('recognizes private LAN addresses', () {
      expect(networkRouteLabel('192.168.1.10'), 'LAN');
      expect(networkRouteLabel('10.0.0.5'), 'LAN');
      expect(networkRouteLabel('172.20.1.2'), 'LAN');
      expect(networkRouteLabel('169.254.1.2'), 'LAN');
      expect(networkRouteLabel('fd12:3456:789a::1'), 'LAN');
      expect(networkRouteLabel('fe80::1'), 'LAN');
      expect(networkRouteLabel('pocketlink.local'), 'LAN');
    });

    test('does not mislabel public or unknown hosts as LAN', () {
      expect(networkRouteLabel('8.8.8.8'), 'Remote');
      expect(networkRouteLabel('example.com'), 'Remote');
      expect(networkRouteLabel('2001:4860:4860::8888'), 'Remote');
    });
  });
}
