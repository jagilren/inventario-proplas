// Convierte docs/sdd-modulo-equipos.md en web/sdd.html, la copia pública que
// se comparte por enlace.
//
// POR QUÉ EXISTE ESTE SCRIPT: la versión web del SDD se armaba A MANO a
// partir del .md, y vivía como artifact de una cuenta de Claude.ai. Dos
// problemas: el enlace dependía de con qué cuenta se hubiera publicado (ya
// quedó uno congelado y hubo que abrir otro), y cada cambio del documento
// obligaba a rehacer el HTML a pulso. Ahora el .md es la única fuente y el
// HTML se genera.
//
// DÓNDE QUEDA PUBLICADO: en `web/`, que es la carpeta que Flutter copia tal
// cual dentro de `build/web`. O sea que el CI/CD que ya publica la app en
// Cloudflare Pages publica también esta página, sin Wrangler a mano y sin
// depender de ninguna cuenta de Claude.
//
//   Uso:  dart run tool/sdd_a_web.dart
//   Sale: web/sdd.html   →   https://inventario-proplas.pages.dev/sdd.html
import 'dart:io';
import 'package:markdown/markdown.dart' as md;

const _entrada = 'docs/sdd-modulo-equipos.md';
const _salida = 'web/sdd.html';

void main() {
  final fuente = File(_entrada);
  if (!fuente.existsSync()) {
    stderr.writeln('No encuentro $_entrada. Corre esto desde la raíz del proyecto.');
    exit(1);
  }
  final texto = fuente.readAsStringSync();

  // gitHubWeb trae tablas, listas de tareas, saltos de línea y —lo que hace
  // falta para el índice— un `id` en cada título.
  final cuerpo = md.markdownToHtml(
    texto,
    extensionSet: md.ExtensionSet.gitHubWeb,
  );

  final indice = _indice(texto);
  final fecha = DateTime.now().toIso8601String().substring(0, 10);

  File(_salida).writeAsStringSync(_pagina(cuerpo, indice, fecha));
  final kb = (File(_salida).lengthSync() / 1024).round();
  stdout.writeln('✓ $_salida ($kb kB) · ${indice.length} entradas de índice');
}

/// El índice sale de los títulos de nivel 2 y 3 del .md, con el mismo `id`
/// (sigue abajo). Los títulos que están DENTRO de una cita (`> ### …`) se
/// quedan fuera a propósito: son destacados dentro de una sección, no
/// secciones. Por eso el cuerpo tiene un `id` más que el índice — no es un
/// enlace perdido.
/// El resto de la regla:
/// que les pone gitHubWeb (minúsculas, sin tildes ni signos, guiones por
/// espacios) — si estas dos reglas se separan, los enlaces del índice
/// apuntan a la nada.
List<({int nivel, String texto, String id})> _indice(String md) {
  final out = <({int nivel, String texto, String id})>[];
  var enCodigo = false;
  for (final linea in md.split('\n')) {
    if (linea.trimLeft().startsWith('```')) {
      enCodigo = !enCodigo;
      continue;
    }
    if (enCodigo) continue;
    final m = RegExp(r'^(#{2,3})\s+(.+?)\s*$').firstMatch(linea);
    if (m == null) continue;
    final texto = m.group(2)!;
    out.add((nivel: m.group(1)!.length, texto: _sinMarcas(texto), id: _id(texto)));
  }
  return out;
}

/// Quita el formato del título para el índice: "**5.8** `activos`" no debe
/// leerse con asteriscos ni comillas invertidas.
String _sinMarcas(String s) => s
    .replaceAll(RegExp(r'[*_`]'), '')
    .replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1')
    .trim();

/// La misma regla de `id` que usa el paquete markdown
/// (`generateAnchorHash`), copiada al pie de la letra porque cualquier
/// diferencia deja los enlaces del índice apuntando a la nada. Dos detalles
/// que NO son obvios y que ya rompieron 11 enlaces:
///
/// - Las tildes **se borran**, no se convierten: "próximo" da "prximo".
/// - Se reemplaza espacio por espacio, no grupos: "Origen ➡️ destino" deja
///   dos espacios al quitar el emoji, y sale "origen--destino" con dos
///   guiones.
String _id(String s) => _sinMarcas(s)
    .toLowerCase()
    .trim()
    .replaceAll(RegExp(r'[^a-z0-9 _-]'), '')
    .replaceAll(RegExp(r'\s'), '-');

