FROM php:8.5.13-apache-bookworm

ENV COMPOSER_ALLOW_SUPERUSER=1

# hadolint ignore=DL3008
RUN set -eux; \
    a2enmod rewrite remoteip; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        unzip \
        tzdata \
        cron \
        curl \
        ca-certificates \
        zlib1g-dev \
        libzip-dev \
        libpng-dev; \
    rm -rf /var/lib/apt/lists/*; \
    docker-php-ext-install pdo_mysql fileinfo gd zip; \
    mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"; \
    pecl install apcu; \
    docker-php-ext-enable apcu; \
    install -d -o www-data -g www-data -m 2775 \
        /var/www/cache \
        /var/www/logs \
        /var/www/config \
        /var/www/var \
        /var/www/var/cache \
        /var/www/var/cache/doctrine \
        /var/www/var/doctrine \
        /var/www/var/doctrine/proxies; \
    touch /var/log/cron.log; \
    chown www-data:www-data /var/log/cron.log; \
    chmod 0664 /var/log/cron.log; \
    curl -fsSLo /tmp/composer-setup.php https://getcomposer.org/installer; \
    curl -fsSLo /tmp/composer-installer.sig https://composer.github.io/installer.sig; \
    php -r "if (hash_file('sha384', '/tmp/composer-setup.php') !== trim(file_get_contents('/tmp/composer-installer.sig'))) { fwrite(STDERR, 'Invalid Composer installer signature' . PHP_EOL); exit(1); }"; \
    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer; \
    rm -f /tmp/composer-setup.php /tmp/composer-installer.sig

COPY php/99-security.ini /usr/local/etc/php/conf.d/99-security.ini
COPY apache/remoteip.conf /etc/apache2/conf-enabled/remoteip.conf
COPY apache/servername.conf /etc/apache2/conf-enabled/servername.conf
COPY apache/security.conf /etc/apache2/conf-enabled/security.conf
COPY html/ /var/www/html

COPY bin/dev-composer-install /usr/local/bin/dev-composer-install
COPY bin/dev-start-services /usr/local/bin/dev-start-services
COPY bin/dev-clear /usr/local/bin/dev-clear
COPY bin/start-services /usr/local/bin/start-services
COPY bin/setup-runtime-dirs /usr/local/bin/setup-runtime-dirs
COPY bin/winglet-doctrine /usr/local/bin/winglet-doctrine
COPY bin/winglet /usr/local/bin/winglet

RUN chmod +x \
    /usr/local/bin/dev-composer-install \
    /usr/local/bin/dev-start-services \
    /usr/local/bin/start-services \
    /usr/local/bin/setup-runtime-dirs \
    /usr/local/bin/winglet \
    /usr/local/bin/winglet-doctrine

WORKDIR /var/www
CMD ["start-services"]
