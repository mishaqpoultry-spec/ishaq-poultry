import 'dart:math';

/// Exact decimal helpers for form previews (the server does the real maths).
/// Values are kept as BigInt scaled by 10^scale — no floating point.
class Dec {
  Dec._(this.units, this.scale);
  final BigInt units;
  final int scale;

  static final _re = RegExp(r'^\s*(-?)(\d*)(?:\.(\d*))?\s*$');

  /// Parses "1,030.250" -> Dec. Returns null if not a number.
  static Dec? tryParse(String? s, {int scale = 3}) {
    if (s == null) return null;
    final m = _re.firstMatch(s.replaceAll(',', ''));
    if (m == null) return null;
    final whole = m.group(2) ?? '';
    var frac = m.group(3) ?? '';
    if (whole.isEmpty && frac.isEmpty) return null;
    if (frac.length > scale) return null;
    frac = frac.padRight(scale, '0');
    var v = BigInt.parse('${whole.isEmpty ? '0' : whole}$frac');
    if (m.group(1) == '-') v = -v;
    return Dec._(v, scale);
  }

  static Dec zero([int scale = 2]) => Dec._(BigInt.zero, scale);
  static Dec fromInt(int v, [int scale = 0]) => Dec._(BigInt.from(v) * BigInt.from(10).pow(scale), scale);

  Dec operator *(Dec o) => Dec._(units * o.units, scale + o.scale);
  Dec operator +(Dec o) => _align(o, (a, b) => a + b);
  Dec operator -(Dec o) => _align(o, (a, b) => a - b);

  Dec _align(Dec o, BigInt Function(BigInt, BigInt) f) {
    final s = max(scale, o.scale);
    return Dec._(f(_up(s), o._up(s)), s);
  }

  BigInt _up(int s) => units * BigInt.from(10).pow(s - scale);

  /// Round half-up to [s] decimals (same as the server's ROUND_HALF_UP).
  Dec round(int s) {
    if (s >= scale) return Dec._(_up(s), s);
    final div = BigInt.from(10).pow(scale - s);
    final half = div ~/ BigInt.two;
    final r = units.isNegative ? -((-units + half) ~/ div) : (units + half) ~/ div;
    return Dec._(r, s);
  }

  bool get isZero => units == BigInt.zero;
  bool get isNegative => units.isNegative;
  int compareTo(Dec o) => _up(max(scale, o.scale)).compareTo(o._up(max(scale, o.scale)));

  @override
  String toString() {
    final neg = units.isNegative;
    final s = units.abs().toString().padLeft(scale + 1, '0');
    final txt = scale == 0 ? s : '${s.substring(0, s.length - scale)}.${s.substring(s.length - scale)}';
    return neg ? '-$txt' : txt;
  }
}
