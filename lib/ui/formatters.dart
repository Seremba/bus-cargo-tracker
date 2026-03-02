class Fmt {
  static String dt16(DateTime? d) =>
      d == null ? '—' : d.toLocal().toString().substring(0, 16);
}