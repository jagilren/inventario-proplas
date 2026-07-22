import 'package:flutter/material.dart';
import '../ajustes.dart';

class ConfiguracionPage extends StatefulWidget {
  const ConfiguracionPage({super.key});
  @override
  State<ConfiguracionPage> createState() => _ConfiguracionPageState();
}

class _ConfiguracionPageState extends State<ConfiguracionPage> {
  late String _csv;
  late String _dec;
  bool _guardando = false;

  // valor -> etiqueta
  static const _seps = {';': 'Punto y coma  ( ; )', ',': 'Coma  ( , )',
    '\t': 'Tabulación'};
  static const _decs = {',': 'Coma  ( , )', '.': 'Punto  ( . )'};

  @override
  void initState() {
    super.initState();
    _csv = Ajustes.csvSep;
    _dec = Ajustes.decSep;
  }

  bool get _conflicto => _csv == _dec;

  Future<void> _guardar() async {
    if (_conflicto) return;
    setState(() => _guardando = true);
    await Ajustes.guardar(_csv, _dec);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Configuración guardada')));
      setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Exportación de informes (CSV)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          const Text('Ajusta esto para que Excel abra bien los archivos según '
              'tu región. En Colombia lo normal es «;» y decimales con «,».',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: _csv,
            decoration: const InputDecoration(
                labelText: 'Separador de columnas', border: OutlineInputBorder()),
            items: _seps.entries.map((e) => DropdownMenuItem(
                value: e.key, child: Text(e.value))).toList(),
            onChanged: (v) => setState(() => _csv = v ?? ';'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _dec,
            decoration: const InputDecoration(
                labelText: 'Separador de decimales', border: OutlineInputBorder()),
            items: _decs.entries.map((e) => DropdownMenuItem(
                value: e.key, child: Text(e.value))).toList(),
            onChanged: (v) => setState(() => _dec = v ?? ','),
          ),
          if (_conflicto) ...[
            const SizedBox(height: 12),
            const Text('El separador de columnas y el de decimales no pueden '
                'ser el mismo (se confundirían los datos).',
                style: TextStyle(color: Colors.red, fontSize: 13)),
          ],
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Ejemplo de una fila:\n'
                  'Tornillo${_csv == '\t' ? '⇥' : _csv} 12 UND${_csv == '\t' ? '⇥' : _csv} '
                  '4500${_dec}50',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: (_guardando || _conflicto) ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: const Text('Guardar configuración'),
            ),
          ),
        ],
      ),
    );
  }
}
