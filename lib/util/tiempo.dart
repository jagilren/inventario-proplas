/// Utilidades de zona horaria.
///
/// Las fechas se guardan en UTC en la base. Colombia es **UTC-5 todo el año**
/// (no tiene horario de verano), así que para mostrar la hora local basta con
/// restar 5 horas al instante UTC. Se usa un desfase fijo (en vez de toLocal())
/// para que SIEMPRE se vea la hora de Colombia, sin importar la zona del
/// dispositivo o del navegador.
DateTime horaColombia(DateTime f) =>
    f.toUtc().subtract(const Duration(hours: 5));
