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
ARG PHP_VERSION=8.2
ARG AGENDAV_VERSION=2.6.0
ADD https://github.com/agendav/agendav/releases/download/$AGENDAV_VERSION/agendav-$AGENDAV_VERSION.tar.gz .
RUN mkdir agendav/data/src -p && \
    tar -xf agendav-$AGENDAV_VERSION.tar.gz -C agendav/data/src && \
    rm agendav-$AGENDAV_VERSION.tar.gz && \
    mkdir agendav/app -p && \
    mkdir agendav/data/config/apache2 -p && \
    mkdir agendav/data/config/php -p && \
    mkdir agendav/data/db -p && \
    mkdir agendav/data/log -p && \
    cp run.sh ./agendav && \
    cp agendav.conf ./agendav/data/config/apache2 && \
    cp settings.php ./agendav/data/src/web/config/settings.php

# Step 2: Prepare the image
FROM php:${PHP_VERSION}-apache-bullseye as preparer
WORKDIR /app/
COPY --from=downloader /home/agendav-docker/agendav .

ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions && \
    install-php-extensions mbstring xml pdo_sqlite && \
    rm /usr/local/bin/install-php-extensions && \

ARG PHP_INI_DIR /usr/local/etc/php
RUN cp ${PHP_INI_DIR}/php.ini-production ${PHP_INI_DIR}/php.ini && \
    echo 'date.timezone = "AGENDAV_TIMEZONE"' >> ${PHP_INI_DIR}/php.ini && \
    echo 'magic_quotes_runtime = false' >> ${PHP_INI_DIR}/php.ini

RUN touch ./data/db/db.sqlite

RUN ln ./data/config/apache2/agendav.conf /etc/apache2/sites-available/agendav.conf -s && \
    ln /var/www/agendav ./data/src -s && \
    ln ./data/db/db.sqlite /var/agendav/db.sqlite -s

RUN yes | php ./data/src/agendavcli migrations:migrate && \
    chmod +x run.sh

RUN a2dissite 000-default && \
    a2ensite agendav.conf && \
    a2enmod rewrite && \
    echo "Listen 127.0.0.1:$AGENDAV_PORT" > /etc/apache2/ports.conf && \
    service apache2 restart && \
    service apache2 stop &&  \
    echo "Listen $AGENDAV_PORT" > /etc/apache2/ports.conf

ARG APACHE_LOG_DIR ./data/log
RUN ln -sf /dev/stdout ${APACHE_LOG_DIR}/access.log \
    && ln -sf /dev/stderr ${APACHE_LOG_DIR}/error.log \
    && ln -sf /dev/stderr ${APACHE_LOG_DIR}/davi-error.log

RUN useradd agendav && \
    export APACHE_RUN_USER=agendav && \
    export APACHE_RUN_GROUP=agendav && \
    chown -R agendav:agendav . && \
    find ./data/ -type d -exec chmod 770 {} \; && \
    find ./data/ -type f -exec chmod 760 {} \; && \
    chmod 730 run.sh

EXPOSE $AGENDAV_PORT

USER agendav

ENTRYPOINT ["/app/run.sh"]

CMD ["apache2"]
