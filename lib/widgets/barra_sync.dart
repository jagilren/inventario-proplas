import 'package:flutter/material.dart';
import '../sync_service.dart';

/// Barra que avisa si se está trabajando sin señal y cuántos movimientos
/// quedan por subir. Solo aparece cuando hay algo que informar, para no
/// robar espacio en pantalla el resto del tiempo.
class BarraSync extends StatelessWidget {
  const BarraSync({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SyncService.enLinea,
      builder: (context, enLinea, _) {
        return ValueListenableBuilder<int>(
          valueListenable: SyncService.pendientes,
          builder: (context, pendientes, __) {
            if (enLinea && pendientes == 0) return const SizedBox.shrink();

            final sinSenal = !enLinea;
            final color = sinSenal ? Colors.orange.shade700 : Colors.blue.shade700;
            final texto = sinSenal
                ? (pendientes > 0
                    ? 'Sin conexión · $pendientes por subir'
                    : 'Sin conexión · trabajando con datos guardados')
                : '$pendientes movimiento(s) por subir';

            return Material(
              color: color,
              child: InkWell(
                onTap: () => SyncService.sincronizar(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Row(
                    children: [
                      Icon(sinSenal ? Icons.cloud_off : Icons.cloud_upload,
                          color: Colors.white, size: 17),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(texto,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12.5)),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: SyncService.sincronizando,
                        builder: (_, sincronizando, ___) => sincronizando
                            ? const SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Reintentar',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
