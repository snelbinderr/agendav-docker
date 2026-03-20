# STEP1: CLONE THE CODE
FROM alpine/git as cloner
WORKDIR /home/
ARG GIT_REPO=https://github.com/snelbinderr/agendav-docker
ARG GIT_BRANCH=master
RUN git clone --depth 1 --single-branch --branch ${GIT_BRANCH} ${GIT_REPO}

# Step 1: Download the code
FROM debian:bullseye-slim as downloader
WORKDIR /home/
COPY --from=cloner /home/agendav-docker .
ARG AGENDAV_VERSION=2.6.0
ADD https://github.com/agendav/agendav/releases/download/$AGENDAV_VERSION/agendav-$AGENDAV_VERSION.tar.gz .
RUN mkdir agendav/dist/data/src -p && \
    tar -xf agendav-$AGENDAV_VERSION.tar.gz && \
    cp -r agendav-$AGENDAV_VERSION/* agendav/dist/data/src/ && \
    rm -rf agendav-$AGENDAV_VERSION && \
    rm agendav-$AGENDAV_VERSION.tar.gz && \
    mkdir agendav/dist/data/config/apache2 -p && \
    mkdir agendav/dist/data/config/php -p && \
    mkdir agendav/dist/data/db -p && \
    mkdir agendav/dist/data/log -p && \
    cp run.sh ./agendav/dist/run.sh && \
    cp agendav.conf ./agendav/dist/data/config/apache2/agendav.conf && \
    cp settings.php ./agendav/dist/data/src/web/config/settings.php

# Step 2: Prepare the image
FROM php:8.2-apache-bullseye 
WORKDIR /app/
COPY --from=downloader /home/agendav/dist/ .

ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions && \
    install-php-extensions mbstring xml pdo_sqlite && \
    rm /usr/local/bin/install-php-extensions

RUN touch ./data/db/db.sqlite

RUN useradd agendav && \
    export APACHE_RUN_USER=agendav && \
    export APACHE_RUN_GROUP=agendav && \
    chown -R agendav:agendav /app && \
    find ./data/ -type d -exec chmod 770 {} \; && \
    find ./data/ -type f -exec chmod 760 {} \;

ARG PHP_INI_DIR=/usr/local/etc/php
RUN cp ${PHP_INI_DIR}/php.ini-production ${PHP_INI_DIR}/php.ini && \
    echo 'date.timezone = "AGENDAV_TIMEZONE"' >> ${PHP_INI_DIR}/php.ini && \
    echo 'magic_quotes_runtime = false' >> ${PHP_INI_DIR}/php.ini && \
    chown -R agendav:agendav ${PHP_INI_DIR}

ENV APACHE_LOG_DIR=/var/log/apache2
RUN chown -R agendav:agendav ${APACHE_LOG_DIR} && \
    chmod 755 ${APACHE_LOG_DIR} && \
    ln -sf /dev/stdout ${APACHE_LOG_DIR}/access.log \
    && ln -sf /dev/stderr ${APACHE_LOG_DIR}/error.log \
    && ln -sf /dev/stderr ${APACHE_LOG_DIR}/davi-error.log

ARG AGENDAV_PORT=8080
ENV AGENDAV_SERVER_NAME=127.0.0.1
RUN ln /app/data/config/apache2/agendav.conf /etc/apache2/sites-available/agendav.conf && \
    ln /app/data/db/ /var/agendav -s && \
    ln /app/data/src/ /var/www/agendav -s && \
    chown -R agendav:agendav /var/agendav && \
    yes | php /var/www/agendav/agendavcli migrations:migrate --configuration=/var/www/agendav/migrations.yml && \
    chmod +x run.sh && \
    a2dissite 000-default && \
    a2ensite agendav.conf && \
    a2enmod rewrite && \
    echo Listen ${AGENDAV_SERVER_NAME}:${AGENDAV_PORT} > /etc/apache2/ports.conf && \
    service apache2 restart && \
    service apache2 stop && \
    echo "Listen ${AGENDAV_PORT}" > /etc/apache2/ports.conf

EXPOSE $AGENDAV_PORT

USER agendav

ENTRYPOINT ["/app/run.sh"]

CMD ["apache2"]
