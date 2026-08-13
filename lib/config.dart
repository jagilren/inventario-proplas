// Configuración de conexión a Supabase.
// publishableKey es PÚBLICA por diseño (protegida por las políticas RLS).
// Reemplaza a la antigua anon key (legacy): esta se puede rotar sin
// tumbar el proyecto.
class Config {
  static const supabaseUrl = 'https://nyvaswimcxbqxnlcnxij.supabase.co';
  static const supabasePublishableKey = 'sb_publishable_8t8Fq2d2AmnVARN8bGgP9g_itlBCgJV';

  /// SOLO PARA PROBAR los mensajes de error del login, sin tener que pausar
  /// la base ni apagar el wifi.
  ///
  /// Valores: null (normal) · 'servidor' · 'sinInternet' · 'credenciales'
  ///
  /// ⚠️ DEBE quedar en null en producción: con un valor puesto, NADIE puede
  /// entrar — el login falla siempre a propósito. Para revisarlo se compila
  /// una versión aparte y se despliega a una rama de prueba, nunca a main.
  ///
  /// No es `const` a propósito: siendo const, el analizador marcaría como
  /// código muerto el bloque que la usa.
  static String? simularFalloLogin;
}
