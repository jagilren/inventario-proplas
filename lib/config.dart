// Configuración de conexión a Supabase.
// publishableKey es PÚBLICA por diseño (protegida por las políticas RLS).
// Reemplaza a la antigua anon key (legacy): esta se puede rotar sin
// tumbar el proyecto.
class Config {
  static const supabaseUrl = 'https://nyvaswimcxbqxnlcnxij.supabase.co';
  static const supabasePublishableKey = 'sb_publishable_8t8Fq2d2AmnVARN8bGgP9g_itlBCgJV';

  /// Versión que se muestra al pie del login.
  ///
  /// Se mantiene a mano igual a la de pubspec.yaml. Leerla en tiempo de
  /// ejecución exigiría el paquete package_info_plus, y sumar otro plugin
  /// justo ahora agravaría el aviso de KGP que ya tenemos pendiente con
  /// file_saver y mobile_scanner.
  static const versionApp = '1.0.0';
}
