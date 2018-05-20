FROM php:5.6.36-apache

ENV SERVER_VERSION=server_release/0.9 \
    ROOT_PATH=/root/boinc/

#install packages 
RUN echo 'deb http://ftp.debian.org/debian jessie-backports main' >> /etc/apt/sources.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        cron \
        curl \
        dh-autoreconf \
        g++ \
        git \
        inotify-tools \
        libcurl4-gnutls-dev \
        libjpeg62-turbo-dev \
        libmysqlclient-dev \
        libpng12-dev \
        m4 \
        make \
        mysql-client \
        pkg-config \
        python \
        python-mysqldb \
        rsyslog \
        supervisor \
        vim-tiny \
        wget \
    && apt-get install -y -t jessie-backports openssl libssl-dev \
    && rm -rf /var/lib/apt/lists


#configure server
RUN docker-php-ext-install mysqli \
    && docker-php-ext-configure gd --with-jpeg-dir=/usr/include/ \
    && docker-php-ext-install gd \
    && a2enmod cgi


RUN mkdir -p $ROOT_PATH \
    && wget -qO- https://github.com/BOINC/boinc/archive/${SERVER_VERSION}.tar.gz | tar xvz --strip-components=1 -C $ROOT_PATH \
    && cd $ROOT_PATH \
    && ./_autosetup \
    && ./configure --disable-client --disable-manager \
    && make

RUN adduser --uid 1000 --system --group boincadm --no-create-home \
    && usermod -aG boincadm www-data

ENV USER=boincadm \
    PROJECT_PATH=/project

WORKDIR $PROJECT_PATH

# set volume
VOLUME "${PROJECT_PATH}"

COPY supervisord.conf /etc/supervisor/conf.d/
COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh

# set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
CMD ["app:start"]
