/// Classifies the connection route from its literal IP address.
String networkRouteLabel(String host) {
  final value = host.trim().toLowerCase();
  final octets = value.split('.');
  if (octets.length == 4) {
    final parts = octets.map(int.tryParse).toList(growable: false);
    if (parts.every((part) => part != null && part >= 0 && part <= 255)) {
      final a = parts[0]!;
      final b = parts[1]!;
      if (a == 100 && b >= 64 && b <= 127) return 'Tailscale';
      if (a == 10 ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168) ||
          (a == 169 && b == 254)) {
        return 'LAN';
      }
    }
  }

  // Tailscale IPv6 addresses are allocated from fd7a:115c:a1e0::/48.
  final compact = value.replaceAll('[', '').replaceAll(']', '');
  if (compact.startsWith('fd7a:115c:a1e0:') ||
      compact == 'fd7a:115c:a1e0::') {
    return 'Tailscale';
  }
  if (compact == '::1' || compact == 'localhost') return 'Local';
  if (compact.endsWith('.local')) return 'LAN';
  if (compact.startsWith('fc') ||
      compact.startsWith('fd') ||
      compact.startsWith('fe80:')) {
    return 'LAN';
  }
  return 'Remote';
}
