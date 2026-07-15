
###################################
#Build stage
FROM golang:1.25-alpine AS build-env

#ARG GOPROXY
#ENV GOPROXY ${GOPROXY:-direct}

ARG GITEA_VERSION="release/v1.12"
ARG TAGS="sqlite sqlite_unlock_notify"
ENV TAGS "bindata $TAGS"
ENV NODE_OPTIONS "--openssl-legacy-provider"
# ponytail: musl 1.2.5+ dropped the LFS64 aliases (off64_t/pread64) that the
# pinned mattn/go-sqlite3 C still references; expose them via the largefile
# macro. Set CGO_CFLAGS (not CGO_EXTRA_CFLAGS — the Makefile hard-overrides
# that with :=); the Makefile's CGO_CFLAGS ?= keeps this env value. Keep the
# project's SQLITE_MAX_VARIABLE_NUMBER define. Drop once go-sqlite3 is bumped.
ENV CGO_CFLAGS="-g -O2 -DSQLITE_MAX_VARIABLE_NUMBER=32766 -D_LARGEFILE64_SOURCE"

#Build deps
RUN apk update && \
  apk upgrade && \
  apk --no-cache add build-base git nodejs npm && \
  apk --no-cache add sqlite>3.38

#Setup repo
COPY . ${GOPATH}/src/code.gitea.io/gitea
WORKDIR ${GOPATH}/src/code.gitea.io/gitea

#Checkout version if set
RUN if [ -n "${GITEA_VERSION}" ]; then git checkout "${GITEA_VERSION}"; fi \
  #&& make build
  && make clean-all build

FROM alpine:3.24
LABEL maintainer="maintainers@gitea.io"

EXPOSE 22 3000

RUN apk --no-cache add bash \
  ca-certificates \
  curl \
  gettext \
  git \
  linux-pam \
  openssh \
  s6 \
  sqlite \
  su-exec \
  tzdata \
  nettle \
  gnupg && \
  apk update && \
  apk upgrade

RUN addgroup \
  -S -g 1000 \
  git && \
  adduser \
  -S -H -D \
  -h /data/git \
  -s /bin/bash \
  -u 1000 \
  -G git \
  git && \
  echo "git:$(dd if=/dev/urandom bs=24 count=1 status=none | base64)" | chpasswd

ENV USER git
ENV GITEA_CUSTOM /data/gitea

VOLUME ["/data"]

ENTRYPOINT ["/usr/bin/entrypoint"]
CMD ["/bin/s6-svscan", "/etc/s6"]

#COPY docker/root /
COPY --from=build-env /go/src/code.gitea.io/gitea/gitea /app/gitea/gitea
RUN ln -s /app/gitea/gitea /usr/local/bin/gitea
