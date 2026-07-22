// Preferencias de exportación (configuración regional de los CSV).
// Es POR USUARIO: se guarda con la llave del id de cada usuario, así cada
// quien tiene su propia configuración y sus descargas salen según ella.
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Ajustes {
  /// Separador de columnas del CSV. En Colombia/LatAm suele ser ';'.
  static String csvSep = ';';

  /// Separador de decimales. En Colombia/LatAm es la coma ','.
  static String decSep = ',';

  static String get _uid =>
      Supabase.instance.client.auth.currentUser?.id ?? 'global';

  /// Carga la configuración del usuario actual (llamar tras el login).
  static Future<void> cargar() async {
    final p = await SharedPreferences.getInstance();
    csvSep = p.getString('csv_sep_$_uid') ?? ';';
    decSep = p.getString('dec_sep_$_uid') ?? ',';
  }

  static Future<void> guardar(String csv, String dec) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('csv_sep_$_uid', csv);
    await p.setString('dec_sep_$_uid', dec);
    csvSep = csv;
    decSep = dec;
  }
}
