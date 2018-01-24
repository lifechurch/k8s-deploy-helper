set -eo pipefail

[[ "$TRACE" ]] && set -x

export CI_CONTAINER_NAME="ci_job_build_$CI_JOB_ID"
export CI_REGISTRY_TAG="$CI_COMMIT_SHA"

if [[ "$CI_JOB_STAGE" == "review" ]]; then
  export STAGE="$CI_ENVIRONMENT_SLUG"
else
  export STAGE="$CI_JOB_STAGE"
fi

create_kubeconfig() {
  echo "Generating kubeconfig..."
  export KUBECONFIG="$(pwd)/kubeconfig"
  export KUBE_CLUSTER_OPTIONS=
  if [[ -n "$KUBE_CA_PEM" ]]; then
    echo "Using KUBE_CA_PEM..."
    echo "$KUBE_CA_PEM" > "$(pwd)/kube.ca.pem"
    export KUBE_CLUSTER_OPTIONS=--certificate-authority="$(pwd)/kube.ca.pem"
  fi
  kubectl config set-cluster gitlab-deploy --server="$KUBE_URL" \
    $KUBE_CLUSTER_OPTIONS
  kubectl config set-credentials gitlab-deploy --token="$KUBE_TOKEN" \
    $KUBE_CLUSTER_OPTIONS
  kubectl config set-context gitlab-deploy \
    --cluster=gitlab-deploy --user=gitlab-deploy \
    --namespace="$KUBE_NAMESPACE"
  kubectl config use-context gitlab-deploy
  mkdir /root/.kube || true
  cp kubeconfig /root/.kube/config
  cp kube.ca.pem /root/.kube/
  echo ""
  helm init --client-only
}

ensure_deploy_variables() {
    if [[ -z "$KUBE_URL" ]]; then
      echo "Missing KUBE_URL."
      exit 1
    fi
    if [[ -z "$KUBE_TOKEN" ]]; then
      echo "Missing KUBE_TOKEN."
      exit 1
    fi
    if [[ -z "$KUBE_NAMESPACE" ]]; then
      echo "Missing KUBE_NAMESPACE."
      exit 1
    fi
    if [[ -z "$CI_ENVIRONMENT_SLUG" ]]; then
      echo "Missing CI_ENVIRONMENT_SLUG."
      exit 1
    fi
    if [[ -z "$CI_ENVIRONMENT_URL" ]]; then
      echo "Missing CI_ENVIRONMENT_URL."
      exit 1
    fi
}

ping_kube() {
  if kubectl version > /dev/null; then
    echo "Kubernetes is online!"
    echo ""
  else
    echo "Cannot connect to Kubernetes."
    return 1
  fi
}

get_buildargs() {
  IFS=$'\n'
  ALL_VARIABLES=$(env | grep -i -e '^BUILDARG_')
  for i in $ALL_VARIABLES; do
    stripped=$(echo $i | cut -d'_' -f2-)
    buildargs+="--build-arg $stripped "
  done
  echo $buildargs
}

setup_docker() {
  if ! docker info &>/dev/null; then
    if [ -z "$DOCKER_HOST" -a "$KUBERNETES_PORT" ]; then
      export DOCKER_HOST='tcp://localhost:2375'
    fi
  fi
}

get_secrets() {
  if env | grep -i -e '^SECRET_' > /dev/null; then
    IFS=$'\n'
    SECRETS=$(env | grep -i -e '^SECRET_')
    for i in $SECRETS; do
      fullkey=$(echo $i | cut -d'=' -f1)
      stripped=$(echo $i | cut -d'_' -f2-)
      key=$(echo $stripped | cut -d'=' -f1)
      value=$(echo -n "${!fullkey}" | base64 -w 0)
      echo "  $key: $value"
    done
  fi

  if env | grep -i -e "^$CI_JOB_STAGE"_ > /dev/null; then
    STAGE_SECRETS=$(env | grep -i -e "^$CI_JOB_STAGE")
    for i in $STAGE_SECRETS; do
      fullkey=$(echo $i | cut -d'=' -f1)
      stripped=$(echo $i | cut -d'_' -f2-)
      key=$(echo $stripped | cut -d'=' -f1)
      value=$(echo -n "${!fullkey}" | base64 -w 0)
      echo "  $key: $value"
    done
  fi
}

get_deploy_events() {
  if env | grep -i -e '^NEWRELIC_' > /dev/null; then
    NEWRELIC=$(env | grep -i -e '^NEWRELIC_')
    for i in $NEWRELIC; do
        if echo "$i" | grep -i -e "API_KEY" > /dev/null; then
            export NEWRELIC_API_KEY=$(echo $i | cut -d'=' -f2)
        fi
        if echo "$i" | grep -i -e "$CI_JOB_STAGE" | grep -i -e "APP_ID" > /dev/null; then
            export NEWRELIC_APP_ID=$(echo $i | cut -d'=' -f2)
        fi
    done
  fi

  if env | grep -i -e '^SLACK_WEBHOOK' > /dev/null; then
    export SLACK_WEBHOOK_URL=$(env | grep -i -e '^SLACK_WEBHOOK' | cut -d'=' -f2)
  fi
}
