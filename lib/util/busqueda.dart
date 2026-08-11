/// Buscador de texto compartido por las pantallas que filtran listas que ya
/// tienen cargadas en memoria.
///
/// Es la traducción a Dart del filtro que usa el buscador de Existencias en el
/// servidor (`buscar_elementos`, ver supabase/schema_v20_buscar_paginado.sql).
/// La idea es que buscar lo mismo en dos pantallas distintas dé el mismo
/// resultado; si algún día cambian las reglas allá, hay que cambiarlas aquí.
///
/// Reglas:
///  - Las palabras pueden ir en CUALQUIER orden, pero deben estar TODAS.
///  - No importan ni las mayúsculas ni las tildes.
///  - Una palabra de UNA sola letra tiene que calzar como palabra completa:
///    así buscar "T" encuentra la "T" del accesorio y no todos los nombres
///    que casualmente llevan una t adentro. Con dos letras o más basta con
///    que el texto la contenga.
library;

const _conTilde = 'áàäâãéèëêíìïîóòöôõúùüûñ';
const _sinTilde = 'aaaaaeeeeiiiiooooouuuun';

/// Minúsculas y sin tildes, el equivalente de `lower(f_unaccent(...))`.
String _normalizar(String s) {
  final sb = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = _conTilde.indexOf(ch);
    sb.write(i >= 0 ? _sinTilde[i] : ch);
  }
  return sb.toString();
}

/// ¿Los [campos] de un elemento (nombre, material, sch, código de barras…)
/// satisfacen la [consulta]? Una consulta vacía deja pasar todo, igual que en
/// el servidor. Los campos nulos se ignoran.
bool coincideBusqueda(String consulta, List<String?> campos) {
  final q = _normalizar(consulta.trim());
  if (q.isEmpty) return true;
  final texto = _normalizar(campos.whereType<String>().join(' '));
  final palabras = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  return palabras.every((w) {
    // Letra suelta: palabra completa. El resto: basta con que aparezca.
    if (w.length == 1 && RegExp(r'[a-z]').hasMatch(w)) {
      return RegExp('\\b$w\\b').hasMatch(texto);
    }
    return texto.contains(w);
  });
}
