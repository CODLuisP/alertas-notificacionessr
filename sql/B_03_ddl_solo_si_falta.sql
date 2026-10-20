-- =============================================================================
-- Servidor B - DDL SOLO SI B_01_verificar_esquema.sql MUESTRA QUE FALTA ALGO.
-- Todo está comentado a propósito. Descomenta y ejecuta únicamente el bloque que aplique.
--
-- Los tipos de columna son INFERIDOS del código. Si A ya tiene el objeto, lo más
-- seguro es copiar su definición exacta desde A:
--     SHOW CREATE TABLE <tabla>;
-- Si falta una TABLA completa, no uses este archivo: crea la tabla con el
-- SHOW CREATE TABLE de A.
-- =============================================================================


-- ── A. visitas_geocerca.salida_por_desvinculacion ───────────────────────────
-- Imprescindible: el INSERT de visitas la usa y falla sin ella (no habría visitas).
--
-- ALTER TABLE visitas_geocerca
--     ADD COLUMN salida_por_desvinculacion TINYINT(1) NOT NULL DEFAULT 0 AFTER entrada_incompleta;


-- ── B. Columnas de control en deviceevent ───────────────────────────────────
-- Imprescindibles. ¡OJO! Con DEFAULT 0 todo el histórico queda "pendiente" y el
-- servicio enviaría WhatsApp/alertas por eventos viejos: por eso cada ADD va seguido
-- de un UPDATE que marca lo existente como procesado.
--
-- ALTER TABLE deviceevent ADD COLUMN isEnviado TINYINT(1) NOT NULL DEFAULT 0;
-- UPDATE deviceevent SET isEnviado = 1;
--
-- ALTER TABLE deviceevent
--     ADD COLUMN isEnviadoWhatsapp TINYINT NOT NULL DEFAULT 0
--         COMMENT '0=pendiente, 1=enviado/descartado, 2=falló tras 5 intentos',
--     ADD COLUMN fechaEnvioWhatsapp DATETIME NULL,
--     ADD COLUMN intentosWhatsapp INT NOT NULL DEFAULT 0;
-- UPDATE deviceevent SET isEnviadoWhatsapp = 1;


-- ── C. Claves únicas ────────────────────────────────────────────────────────
-- Sin ellas el servicio NO falla, pero:
--   * geocercas_whatsapp_destinos: un mismo número puede quedar repetido en una
--     geocerca y recibir cada aviso dos veces.  (la más importante de las tres)
--   * evento_whatsapp_envios / destinos_vehiculos: filas duplicadas.
-- Antes de crearlas, comprueba que no haya duplicados (si devuelve filas, la
-- creación fallará; limpia primero):
--
-- SELECT id_geocerca, phone, COUNT(*) FROM geocercas_whatsapp_destinos
--  GROUP BY id_geocerca, phone HAVING COUNT(*) > 1;
-- SELECT id_evento, phone, COUNT(*) FROM evento_whatsapp_envios
--  GROUP BY id_evento, phone HAVING COUNT(*) > 1;
-- SELECT id_destino, deviceID, COUNT(*) FROM geocercas_whatsapp_destinos_vehiculos
--  GROUP BY id_destino, deviceID HAVING COUNT(*) > 1;
--
-- ALTER TABLE geocercas_whatsapp_destinos           ADD UNIQUE KEY uq_destino_geocerca_phone (id_geocerca, phone);
-- ALTER TABLE evento_whatsapp_envios                ADD UNIQUE KEY uq_envio_evento_phone     (id_evento, phone);
-- ALTER TABLE geocercas_whatsapp_destinos_vehiculos ADD UNIQUE KEY uq_destino_device         (id_destino, deviceID);


-- ── D. Índices de rendimiento (opcionales) ──────────────────────────────────
-- Solo si A los tiene y B no. El servicio sondea deviceevent cada PollingIntervalSeconds
-- (2 s por defecto) dos veces; sin índice, cada sondeo recorre la tabla completa.
-- En MySQL 8 ADD INDEX es online (no bloquea escrituras), pero en tablas grandes tarda.
--
-- ALTER TABLE deviceevent
--     ADD INDEX ix_de_pend_signalr  (eventType, isEnviado, serverTime),
--     ADD INDEX ix_de_pend_whatsapp (eventType, isEnviadoWhatsapp, intentosWhatsapp, serverTime),
--     ADD INDEX ix_de_enter_match   (deviceID, geofenceID, eventType, serverTime),
--     ALGORITHM = INPLACE, LOCK = NONE;
--
-- ALTER TABLE visitas_geocerca
--     ADD INDEX ix_vg_evento_salida   (evento_salida_id),
--     ADD INDEX ix_vg_account_salida  (accountID, fecha_salida),
--     ALGORITHM = INPLACE, LOCK = NONE;
