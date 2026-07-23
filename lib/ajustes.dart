// Configuración regional de exportaciones (CSV), guardada POR USUARIO en la
// base de datos (columna en profiles). Así un admin puede cambiar la config de
// cualquier usuario, y cada quien descarga con la suya desde cualquier equipo.
import 'package:supabase_flutter/supabase_flutter.dart';

class Ajustes {
  static String csvSep = ';';
  static String decSep = ',';

  static SupabaseClient get _sb => Supabase.instance.client;

  /// Carga la config del usuario actual (llamar tras el login).
  static Future<void> cargar() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final r = await _sb.from('profiles')
          .select('csv_sep, dec_sep').eq('id', uid).maybeSingle();
      csvSep = (r?['csv_sep'] ?? ';') as String;
      decSep = (r?['dec_sep'] ?? ',') as String;
    } catch (_) {/* sin red: se quedan los últimos valores */}
  }

  /// Config de OTRO usuario (para que el admin la vea/edite).
  static Future<(String, String)> configDe(String userId) async {
    final r = await _sb.from('profiles')
        .select('csv_sep, dec_sep').eq('id', userId).maybeSingle();
    return ((r?['csv_sep'] ?? ';') as String, (r?['dec_sep'] ?? ',') as String);
  }

  /// Guarda la config de un usuario (por defecto, el actual).
  static Future<void> guardar(String csv, String dec, {String? paraUsuario}) async {
    final uid = paraUsuario ?? _sb.auth.currentUser?.id;
    if (uid == null) return;
    await _sb.from('profiles').update({'csv_sep': csv, 'dec_sep': dec}).eq('id', uid);
    // Si es la del usuario actual, actualizar la caché en memoria.
    if (uid == _sb.auth.currentUser?.id) {
      csvSep = csv;
      decSep = dec;
    }
  }
}
