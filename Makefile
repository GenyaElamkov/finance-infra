COMPOSE := docker compose

.PHONY: help build up down restart logs ps migrate certbot-init certbot-renew redeploy-backend redeploy-frontend

help: ## Список команд
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'

build: ## Собрать все образы (backend, frontend)
	$(COMPOSE) build

up: ## Поднять весь стек в фоне
	$(COMPOSE) up -d

down: ## Остановить и удалить контейнеры
	$(COMPOSE) down

restart: down up ## Перезапустить весь стек

logs: ## Логи всех сервисов
	$(COMPOSE) logs -f

ps: ## Список контейнеров проекта
	$(COMPOSE) ps

migrate: ## Прогнать миграции вручную (обычно не требуется — делает сервис migrate при старте)
	$(COMPOSE) run --rm migrate

redeploy-backend: ## git pull + пересборка + рестарт только backend (после deploy в ../backend)
	$(COMPOSE) build backend migrate
	$(COMPOSE) up -d --no-deps backend

redeploy-frontend: ## git pull + пересборка + рестарт только frontend (после deploy в ../frontend)
	$(COMPOSE) build frontend
	$(COMPOSE) up -d --no-deps frontend

certbot-init: ## Первичный выпуск сертификата Let's Encrypt (после domain: правки в nginx.conf и запущенного up)
	docker run --rm \
		-v $$(pwd)/nginx/certbot/conf:/etc/letsencrypt \
		-v $$(pwd)/nginx/certbot/www:/var/www/certbot \
		certbot/certbot certonly --webroot -w /var/www/certbot \
		-d $$(grep DOMAIN .env | cut -d '=' -f2)

certbot-renew: ## Продление сертификата (повесить на cron раз в сутки/неделю)
	docker run --rm \
		-v $$(pwd)/nginx/certbot/conf:/etc/letsencrypt \
		-v $$(pwd)/nginx/certbot/www:/var/www/certbot \
		certbot/certbot renew --webroot -w /var/www/certbot
	$(COMPOSE) exec nginx nginx -s reload
