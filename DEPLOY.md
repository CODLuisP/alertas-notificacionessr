# Despliegue en el servidor B — `notificaciones-trackbell-sr`

Copia independiente de `notificaciones-trackbell` (servidor A) para el **servidor B**
(165.227.9.191, `Servidor-107`, dominios `sr.velsat.pe` y `sub.velsat.pe`).
Misma lógica y mismas tablas; lee las alertas de geocerca de la base **GTS de B**.

| | Original (A) | Esta copia (B) |
| :--- | :--- | :--- |
| Proyecto compose | `notificaciones-trackvel` (nombre de carpeta) | `notificaciones-trackbell-sr` |
| Imagen | `notificaciones-trackvel-geocerca-notifications` | `notificaciones-trackbell-sr:latest` |
| Contenedor | `notificaciones-trackbell` | `notificaciones-trackbell-sr` |
| Puerto host → contenedor | `127.0.0.1:3008 → 8080` | `127.0.0.1:3010 → 8080` |
| Base de datos | MySQL vía `host.docker.internal` | `mysql-gts:3306` por la red Docker `app-net` |
| WhatsApp | whatsapp-api de A | la misma whatsapp-api de A (`https://do.velsat.pe:8443/whatsapp/api/send/single`) |
| URL pública | `https://do.velsat.pe:8443/notificaciones-trackbell/` | `https://sr.velsat.pe:8443/notificaciones-trackbell/` |

URLs públicas en B (una vez hecho el paso 7):

| | URL |
| :--- | :--- |
| Base | `https://sr.velsat.pe:8443/notificaciones-trackbell/` |
| Swagger UI | `https://sr.velsat.pe:8443/notificaciones-trackbell/swagger/index.html` |
| Salud | `https://sr.velsat.pe:8443/notificaciones-trackbell/health` |
| Hub SignalR | `https://sr.velsat.pe:8443/notificaciones-trackbell/notificationsHub` |

---

## 0. Requisitos previos en B

```bash
# La red externa debe existir y tener a mysql-gts
docker network inspect app-net --format '{{range .Containers}}{{.Name}} {{end}}'

# El puerto 3010 debe estar libre
ss -ltnp | grep ':3010 ' || echo "3010 libre"
```

**Base de datos** (antes del primer arranque, ver `sql/`):

1. `sql/B_01_verificar_esquema.sql` — solo lectura. Toda fila con `FALTA` debe resolverse.
2. `sql/B_02_revisar_pendientes.sql` — solo lectura (la parte DML es opcional y está comentada).
   **Importante:** al arrancar, el servicio procesa *todos* los eventos de geocerca con
   `isEnviado = 0` / `isEnviadoWhatsapp = 0`, sin importar la fecha. Si hay histórico
   sin marcar en B, se enviarían WhatsApp reales por eventos viejos.
3. `sql/B_03_ddl_solo_si_falta.sql` — DDL comentado; ejecutar solo el bloque que haga falta.

```bash
docker exec -i mysql-gts mysql -ugtsuser -p gts < sql/B_01_verificar_esquema.sql
docker exec -i mysql-gts mysql -ugtsuser -p gts < sql/B_02_revisar_pendientes.sql
```

> No uses `sql/2026-10-12_salida_por_desvinculacion.sql` en B: es histórico de A y su
> `UPDATE ... WHERE id = 3` apunta a un registro de A.

---

## 1. Llevar el código a B

**Opción A — clonar** (si la copia tiene repositorio propio):

```bash
cd /opt
git clone <URL_DEL_REPO_notificaciones-trackbell-sr> notificaciones-trackbell-sr
cd /opt/notificaciones-trackbell-sr
```

**Opción B — copiar la carpeta** desde tu máquina (sin `.env`, `bin`, `obj`, `.git`):

```bash
# En tu máquina, desde el directorio padre de la carpeta
tar --exclude=.git --exclude=.env --exclude='*/bin' --exclude='*/obj' \
    -czf notificaciones-trackbell-sr.tgz notificaciones-trackbell-sr
scp notificaciones-trackbell-sr.tgz root@165.227.9.191:/opt/

# En B
cd /opt && tar -xzf notificaciones-trackbell-sr.tgz && rm notificaciones-trackbell-sr.tgz
cd /opt/notificaciones-trackbell-sr
```

---

## 2. Crear el `.env`

```bash
cp .env.example .env
chmod 600 .env
nano .env
```

