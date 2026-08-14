# PocketKeeper — инфраструктура деплоя

Оркестрирует два независимых репозитория (`backend` — PocketKeeper API, `frontend` — Vue SPA)
и Nginx как единственную точку входа. Сами репозитории не меняются и не сливаются —
этот репозиторий только собирает их образы и связывает сетью.

## Раскладка на сервере

Три репозитория должны лежать рядом, на одном уровне:

```
/opt/pocketkeeper/
├── backend/    <- git clone https://github.com/GenyaElamkov/PocketKeeper.git
├── frontend/   <- git clone https://github.com/GenyaElamkov/finance-frontend.git
└── infra/      <- git clone https://github.com/GenyaElamkov/finance-infra.git
```

## Архитектура

```
Интернет ──▶ nginx (80/443, единственный порт наружу)
                ├── /            ──▶ frontend:80  (статика, Vue SPA)
                └── /api/        ──▶ backend:8000  (FastAPI)

backend ──▶ db (postgres)   — доступен только backend/migrate, наружу и frontend/nginx закрыт
```

Frontend собирается с `VITE_API_URL=/api/v1` (относительный путь) — фронт и бэк
отдаются с одного домена, поэтому браузер видит один origin и CORS не мешает.

## Первый деплой

```bash
cd /opt/pocketkeeper
git clone <backend-repo-url> backend
git clone <frontend-repo-url> frontend
git clone <infra-repo-url> infra
cd infra

cp .env.example .env
nano .env   # заполнить DB_PASSWORD, SECRET_KEY (openssl rand -hex 32), SMTP_*, DOMAIN и т.д.

# В nginx/conf.d/pocketkeeper.conf заменить "your-domain.com" на реальный домен
sed -i 's/your-domain.com/ваш-домен.ру/' nginx/conf.d/pocketkeeper.conf

make build
make up
make ps       # все контейнеры должны быть healthy/running
make logs     # проверить, что миграции прошли и backend поднялся
```

На этом этапе сайт уже доступен по HTTP (`http://ваш-домен.ру`).

## Включение HTTPS (Let's Encrypt)

1. Убедиться, что DNS A-запись домена уже указывает на сервер, и стек поднят (`make up`).
2. Выпустить сертификат:
   ```bash
   make certbot-init
   ```
3. В `nginx/conf.d/pocketkeeper.conf`:
   - раскомментировать `return 301 https://$host$request_uri;` в блоке `listen 80`
     (или просто закомментировать `location /api/` и `location /` там же — тогда 80-й
     порт будет только отдавать ACME-challenge и делать редирект);
   - раскомментировать весь блок `server { listen 443 ssl http2; ... }` внизу файла;
   - заменить `your-domain.com` на реальный домен в обоих местах, если ещё не заменили.
4. Перечитать конфиг без даунтайма:
   ```bash
   docker compose exec nginx nginx -s reload
   ```
5. Продление — добавить `make certbot-renew` в cron (например, раз в неделю).

## Обновление (редеплой)

Т.к. backend и frontend — разные репозитории, обновляются независимо:

```bash
# Бэкенд
cd /opt/pocketkeeper/backend && git pull
cd /opt/pocketkeeper/infra && make redeploy-backend

# Фронтенд
cd /opt/pocketkeeper/frontend && git pull
cd /opt/pocketkeeper/infra && make redeploy-frontend
```

Каждая команда пересобирает только один образ и перезапускает только соответствующий
контейнер (`--no-deps`), второй сервис не трогается и не даунтаймится.

## Бэкапы

БД лежит в именованном volume `db_data`. Регулярный бэкап (пример для cron):

```bash
docker compose exec -T db pg_dump -U <DB_USER> <POSTGRES_DB> | gzip > backup_$(date +%F).sql.gz
```

## Полезные команды

| Команда              | Что делает                                   |
|----------------------|-----------------------------------------------|
| `make up` / `make down` | Поднять / остановить весь стек            |
| `make logs`           | Логи всех сервисов                           |
| `make ps`              | Статус контейнеров                          |
| `make migrate`         | Прогнать миграции вручную                   |
| `make redeploy-backend` / `make redeploy-frontend` | Обновить один сервис |
