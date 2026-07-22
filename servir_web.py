#!/usr/bin/env python3
# Sirve build/web en el puerto 3000. No requiere zip: cada 'flutter build web'
# queda servido al instante. Resuelve la carpeta por RUTA en cada petición
# (con directory=), así NO se "cuelga" aunque flutter recree build/web.
#
# Cabeceras no-cache SOLO en los archivos que deben revisarse siempre
# (index.html y el service worker) para detectar versiones nuevas al instante.
# El resto lo cachea el service worker de Flutter (carga rápida + offline).
import http.server, socketserver, os, functools

RAIZ = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'build', 'web')

class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        ruta = self.path.split('?')[0]
        if ruta in ('/', '/index.html', '/flutter_service_worker.js',
                    '/flutter_bootstrap.js', '/version.json'):
            self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
            self.send_header('Pragma', 'no-cache')
            self.send_header('Expires', '0')
        super().end_headers()

socketserver.TCPServer.allow_reuse_address = True
handler = functools.partial(Handler, directory=RAIZ)
with socketserver.TCPServer(('0.0.0.0', 3000), handler) as httpd:
    print(f'Sirviendo {RAIZ} en http://0.0.0.0:3000')
    httpd.serve_forever()