Reemplaza cada `<...>`:

| Variable | Qué poner |
| :--- | :--- |
| `ConnectionStrings__GtsDatabase` | Solo cambia `<GTSUSER_PASSWORD>` por la contraseña de `gtsuser`. El resto ya apunta a `mysql-gts`. |
| `StaticApiToken` | Token propio para B, largo y aleatorio (`openssl rand -hex 32`). Es el que deben enviar los clientes en `Authorization: Bearer ...` o `X-API-KEY`. |
| `settings__secretkey` | Clave JWT (≥ 32 caracteres). Si los clientes de B envían JWT emitidos por otro backend, debe ser la misma clave con la que ese backend los firma. |
| `AllowedOrigins` | Orígenes del frontend separados por coma, p. ej. `https://sr.velsat.pe:8443,http://localhost:3000` (este último solo para desarrollo). |
| `WhatsApp__ApiKey` | API key de la whatsapp-api de A (la misma que usa A). |
| `EnableSwagger` | `false` por defecto. Ponlo en `true` para tener Swagger en `/notificaciones-trackbell/swagger/index.html`. |

Ya vienen con valor y normalmente no se tocan: `ASPNETCORE_ENVIRONMENT=Production`,
`ASPNETCORE_HTTP_PORTS=8080`, `PollingIntervalSeconds=2`,
`WhatsApp__Enabled=true`, `WhatsApp__ApiUrl`, `WhatsApp__TimeoutMs=10000`,
`WhatsApp__DelayBetweenSendsMs=400`.

> El `.env` contiene secretos: no lo subas al repo, no lo pegues en chats ni tickets.
> Tampoco compartas la salida de `docker compose config` ni de `docker inspect`:
> ambas muestran los valores del `.env`.

---

## 3. Construir y levantar

```bash
docker compose up -d --build
```

## 4. Verificar

```bash
docker compose ps                          # STATUS debe llegar a "healthy"
curl http://127.0.0.1:3010/health
# {"service":"GeocercaNotificationsService","status":"running","timestamp":"..."}

# Resolución de mysql-gts dentro de la red app-net
docker exec notificaciones-trackbell-sr getent hosts mysql-gts

# Estado de WhatsApp (no muestra la key, solo si está configurada)
curl -H "X-API-KEY: <tu StaticApiToken>" http://127.0.0.1:3010/api/whatsapp/status
```

En los logs debe aparecer `EventPollingService iniciado` y, cada 2 s,
`Ciclo de sondeo: N evento(s) pendiente(s)` **sin** errores de conexión a MySQL.

## 5. Logs

```bash
docker compose logs -f --tail=100          # en vivo
docker compose logs --since=1h | grep -iE "error|fail|warn"
```

Rotación: 3 archivos de 10 MB (configurada en `docker-compose.yml`).

## 6. Actualizar

```bash
cd /opt/notificaciones-trackbell-sr
git pull                                   # o vuelve a copiar la carpeta (paso 1, opción B) conservando el .env
docker compose up -d --build
docker image prune -f                      # limpia capas viejas
```

Otros comandos: `docker compose restart`, `docker compose down` (detiene y elimina el
contenedor; la red `app-net` no se toca porque es externa).

---

## 7. Publicación con nginx en `https://sr.velsat.pe:8443/notificaciones-trackbell/`

> Solo documentación: nada de esto está aplicado en B.

### Cómo maneja el prefijo el servicio (igual que en A)

- nginx **quita** el prefijo: `proxy_pass http://127.0.0.1:3010/;` (con la `/` final) convierte
  `/notificaciones-trackbell/health` en `/health`. La app no usa `UsePathBase`.
- Las redirecciones de `/` y `/swagger` son relativas (`swagger/index.html`), así que
  funcionan dentro del prefijo.
- Swagger UI pide `v1/swagger.json` en forma relativa, así que la página carga igual. Pero
  el botón *Execute* usa el `servers` del documento, que se arma con el header
  **`X-Forwarded-Prefix`** (o con la variable `SwaggerPathBase`). En A, el nginx envía
  `X-Forwarded-Prefix /notificaciones-trackbell`; por eso el bloque de B lo lleva también.
  - Sin ese header, *Execute* llamaría a `https://sr.velsat.pe:8443/health` (sin prefijo)
    y fallaría.
  - El código tiene un respaldo que pone `/notificaciones-trackbell` al ver
    `X-Forwarded-Proto`/`X-Forwarded-For`. En la práctica no se activa:
    `UseForwardedHeaders()` corre antes y quita esos headers de la petición. Verificado en
    local: sin `X-Forwarded-Prefix` el swagger.json sale sin `servers`, y con él sale
    `"servers":[{"url":"/notificaciones-trackbell"}]`.
  - No uses `SwaggerPathBase` en el `.env`: también se aplicaría al entrar directo por
    `127.0.0.1:3010`.
