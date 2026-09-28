FROM docker.io/library/php:8.3-apache-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libfreetype6-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libldap2-dev \
        libonig-dev \
        libpng-dev \
        libzip-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" gd intl ldap mbstring pdo_mysql zip \
    && a2enmod rewrite headers \
    && rm -rf /var/lib/apt/lists/*

COPY . /var/www/html/

RUN mkdir -p /var/lib/limesurvey/config \
    && ln -s /var/lib/limesurvey/config/config.php /var/www/html/application/config/config.php \
    && chown -R www-data:www-data \
        /var/lib/limesurvey/config \
        /var/www/html/application/config \
        /var/www/html/tmp \
        /var/www/html/upload \
    && printf '%s\n' \
        'memory_limit=256M' \
        'upload_max_filesize=64M' \
        'post_max_size=64M' \
        > /usr/local/etc/php/conf.d/limesurvey.ini \
    && printf '%s\n' \
        '<Directory /var/www/html>' \
        '    AllowOverride All' \
        '</Directory>' \
        > /etc/apache2/conf-available/limesurvey.conf \
    && a2enconf limesurvey

EXPOSE 80