String _pagina(String cuerpo, List<({int nivel, String texto, String id})> indice, String fecha) {
  final enlaces = indice
      .map((e) =>
          '<a class="n${e.nivel}" href="#${e.id}">${_escapar(e.texto)}</a>')
      .join('\n      ');
  return '''<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<!-- Documento interno: que no lo indexen los buscadores. -->
<meta name="robots" content="noindex, nofollow">
<title>SDD · Módulo de Equipos · Inventario PROPLAS</title>
<style>
  /* Generado por tool/sdd_a_web.dart — no editar a mano: se sobrescribe. */
  :root{
    --teal:#00695c; --teal-600:#00897b; --teal-ink:#004d40;
    --ink:#132320; --muted:#5c6d69; --line:#e0e7e5;
    --card:#ffffff; --canvas:#eef2f1; --chip:#eaf1ef; --code:#f4f7f6;
    --sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
    --mono:"SFMono-Regular",Menlo,Consolas,"Liberation Mono",monospace;
  }
  @media (prefers-color-scheme: dark){
    :root{
      --teal:#4db6ac; --teal-600:#80cbc4; --teal-ink:#b2dfdb;
      --ink:#e6efed; --muted:#9fb3af; --line:#2a3b38;
      --card:#132320; --canvas:#0d1817; --chip:#1b2c29; --code:#162422;
    }
  }
  *{box-sizing:border-box}
  body{margin:0;background:var(--canvas);color:var(--ink);font:16px/1.65 var(--sans)}
  .marco{max-width:1180px;margin:0 auto;padding:24px 16px 64px;display:grid;
    grid-template-columns:260px minmax(0,1fr);gap:32px;align-items:start}
  /* En celular el índice se va arriba y se pliega. */
  @media (max-width:860px){ .marco{grid-template-columns:minmax(0,1fr);gap:16px} }

  header.tapa{grid-column:1/-1;background:var(--teal);color:#fff;border-radius:14px;
    padding:22px 24px;margin-bottom:8px}
  header.tapa h1{margin:0 0 4px;font-size:24px;letter-spacing:.2px}
  header.tapa p{margin:0;opacity:.9;font-size:14px}

  nav.indice{position:sticky;top:16px;background:var(--card);border:1px solid var(--line);
    border-radius:14px;padding:14px;max-height:calc(100vh - 32px);overflow:auto}
  @media (max-width:860px){ nav.indice{position:static;max-height:none} }
  nav.indice strong{display:block;font-size:12px;text-transform:uppercase;
    letter-spacing:.8px;color:var(--muted);margin:0 0 10px}
  nav.indice a{display:block;padding:5px 8px;border-radius:8px;text-decoration:none;
    color:var(--ink);font-size:13.5px;line-height:1.35}
  nav.indice a:hover{background:var(--chip);color:var(--teal-ink)}
  nav.indice a.n3{padding-left:22px;font-size:12.5px;color:var(--muted)}

  main{background:var(--card);border:1px solid var(--line);border-radius:14px;
    padding:8px 28px 32px;min-width:0}
  @media (max-width:600px){ main{padding:8px 16px 24px} }
  main h2{margin:34px 0 10px;padding-top:10px;border-top:1px solid var(--line);
    font-size:22px;color:var(--teal-ink)}
  main h2:first-of-type{border-top:0}
  main h3{margin:26px 0 8px;font-size:17.5px;color:var(--teal)}
  main h4{margin:18px 0 6px;font-size:15px}
  main p,main li{overflow-wrap:break-word}
  main a{color:var(--teal);text-decoration-thickness:1px}
  main code{font:13.5px/1.5 var(--mono);background:var(--code);padding:1px 5px;
    border-radius:5px}
  main pre{background:var(--code);border:1px solid var(--line);border-radius:10px;
    padding:12px 14px;overflow-x:auto}
  main pre code{background:none;padding:0}
  main blockquote{margin:16px 0;padding:12px 16px;background:var(--chip);
    border-left:4px solid var(--teal);border-radius:0 10px 10px 0}
  main blockquote p{margin:6px 0}
  /* Las tablas del SDD son anchas: su propio scroll, y el cuerpo no se mueve. */
  .tabla{overflow-x:auto;margin:16px 0}
  table{border-collapse:collapse;width:100%;font-size:14.5px}
  th,td{border:1px solid var(--line);padding:8px 10px;text-align:left;vertical-align:top}
  th{background:var(--chip);color:var(--teal-ink)}
  hr{border:0;border-top:1px solid var(--line);margin:28px 0}
  img{max-width:100%}

  /* Para imprimir o guardar en PDF: sin índice y sin cajas. */
  @media print{
    body{background:#fff}
    .marco{display:block;max-width:none;padding:0}
    nav.indice{display:none}
    header.tapa{background:none;color:#000;padding:0;border-radius:0}
    main{border:0;border-radius:0;padding:0}
    main h2{page-break-after:avoid}
  }
</style>
</head>
<body>
<div class="marco">
  <header class="tapa">
    <h1>SDD · Módulo de Equipos</h1>
    <p>Inventario PROPLAS · documento de diseño · generado el $fecha</p>
  </header>
  <nav class="indice">
    <strong>Contenido</strong>
      $enlaces
  </nav>
  <main>
$cuerpo
  </main>
</div>
<script>
  // Las tablas salen "desnudas" del markdown; se les envuelve para que en
  // celular se desplacen solas en vez de estirar la página.
  for (const t of document.querySelectorAll('main table')) {
    const caja = document.createElement('div');
    caja.className = 'tabla';
    t.parentNode.insertBefore(caja, t);
    caja.appendChild(t);
  }
</script>
</body>
</html>
''';
}

String _escapar(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
