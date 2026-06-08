FROM php:8.2-cli

RUN apt-get update \
    && apt-get install -y --no-install-recommends libsqlite3-dev libonig-dev unzip ca-certificates \
    && docker-php-ext-install pdo_sqlite mbstring \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/app
COPY php.ini /usr/local/etc/php/conf.d/99-upeu-silabo-ai.ini
COPY . /var/www/app

RUN mkdir -p storage/db storage/sessions storage/uploads storage/reports storage/cache storage/jobs storage/rag storage/tmp /data/syllabi \
    && chown -R www-data:www-data /var/www/app/storage /data \
    && chmod +x /var/www/app/docker-entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/var/www/app/docker-entrypoint.sh"]
CMD ["php", "-S", "0.0.0.0:8080", "-t", "public", "public/index.php"]
