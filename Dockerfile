FROM php:8.2-apache

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    unzip \
    curl \
    default-mysql-client \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libwebp-dev \
    libzip-dev \
    libxml2-dev \
    libonig-dev \
    libicu-dev \
    && rm -rf /var/lib/apt/lists/*

# PHP extensions needed by Drupal 10, mpdf, and phpspreadsheet
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j$(nproc) \
        gd \
        opcache \
        pdo_mysql \
        mysqli \
        zip \
        xml \
        mbstring \
        bcmath \
        intl \
    && a2enmod rewrite

# Composer
RUN curl -sS https://getcomposer.org/installer \
    | php -- --install-dir=/usr/local/bin --filename=composer

COPY config/php.ini /usr/local/etc/php/conf.d/lms.ini
COPY config/apache-drupal.conf /etc/apache2/sites-enabled/000-default.conf

ENV COMPOSER_MEMORY_LIMIT=-1

# Create the Drupal 10 project. BuildKit cache mount keeps the composer
# package cache warm across rebuilds so only changed packages are re-fetched.
WORKDIR /var/www/html
RUN --mount=type=cache,target=/root/.composer/cache \
    composer create-project drupal/recommended-project:10.6.2 drupal10 \
        --no-interaction --no-install \
    && cd drupal10 && composer install --no-interaction

WORKDIR /var/www/html/drupal10

# Add all third-party dependencies in one solver pass for speed
RUN --mount=type=cache,target=/root/.composer/cache \
    composer require --no-interaction \
        'drupal/bootstrap5:^3.0' \
        'drupal/date_popup:^2.0' \
        'drupal/simple_gmap:^3.1' \
        'drupal/route_condition:^2.0' \
        'drupal/devel:^5.0' \
        'drush/drush' \
        'drupal/symfony_mailer:^1.4' \
        'mpdf/mpdf:^8.2' \
        'phpoffice/phpspreadsheet:^2.0' \
        'drupal/genpass:^2.1' \
        'drupal/legal:^3.0' \
        'drupal/captcha:^2.0' \
        'drupal/riddler:^3.0' \
        'drupal/book:^1.0' \
        'drupal/restui:^1.21' \
        'drupal/single_content_sync:^1.4'

# composer require re-runs scaffold and overwrites .htaccess, so set RewriteBase here
RUN sed -i 's|^\([[:space:]]*\)# RewriteBase /$|\1RewriteBase /lmsdev|' web/.htaccess

# Scaffold directories (custom module/theme dirs + config sync dir)
RUN mkdir -p web/modules/contrib \
             web/modules/custom \
             web/themes/contrib \
             web/themes/custom \
             web/sites/default/files \
             config/sync \
    && chown -R www-data:www-data web/sites/default

COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY scripts/install-lms.sh       /scripts/install-lms.sh
COPY scripts/export-seed.sh       /scripts/export-seed.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
             /scripts/install-lms.sh \
             /scripts/export-seed.sh

EXPOSE 80
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
