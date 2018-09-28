FROM docker:17.11.0-ce-dind

ENV HELM_VERSION="2.6.1" \
    KUBECTL_VERSION="1.8.7" \
    YQ_VERSION="1.14.0" \ 
    HELM_SHA256="5e90d8ad17ba42e67dad97b5c2230707beadd2635f89d6ccc96f8a92777c42c4" \
    GLIBC_VERSION="2.23-r3" \
    PATH=/opt/kubernetes-deploy:$PATH

# Install pre-req
RUN apk add -U openssl curl tar gzip bash ca-certificates git wget jq libintl coreutils \
   && apk add --virtual build_deps gettext \
   && mv /usr/bin/envsubst /usr/local/bin/envsubst \
   && apk del build_deps

# Install deploy scripts
COPY / /opt/kubernetes-deploy/

# Install glibc for Alpine
RUN wget -q -O /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub \ 
    && wget https://github.com/sgerrand/alpine-pkg-glibc/releases/download/$GLIBC_VERSION/glibc-$GLIBC_VERSION.apk \ 
    && apk add glibc-$GLIBC_VERSION.apk \ 
    && rm glibc-$GLIBC_VERSION.apk

# Install yq
RUN wget -q -O /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/$YQ_VERSION/yq_linux_amd64 && chmod +x /usr/local/bin/yq

# Install kubectl
RUN curl -L -o /usr/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/v$KUBECTL_VERSION/bin/linux/amd64/kubectl \
    && chmod +x /usr/bin/kubectl \
    && kubectl version --client

# Install Helm
RUN set -x \
  && curl -fSL https://storage.googleapis.com/kubernetes-helm/helm-v${HELM_VERSION}-linux-amd64.tar.gz -o helm.tar.gz \
  && echo "${HELM_SHA256} *helm.tar.gz" | sha256sum -c - \
  && tar -xzvf helm.tar.gz \
  && mv linux-amd64/helm /usr/local/bin/ \
  && rm -rf linux-amd64 \
  && rm helm.tar.gz \
  && helm help