- SignalR: el cliente se conecta a `https://sr.velsat.pe:8443/notificaciones-trackbell/notificationsHub`;
  `Upgrade`/`Connection` permiten WebSockets y los timeouts de 3600 s mantienen la conexión.

### 7.1 Comprobar que el 8443 está libre en B y ubicar los certificados

```bash
sudo ss -ltnp | grep ':8443 ' || echo "8443 libre"

# Certificados que ya usa el server de sr.velsat.pe en 2053/2087/2096
sudo grep -rnE 'listen .*(2053|2087|2096)|server_name|ssl_certificate' /etc/nginx/sites-enabled/
```

### 7.2 Server nuevo para el 8443

nginx de B no escucha en el 8443, así que hace falta un `server` nuevo, por ejemplo en
`/etc/nginx/sites-available/sr-velsat-8443.conf`:

```nginx
server {
    listen 8443 ssl http2;
    listen [::]:8443 ssl http2;
    server_name sr.velsat.pe;

    # ssl_certificate y ssl_certificate_key: las mismas que usa el server de
    # sr.velsat.pe en los puertos 2053/2087/2096.
    ssl_certificate     <ruta_al_certificado>;
    ssl_certificate_key <ruta_a_la_clave>;

    location /notificaciones-trackbell/ {
        proxy_pass http://127.0.0.1:3010/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Real-IP $remote_addr;
        # Igual que en A: Swagger lo usa para que "Execute" llame con el prefijo
        proxy_set_header X-Forwarded-Prefix /notificaciones-trackbell;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/sr-velsat-8443.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

- Los demás servicios que se publiquen en el 8443 van como **otro `location`** dentro de
  este mismo `server`, no en otro `server` con el mismo `listen`/`server_name`.
- En nginx ≥ 1.25.1, `http2` dentro de `listen` da un aviso de *deprecated*; funciona igual
  (la forma nueva es `http2 on;` en una línea aparte).

### 7.3 Abrir el 8443/tcp en ufw

```bash
sudo ufw allow 8443/tcp
sudo ufw status | grep 8443
```

Si los puertos 2053/2087/2096 están limitados a las IPs de Cloudflare, aplica la misma
regla al 8443 en lugar del `allow` general.

### 7.4 DNS de sr.velsat.pe proxied por Cloudflare

En Cloudflare → DNS, el registro `sr` debe tener la **nube naranja** (Proxied). Desde
cualquier equipo:

```bash
dig +short sr.velsat.pe
```

Debe devolver IPs de Cloudflare (p. ej. `104.x.x.x` o `172.64–71.x.x`), **no** `165.227.9.191`.
El modo SSL/TLS de la zona (Full / Full strict) debe aceptar el certificado configurado en 7.2,
igual que ya pasa con 2053/2087/2096.

### 7.5 Pruebas

```bash
# En B, directo contra nginx (sin pasar por Cloudflare)
curl -sk --resolve sr.velsat.pe:8443:127.0.0.1 https://sr.velsat.pe:8443/notificaciones-trackbell/health

# Prueba final por la URL pública
curl -s https://sr.velsat.pe:8443/notificaciones-trackbell/health
# {"service":"GeocercaNotificationsService","status":"running","timestamp":"..."}

# Swagger (con EnableSwagger=true): 200 y servers apuntando al prefijo
curl -s -o /dev/null -w "%{http_code}\n" https://sr.velsat.pe:8443/notificaciones-trackbell/swagger/index.html
curl -s https://sr.velsat.pe:8443/notificaciones-trackbell/swagger/v1/swagger.json | grep -o '"servers":[^]]*]'
# "servers":[{"url":"/notificaciones-trackbell"}]

# SignalR: negociación (debe devolver JSON con connectionToken y transporte WebSockets)
curl -s -X POST "https://sr.velsat.pe:8443/notificaciones-trackbell/notificationsHub/negotiate?negotiateVersion=1"
```
