#FROM jdk8:latest
FROM openjdk:8u151-jdk-alpine3.7
#FROM jdk8-alipne3.6:latest
RUN apk add --no-cache tzdata
ENV TZ Asia/Jakarta

RUN apk add --no-cache git python rsync jq wget openssl coreutils ansible openssh-client curl unzip bash ttf-dejavu \ 
	coreutils tini php7 php7-gd php7-curl \
	php7-iconv php7-phar php7-json php7-openssl php7-mbstring php7-xsl php7-pdo php7-mysqli \
	php7-ctype php7-xml php7-xmlreader php7-common \
	php7-dom php7-xmlreader php7-zip php7-zlib php7-session php7-pdo_mysql \ 
	php7-mcrypt php7-gettext php7-exif php7-sockets \
	php7-ctype php7-bcmath php7-tokenizer php7-fileinfo php7-xmlwriter php7-simplexml \
	php7-intl php7-bcmath php7-redis php7-soap php7-xdebug php7-imagick 

ENV NODE_VERSION 11.10.0

RUN apk add --no-cache \
        libstdc++ \
    && apk add --no-cache --virtual .build-deps \
        binutils-gold \
        g++ \
        gcc \
        gnupg \
        libgcc \
        linux-headers \
        make \
  # gpg keys listed at https://github.com/nodejs/node#release-keys
  && for key in \
    94AE36675C464D64BAFA68DD7434390BDBE9B9C5 \
    FD3A5288F042B6850C66B31F09FE44734EB7990E \
    71DCFD284A79C3B38668286BC97EC7A07EDE3FC1 \
    DD8F2338BAE7501E3DD5AC78C273792F7D83545D \
    C4F0DFFF4E8C1A8236409D08E73BC641CC11F4C8 \
    B9AE9905FFD7803F25714661B63B535A4C206CA9 \
    77984A986EBC2AA786BC0F66B01FBB92821C587A \
    8FCCA13FEF1D0C2E91008E09770F7A9A5AE15600 \
    4ED778F539E3634C779C87C6D7062848A1AB005C \
    A48C2BEE680E841632CD4E44F07496B3EB3C1762 \
    B9E2F5981AA6E0CD28160D9FF13993A75599653C \
  ; do \
    gpg --batch --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys "$key" || \
    gpg --batch --keyserver hkp://ipv4.pool.sks-keyservers.net --recv-keys "$key" || \
    gpg --batch --keyserver hkp://pgp.mit.edu:80 --recv-keys "$key" ; \
  done \
    && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION.tar.xz" \
    && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt.asc" \
    && gpg --batch --decrypt --output SHASUMS256.txt SHASUMS256.txt.asc \
    && grep " node-v$NODE_VERSION.tar.xz\$" SHASUMS256.txt | sha256sum -c - \
    && tar -xf "node-v$NODE_VERSION.tar.xz" \
    && cd "node-v$NODE_VERSION" \
    && ./configure \
    && make -j$(getconf _NPROCESSORS_ONLN) \
    && make install \
    && apk del .build-deps \
    && cd .. \
    && rm -Rf "node-v$NODE_VERSION" \
    && rm "node-v$NODE_VERSION.tar.xz" SHASUMS256.txt.asc SHASUMS256.txt

# Golang 

ENV GOLANG_VERSION 1.12.3

RUN set -eux; \
	apk add --no-cache --virtual .build-deps \
	musl-dev \
	go \
	; \
	export \
	GOROOT_BOOTSTRAP="$(go env GOROOT)" \
	GOOS="$(go env GOOS)" \
	GOARCH="$(go env GOARCH)" \
	GOHOSTOS="$(go env GOHOSTOS)" \
	GOHOSTARCH="$(go env GOHOSTARCH)" \
	; \
	apkArch="$(apk --print-arch)"; \
	case "$apkArch" in \
	armhf) export GOARM='6' ;; \
	x86) export GO386='387' ;; \
	esac; \
	\
	wget -O go.tgz "https://golang.org/dl/go$GOLANG_VERSION.src.tar.gz"; \
	echo '5c507abe8818429d74ebb650a4155d36bc3f9a725e59e76f5d6aca9690be2373 *go.tgz' | sha256sum -c -; \
	tar -C /usr/local -xzf go.tgz; \
	rm go.tgz; \
	\
	cd /usr/local/go/src; \
	./make.bash; \
	\
	rm -rf \
	/usr/local/go/pkg/bootstrap \
	/usr/local/go/pkg/obj \
	; \
	apk del .build-deps; \
	\
	export PATH="/usr/local/go/bin:$PATH"; \
	go version

