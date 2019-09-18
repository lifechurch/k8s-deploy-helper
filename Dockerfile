FROM docker:18.06.3-ce-dind

ENV HELM_VERSION="2.14.1" \
  KUBECTL_VERSION="1.12.6" \
  YQ_VERSION="2.1.1" \ 
  KUBEVAL_VERSION="0.12.0" \ 
  GLIBC_VERSION="2.28-r0" \
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

# Install kubeval
RUN wget https://github.com/garethr/kubeval/releases/download/$KUBEVAL_VERSION/kubeval-linux-amd64.tar.gz \
  && tar xvfzmp kubeval-linux-amd64.tar.gz \
  && mv kubeval /usr/local/bin \
  && chmod +x /usr/local/bin/kubeval

# Install kubectl
RUN curl -L -o /usr/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/v$KUBECTL_VERSION/bin/linux/amd64/kubectl \
  && chmod +x /usr/bin/kubectl \
  && kubectl version --client

# Install Helm
RUN set -x \
  && curl -fSL https://storage.googleapis.com/kubernetes-helm/helm-v${HELM_VERSION}-linux-amd64.tar.gz -o helm.tar.gz \
  && tar -xzvf helm.tar.gz \
  && mv linux-amd64/helm /usr/local/bin/ \
  && rm -rf linux-amd64 \
  && rm helm.tar.gz \
  && helm help



