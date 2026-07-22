// Preferencias de exportación (configuración regional de los CSV).
import 'package:shared_preferences/shared_preferences.dart';

class Ajustes {
  /// Separador de columnas del CSV. En Colombia/LatAm suele ser ';'.
  static String csvSep = ';';

  /// Separador de decimales. En Colombia/LatAm es la coma ','.
  static String decSep = ',';

  static Future<void> cargar() async {
    final p = await SharedPreferences.getInstance();
    csvSep = p.getString('csv_sep') ?? ';';
    decSep = p.getString('dec_sep') ?? ',';
  }

  static Future<void> guardar(String csv, String dec) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('csv_sep', csv);
    await p.setString('dec_sep', dec);
    csvSep = csv;
    decSep = dec;
  }
}
