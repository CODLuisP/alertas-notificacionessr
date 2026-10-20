-- =============================================================================
-- Servidor B (mysql-gts, base gts) - VERIFICACIÓN DE ESQUEMA. SOLO LECTURA.
-- Lista lo que el microservicio usa y marca lo que falte. No modifica nada.
-- Ejecutar como gtsuser:  docker exec -i mysql-gts mysql -ugtsuser -p gts < B_01_verificar_esquema.sql
-- =============================================================================

-- 1) Columnas que el código lee o escribe. Toda fila con estado = 'FALTA' es un problema.
--    (areaWkt puede llamarse area_wkt; si no existe ninguna de las dos, el servicio
--     funciona, pero no detecta "salida por desvinculación").
SELECT e.tabla, e.columna,
       IF(c.COLUMN_NAME IS NULL, 'FALTA', 'ok') AS estado,
       c.COLUMN_TYPE, c.IS_NULLABLE, c.COLUMN_DEFAULT
FROM (
              SELECT 'deviceevent' tabla, 'id' columna
    UNION ALL SELECT 'deviceevent', 'accountID'
    UNION ALL SELECT 'deviceevent', 'deviceID'
    UNION ALL SELECT 'deviceevent', 'eventType'
    UNION ALL SELECT 'deviceevent', 'serverTime'
    UNION ALL SELECT 'deviceevent', 'latitude'
    UNION ALL SELECT 'deviceevent', 'longitude'
    UNION ALL SELECT 'deviceevent', 'speed'
    UNION ALL SELECT 'deviceevent', 'geofenceID'
    UNION ALL SELECT 'deviceevent', 'geofenceName'
    UNION ALL SELECT 'deviceevent', 'isEnviado'
    UNION ALL SELECT 'deviceevent', 'isEnviadoWhatsapp'
    UNION ALL SELECT 'deviceevent', 'fechaEnvioWhatsapp'
    UNION ALL SELECT 'deviceevent', 'intentosWhatsapp'
    UNION ALL SELECT 'visitas_geocerca', 'id'
    UNION ALL SELECT 'visitas_geocerca', 'accountID'
    UNION ALL SELECT 'visitas_geocerca', 'deviceID'
    UNION ALL SELECT 'visitas_geocerca', 'geofenceID'
    UNION ALL SELECT 'visitas_geocerca', 'geofenceName'
    UNION ALL SELECT 'visitas_geocerca', 'fecha_entrada'
    UNION ALL SELECT 'visitas_geocerca', 'fecha_salida'
    UNION ALL SELECT 'visitas_geocerca', 'duracion_minutos'
    UNION ALL SELECT 'visitas_geocerca', 'latitud_entrada'
    UNION ALL SELECT 'visitas_geocerca', 'longitud_entrada'
    UNION ALL SELECT 'visitas_geocerca', 'latitud_salida'
    UNION ALL SELECT 'visitas_geocerca', 'longitud_salida'
    UNION ALL SELECT 'visitas_geocerca', 'evento_entrada_id'
    UNION ALL SELECT 'visitas_geocerca', 'evento_salida_id'
    UNION ALL SELECT 'visitas_geocerca', 'entrada_incompleta'
    UNION ALL SELECT 'visitas_geocerca', 'salida_por_desvinculacion'
    UNION ALL SELECT 'visitas_geocerca', 'fecha_registro'
    UNION ALL SELECT 'geocercas', 'id'
    UNION ALL SELECT 'geocercas', 'accountID'
    UNION ALL SELECT 'geocercas', 'geofenceID'
    UNION ALL SELECT 'geocercas', 'nombre'
    UNION ALL SELECT 'geocercas', 'activo'
    UNION ALL SELECT 'geocercas', 'whatsapp_activo'
    UNION ALL SELECT 'geocercas', 'whatsapp_modo'
    UNION ALL SELECT 'geocercas', 'whatsapp_eventos'
    UNION ALL SELECT 'geocercas', 'areaWkt'
    UNION ALL SELECT 'geocercas_vehiculos', 'id_geocerca'
    UNION ALL SELECT 'geocercas_vehiculos', 'deviceID'
    UNION ALL SELECT 'geocercas_vehiculos', 'activo'
    UNION ALL SELECT 'geocercas_vehiculos', 'notificarWhatsapp'
    UNION ALL SELECT 'geocercas_whatsapp_destinos', 'id'
    UNION ALL SELECT 'geocercas_whatsapp_destinos', 'id_geocerca'
    UNION ALL SELECT 'geocercas_whatsapp_destinos', 'nombre'
    UNION ALL SELECT 'geocercas_whatsapp_destinos', 'phone'
    UNION ALL SELECT 'geocercas_whatsapp_destinos', 'activo'
    UNION ALL SELECT 'geocercas_whatsapp_destinos', 'eventos'
    UNION ALL SELECT 'geocercas_whatsapp_destinos_vehiculos', 'id_destino'
    UNION ALL SELECT 'geocercas_whatsapp_destinos_vehiculos', 'deviceID'
    UNION ALL SELECT 'evento_whatsapp_envios', 'id_evento'
    UNION ALL SELECT 'evento_whatsapp_envios', 'phone'
    UNION ALL SELECT 'evento_whatsapp_envios', 'enviado_en'
) e
LEFT JOIN information_schema.COLUMNS c
       ON c.TABLE_SCHEMA = 'gts'
      AND c.TABLE_NAME = e.tabla
      AND (c.COLUMN_NAME = e.columna
           OR (e.columna = 'areaWkt' AND c.COLUMN_NAME = 'area_wkt'))
ORDER BY (c.COLUMN_NAME IS NULL) DESC, e.tabla, e.columna;

-- 2) Claves únicas de las que depende el código (ON DUPLICATE KEY / INSERT IGNORE).
--    Esperado:
--      evento_whatsapp_envios                (id_evento, phone)
--      geocercas_whatsapp_destinos           (id_geocerca, phone)   <- sin ella, un número repetido recibe el WhatsApp dos veces
--      geocercas_whatsapp_destinos_vehiculos (id_destino, deviceID)
SELECT TABLE_NAME, INDEX_NAME, NON_UNIQUE,
       GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS columnas
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = 'gts'
  AND TABLE_NAME IN ('evento_whatsapp_envios',
                     'geocercas_whatsapp_destinos',
                     'geocercas_whatsapp_destinos_vehiculos',
                     'deviceevent',
                     'visitas_geocerca',
                     'geocercas',
                     'geocercas_vehiculos')
GROUP BY TABLE_NAME, INDEX_NAME, NON_UNIQUE
ORDER BY TABLE_NAME, NON_UNIQUE, INDEX_NAME;

-- 3) Zona horaria y sql_mode: compáralos con los de A (fechaEnvioWhatsapp y
--    enviado_en usan NOW(), que depende de la zona del servidor MySQL).
SELECT @@global.time_zone, @@session.time_zone, @@system_time_zone, @@global.sql_mode;
