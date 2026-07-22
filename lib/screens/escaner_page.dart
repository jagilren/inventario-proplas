import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Pantalla de escaneo de código de barras.
///
/// Diseño no intrusivo: la cámara solo vive mientras esta pantalla está
/// abierta. Al leer el primer código, devuelve el valor y se cierra sola,
/// así la cámara no queda encendida gastando batería.
class EscanerPage extends StatefulWidget {
  final String titulo;
  const EscanerPage({super.key, this.titulo = 'Escanear código'});

  @override
  State<EscanerPage> createState() => _EscanerPageState();
}

class _EscanerPageState extends State<EscanerPage> {
  final _controlador = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _yaLeido = false;

  void _alDetectar(BarcodeCapture captura) {
    if (_yaLeido) return;
    final codigos = captura.barcodes;
    if (codigos.isEmpty) return;
    final valor = codigos.first.rawValue;
    if (valor == null || valor.isEmpty) return;
    _yaLeido = true; // evita leer el mismo código varias veces
    Navigator.pop(context, valor);
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo),
        actions: [
          IconButton(
            tooltip: 'Linterna',
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controlador.toggleTorch(),
          ),
          IconButton(
            tooltip: 'Cambiar cámara',
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controlador.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _controlador,
            onDetect: _alDetectar,
            errorBuilder: (context, error, _) => _error(error),
          ),
          // Marco guía para que el usuario sepa dónde apuntar
          Container(
            width: 250,
            height: 160,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const Positioned(
            bottom: 40,
            child: Text('Apunta al código de barras',
                style: TextStyle(color: Colors.white, fontSize: 15,
                    backgroundColor: Colors.black54)),
          ),
        ],
      ),
    );
  }

  Widget _error(MobileScannerException error) {
    final sinCamara = error.errorCode == MobileScannerErrorCode.unsupported ||
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              sinCamara
                  ? 'Este equipo no tiene cámara o no diste permiso.\n'
                    'Puedes buscar el elemento por su nombre.'
                  : 'No se pudo abrir la cámara.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }
}
