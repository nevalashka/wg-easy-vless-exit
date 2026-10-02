# README: выходной сервер VLESS + REALITY

Контейнер с Xray для второго (выходного) сервера в связке с [wg-easy-tun](../wg-easy-vless). Он заменяет `nevalashka/shadowsocks_tun`.

```
клиент ──WireGuard──▶ нода 1 (wg-easy-tun) ──VLESS+REALITY :443──▶ ЭТОТ СЕРВЕР ──▶ интернет
```

- Ключи REALITY, UUID и shortId **генерируются сами** при первом старте и сохраняются в `./xray-data`. При пересоздании контейнера они не меняются.
- Готовый блок переменных для первой ноды печатается в лог и пишется в `./xray-data/client.txt`.
- Если запрос пришёл не с ключом REALITY (активное зондирование), сервер отдаёт настоящий сертификат сайта из `REALITY_SNI`.
- Клиентам закрыт доступ в приватные сети выходного сервера, включая `169.254.169.254` (метаданные облака). BitTorrent заблокирован, чтобы хостер не получал abuse-жалобы.
- Access-лог выключен (no-logs).
- Защищён: read-only FS, `cap_drop: ALL` (оставлен только `NET_BIND_SERVICE`), `no-new-privileges`.

## Развёртывание

1. VPS за пределами РФ, Ubuntu 22.04/24.04, Docker. Порт **443/tcp** должен быть свободен.
2. Положить `docker-compose.yml`, при желании поменять `REALITY_SNI`.
3. Запустить:
   ```bash
   docker compose up -d
   docker logs vless-exit        # или: cat xray-data/client.txt
   ```
4. Скопировать напечатанный блок `VLESS_*` (или строку `VLESS_URI`) в `docker-compose.yml` первой ноды и выполнить там `docker compose up -d --force-recreate wg-easy-tun`.
5. На первой ноде: `docker exec wg-easy-tun healthcheck.sh -v`. В строке `exit IP` должен быть IP этого сервера.

## Переменные

| Переменная | По умолчанию | Описание |
|---|---|---|
| `VLESS_PORT` | `443` | порт VLESS (tcp + vision) |
| `REALITY_SNI` | `www.microsoft.com` | сайт, под который маскируемся |
| `REALITY_TARGET` | `SNI:443` | куда проксировать «чужие» подключения |
| `XHTTP_PORT` | пусто | включить запасной транспорт xhttp на этом порту (не забыть открыть его в `ports`) |
| `XHTTP_PATH` | случайный | путь xhttp |
| `VLESS_UUID` | авто | UUID клиента |
| `REALITY_PRIVATE_KEY` | авто | приватный ключ REALITY (публичный вычисляется сам) |
| `REALITY_SHORT_ID` | авто | shortId, hex до 16 символов |
| `BLOCK_TORRENT` | `true` | блокировать BitTorrent |
| `PUBLIC_HOST` | автоопределение | IP/домен для печати параметров |
| `XRAY_LOGLEVEL` | `warning` | уровень лога |
| `XRAY_ACCESS_LOG` | `false` | логировать соединения (для отладки) |

## Выбор SNI

- Сайт должен поддерживать TLS 1.3 и HTTP/2. Проверка: `curl -sI --http2 --tlsv1.3 https://SITE | head -1`.
- Не за Cloudflare и не из блок-листов РКН.
- Лучше всего — сайт в той же стране или у того же хостера (ASN), что и VPS. Тогда трафик к IP сервера под этим SNI выглядит естественно.
- Если SNI сменить, его нужно сменить и на ноде (`VLESS_SNI`).

## Ротация ключей

```bash
docker compose down && rm xray-data/server.env && docker compose up -d && docker logs vless-exit
```
После этого обновить `VLESS_*` на первой ноде.

## Рекомендации для хоста

Включить BBR, это заметно лучше на длинном канале РФ → EU:
```bash
echo -e "net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr" > /etc/sysctl.d/99-bbr.conf && sysctl --system
```

## Сборка

```bash
DOCKER_BUILDKIT=1 docker build --no-cache -t nevalashka/vless-reality-exit:1.0 .
docker build --build-arg XRAY_VERSION=v26.9.30 -t ... .   # другая версия Xray
```
