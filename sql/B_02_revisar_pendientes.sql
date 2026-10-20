-- =============================================================================
-- Servidor B - EVENTOS PENDIENTES ANTES DEL PRIMER ARRANQUE.
-- Ejecutar ANTES de "docker compose up". La parte 1 es solo lectura.
--
-- Al arrancar, el servicio toma de deviceevent TODO evento geofenceEnter/geofenceExit con
--   isEnviado = 0                               -> alerta SignalR + fila en visitas_geocerca
--   isEnviadoWhatsapp = 0 AND intentosWhatsapp < 5 -> WhatsApp a los destinos configurados
-- sin importar su antigüedad. Si en B hay histórico sin marcar, se enviarán WhatsApp
-- reales por eventos viejos y se crearán visitas por ellos.
-- =============================================================================

-- 1) ¿Cuántos pendientes hay y de qué fechas? (solo lectura)
SELECT 'SignalR / visitas (isEnviado=0)' AS cola,
       COUNT(*) AS pendientes,
       FROM_UNIXTIME(MIN(serverTime)) AS mas_antiguo,
       FROM_UNIXTIME(MAX(serverTime)) AS mas_reciente
FROM deviceevent
WHERE eventType IN ('geofenceEnter', 'geofenceExit') AND isEnviado = 0
UNION ALL
SELECT 'WhatsApp (isEnviadoWhatsapp=0, intentos<5)',
       COUNT(*),
       FROM_UNIXTIME(MIN(serverTime)),
       FROM_UNIXTIME(MAX(serverTime))
FROM deviceevent
WHERE eventType IN ('geofenceEnter', 'geofenceExit')
  AND isEnviadoWhatsapp = 0 AND intentosWhatsapp < 5;

-- 2) ¿Hay otro proceso en B que ya consuma isEnviado / isEnviadoWhatsapp?
--    Si los pendientes de la parte 1 están en 0 y van subiendo/bajando solos con el tiempo,
--    algo más en B ya está marcando esos campos (otro servicio de alertas).
--    En ese caso NO levantes este servicio hasta decidir cuál de los dos debe hacerlo:
--    competirían por los mismos eventos.

-- 3) OPCIONAL (DML, decisión tuya): marcar el histórico como ya procesado para que
--    el servicio solo atienda eventos nuevos. Ajusta el corte antes de ejecutar.
--
-- SET @corte = UNIX_TIMESTAMP(NOW() - INTERVAL 10 MINUTE);
-- UPDATE deviceevent
--    SET isEnviado = 1
--  WHERE eventType IN ('geofenceEnter', 'geofenceExit') AND isEnviado = 0 AND serverTime < @corte;
-- UPDATE deviceevent
--    SET isEnviadoWhatsapp = 1, fechaEnvioWhatsapp = NOW()
--  WHERE eventType IN ('geofenceEnter', 'geofenceExit') AND isEnviadoWhatsapp = 0 AND serverTime < @corte;
--
-- Nota: marcar isEnviado=1 en el histórico también evita que se creen filas de
-- visitas_geocerca para esas salidas antiguas.