#RUN ln -sd /usr/bin/php7 /usr/bin/php
RUN mkdir -p /var/ansible && touch /var/ansible/keys_root
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer && chmod +x /usr/local/bin/composer
RUN addgroup -S devteam && adduser -S -G devteam devteam

ARG user=jenkins
ARG group=jenkins
ARG uid=1000
ARG gid=1000
ARG http_port=8080
ARG agent_port=50000
ARG JENKINS_HOME=/var/jenkins_home

ENV JENKINS_HOME $JENKINS_HOME
ENV JENKINS_SLAVE_AGENT_PORT ${agent_port}

# Jenkins is run with user `jenkins`, uid = 1000
# If you bind mount a volume from the host or a data container,
# ensure you use the same uid
RUN mkdir -p $JENKINS_HOME \
  && chown ${uid}:${gid} $JENKINS_HOME \
  && addgroup -g ${gid} ${group} \
  && adduser -h "$JENKINS_HOME" -u ${uid} -G ${group} -s /bin/bash -D ${user}

# Jenkins home directory is a volume, so configuration and build history
# can be persisted and survive image upgrades
VOLUME $JENKINS_HOME

# `/usr/share/jenkins/ref/` contains all reference configuration we want
# to set on a fresh new installation. Use it to bundle additional plugins
# or config file with your custom jenkins Docker image.
RUN mkdir -p /usr/share/jenkins/ref/init.groovy.d

COPY init.groovy /usr/share/jenkins/ref/init.groovy.d/tcp-slave-agent-port.groovy

# jenkins version being bundled in this docker image
ARG JENKINS_VERSION
ENV JENKINS_VERSION ${JENKINS_VERSION:-2.164.1}

# jenkins.war checksum, download will be validated using it
# ARG JENKINS_SHA=fab70f4e209855e0806315cc419e0cbbbf1bd9b31c6f221f7702aa21145040f8 #v2.150.3
#ARG JENKINS_SHA=4fc2700a27a6ccc53da9d45cc8b2abd41951b361e562e1a1ead851bea61630fd
ARG JENKINS_SHA=65543f5632ee54344f3351b34b305702df12393b3196a95c3771ddb3819b220b

# Can be used to customize where jenkins.war get downloaded from
ARG JENKINS_URL=https://repo.jenkins-ci.org/public/org/jenkins-ci/main/jenkins-war/${JENKINS_VERSION}/jenkins-war-${JENKINS_VERSION}.war

# could use ADD but this one does not check Last-Modified header neither does it allow to control checksum
# see https://github.com/docker/docker/issues/8331
RUN curl -fsSL ${JENKINS_URL} -o /usr/share/jenkins/jenkins.war \
  && echo "${JENKINS_SHA}  /usr/share/jenkins/jenkins.war" | sha256sum -c -

ENV JENKINS_UC https://updates.jenkins.io
ENV JENKINS_UC_EXPERIMENTAL=https://updates.jenkins.io/experimental
ENV JENKINS_INCREMENTALS_REPO_MIRROR=https://repo.jenkins-ci.org/incrementals
RUN chown -R ${user} "$JENKINS_HOME" /usr/share/jenkins/ref

# for main web interface:
EXPOSE ${http_port}

# will be used by attached slave agents:
EXPOSE ${agent_port}

ENV COPY_REFERENCE_FILE_LOG $JENKINS_HOME/copy_reference_file.log

USER ${user}

COPY jenkins-support /usr/local/bin/jenkins-support
COPY jenkins.sh /usr/local/bin/jenkins.sh
COPY tini-shim.sh /bin/tini
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/jenkins.sh"]

# from a derived Dockerfile, can use `RUN plugins.sh active.txt` to setup /usr/share/jenkins/ref/plugins from a support bundle
COPY plugins.sh /usr/local/bin/plugins.sh
COPY install-plugins.sh /usr/local/bin/install-plugins.sh
