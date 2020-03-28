set -eo pipefail

[[ "$TRACE" ]] && set -x


if [[ "$CI_JOB_STAGE" == "review" ]]; then
  export STAGE="$CI_ENVIRONMENT_SLUG"
else
  export STAGE="$CI_JOB_STAGE"
fi

ensure_variables() {
  if [[ -n "$CIRCLECI" ]]; then
    if [[ -z "$KDH_REGISTRY_USER" ]]; then
      echo "ERROR: Missing KDH_REGISTRY_USER. Make sure to configure this as an environment variable"
      exit 1
    fi

    if [[ -z "$KDH_REGISTRY_PASSWORD" ]]; then
      echo "ERROR: Missing KDH_REGISTRY_PASSWORD. Make sure to configure this as an environment variable"
      exit 1
    fi

    if [[ -z "$KDH_REGISTRY_PREFIX" ]]; then
      echo "ERROR: Missing KDH_REGISTRY_PREFIX. Make sure to configure this as an environment variable"
      exit 1
    fi

    if [[ -z "$KDH_KUBE_NAMESPACE" ]]; then
      echo "ERROR: Missing KDH_REGISTRY_PREFIX. Make sure to configure this as an environment variable"
      exit 1
    fi

    export KDH_REPO_NAME=$CIRCLE_PROJECT_REPONAME
    export KDH_SHA=$CIRCLE_SHA1
    export KDH_BRANCH=$CIRCLE_BRANCH
    export KDH_BUILD_NUMBER=$CIRCLE_BUILD_NUM
    export KDH_REGISTRY=$(echo "$KDH_REGISTRY_PREFIX" | cut -d'/' -f1)
    export KDH_REGISTRY_IMAGE="${KDH_REGISTRY_PREFIX}/${KDH_REPO_NAME}"
    export KDH_CONTAINER_NAME="ci_job_build_$KDH_BUILD_NUMBER"
    export KDH_STAGE=$CIRCLE_JOB
    export KDH_WORKING_DIR=$CIRCLE_WORKING_DIRECTORY

  elif [[ -n "$GITLAB_CI" ]]; then
    if [[ -z "$KUBE_URL" ]]; then
      echo "ERROR: Missing KUBE_URL. Make sure to configure the Kubernetes Cluster in Operations->Kubernetes"
      exit 1
    fi
    if [[ -z "$KUBE_TOKEN" ]]; then
      echo "ERROR: Missing KUBE_TOKEN. Make sure to configure the Kubernetes Cluster in Operations->Kubernetes"
      exit 1
    fi
    if [[ -z "$KUBE_NAMESPACE" ]]; then
      echo "ERROR: Missing KUBE_NAMESPACE. Make sure to configure the Kubernetes Cluster in Operations->Kubernetes"
      exit 1
    fi
    if [[ -z "$CI_ENVIRONMENT_SLUG" ]]; then
      echo "ERROR: Missing CI_ENVIRONMENT_SLUG. Make sure to configure the Kubernetes Cluster in Operations->Kubernetes"
      exit 1
    fi
    if [[ -z "$CI_ENVIRONMENT_URL" ]]; then
      echo "ERROR: Missing CI_ENVIRONMENT_URL. Make sure to configure the Kubernetes Cluster in Operations->Kubernetes"
      exit 1
    fi
    if [[ -z "$CI_DEPLOY_USER" ]]; then
      echo "ERROR: Missing CI_DEPLOY_USER. Create a deploy token at Settings->Repository->Deploy Tokens and make one named gitlab-deploy-token with read_registry access."
      exit 1
    fi
    if [[ -z "$CI_DEPLOY_PASSWORD" ]]; then
      echo "ERROR: Missing CI_DEPLOY_PASSWORD. Create a deploy token at Settings->Repository->Deploy Tokens and make one named gitlab-deploy-token with read_registry access."
      exit 1
    fi
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

buildargs_from() {
  if [[ -n "$BUILDARGS_FROM" ]]; then
    echo "BUILDARGS_FROM is set to $BUILDARGS_FROM, starting clone secret operation."
    echo "Turning on the KDH_INSERT_ARGS flag"
    export KDH_INSERT_ARGS=true
    if env | grep -i -e '^SECRET_' > /dev/null; then
      IFS=$'\n'
      SECRETS=$(env | grep -i -e '^SECRET_')
      for i in $SECRETS; do
        fullkey=$(echo $i | cut -d'=' -f1)
        stripped=$(echo $i | cut -d'_' -f2-)
        key=$(echo $stripped | cut -d'=' -f1)
        value=$(echo -n "${!fullkey}")
        echo "Exporting $key as BUILDARG_$key"
        export BUILDARG_$stripped
      done
    fi
    if env | grep -i -e "^${BUILDARGS_FROM}_" > /dev/null; then
      IFS=$'\n'
      STAGE_SECRETS=$(env | grep -i -e "^${BUILDARGS_FROM}_")
      for i in $STAGE_SECRETS; do
        fullkey=$(echo $i | cut -d'=' -f1)
        stripped=$(echo $i | cut -d'_' -f2-)
        key=$(echo $stripped | cut -d'=' -f1)
        value=$(echo -n "${!fullkey}")
        echo "Exporting $key as BUILDARG_$key"
        export BUILDARG_$stripped
      done
    fi
  fi
}

insert_args() {
  if [[ -n "$KDH_INSERT_ARGS" ]]; then
    echo "KDH_INSERT_ARGS is turned on, so we're going to re-write your Dockerfile and insert ARG commands for every BUILDARG"
    IFS=$'\n'
    ALL_VARIABLES=$(env | grep -i -e '^BUILDARG_')
    for i in $ALL_VARIABLES; do
      stripped=$(echo $i | cut -d'_' -f2-)
      key=$(echo $stripped | cut -d'=' -f1)
      echo "Inserting ARG $key into Dockerfile below the FROM"
      sed -i -e "/^FROM/a ARG $key" $DOCKERFILE
    done
    echo "Dockerfile manipulation complete. Now it looks like:"
    echo
    cat $DOCKERFILE
    echo 
  fi
}

set_defaults() {

  if [[ -v SCALE_REPLICAS ]]; then
    export SCALE_MIN=$SCALE_REPLICAS
    export SCALE_MAX=$SCALE_REPLICAS
  fi

  if [[ ! -v SCALE_MIN ]]; then
    export SCALE_MIN=2
  fi

  if [[ ! -v SCALE_MAX ]]; then
    export SCALE_MAX=4
  fi

  if [[ ! -v SCALE_CPU ]]; then
    export SCALE_CPU=60
  fi

  if [[ ! -v PDB_MIN ]]; then
    export PDB_MIN="50%"
  fi

  if [[ ! -v PORT ]]; then
    export PORT=5000
  fi

  if [[ ! -v PROBE_URL ]]; then
    export PROBE_URL="/"
  fi

  if [[ ! -v LIMIT_CPU ]]; then
    export LIMIT_CPU="1"
  fi

  if [[ ! -v LIMIT_MEMORY ]]; then
    export LIMIT_MEMORY="512Mi"
  fi

  if [[ ! -v LIVENESS_PROBE ]]; then
    export LIVENESS_PROBE="/bin/true"
  fi
}

set_prefix_defaults() {
  memory=${1}_LIMIT_MEMORY
  cpu=${1}_LIMIT_CPU
  liveness=${1}_LIVENESS_PROBE
  replicas=${1}_REPLICAS
  min_replicas=${1}_SCALE_MIN
  max_replicas=${1}_SCALE_MAX
  scale_cpu=${1}_SCALE_CPU

  if [[ -v ${replicas} ]]; then
    export ${min_replicas}=${!replicas}
    export ${max_replicas}=${!replicas}
  fi

  if [[ ! -v ${min_replicas} ]]; then
    export ${min_replicas}="1"
  fi

  if [[ ! -v ${max_replicas} ]]; then
    export ${max_replicas}="1"
  fi

  if [[ ! -v ${scale_cpu} ]]; then
    export ${scale_cpu}="60"
  fi

  if [[ ! -v ${memory} ]]; then
    export ${memory}="512Mi"
  fi

  if [[ ! -v ${cpu} ]]; then
    export ${cpu}="1"
  fi

  if [[ ! -v ${liveness} ]]; then
    export ${liveness}="/bin/true"
  fi
}

set_buildargs() {
  IFS=$'\n'
  if env | grep -i -e '^BUILDARG_' > /dev/null; then
    ALL_VARIABLES=$(env | grep -i -e '^BUILDARG_')
    for i in $ALL_VARIABLES; do
      fullkey=$(echo $i | cut -d'=' -f1)
      stripped=$(echo $i | cut -d'_' -f2-)
      key=$(echo $stripped | cut -d'=' -f1)
      value=$(echo -n "${!fullkey}")
      buildargs="${buildargs}--build-arg $key='$value' "
    done
    export buildargs=$buildargs
  fi
}

build_env() {
  IFS=$'\n'
  echo "Removing .env file"
  rm $KDH_WORKING_DIR/.env &> /dev/null || true
  if env | grep -i -e '^BUILDARG_' > /dev/null; then
    ALL_VARIABLES=$(env | grep -i -e '^BUILDARG_')
    for i in $ALL_VARIABLES; do
      fullkey=$(echo $i | cut -d'=' -f1)
      stripped=$(echo $i | cut -d'_' -f2-)
      key=$(echo $stripped | cut -d'=' -f1)
      value=$(echo -n "${!fullkey}")
      echo "$key=$value" >> $KDH_WORKING_DIR/.env
    done
  fi
}

setup_docker() {
  if ! docker info &>/dev/null; then
    if [ -z "$DOCKER_HOST" -a "$KUBERNETES_PORT" ]; then
      export DOCKER_HOST='tcp://localhost:2375'
    fi
  fi
}

get_secrets_for_creation() {
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

  if env | grep -i -e "^$KDH_STAGE"_ > /dev/null; then
    IFS=$'\n'
    STAGE_SECRETS=$(env | grep -i -e "^$KDH_STAGE")
    for i in $STAGE_SECRETS; do
      fullkey=$(echo $i | cut -d'=' -f1)
      stripped=$(echo $i | cut -d'_' -f2-)
      key=$(echo $stripped | cut -d'=' -f1)
      value=$(echo -n "${!fullkey}" | base64 -w 0)
      echo "  $key: $value"
    done
  fi
}

get_secrets_for_usage() {
  if env | grep -i -e '^SECRET_' > /dev/null; then
    IFS=$'\n'
    SECRETS=$(env | grep -i -e '^SECRET_')
    for i in $SECRETS; do
      fullkey=$(echo $i | cut -d'=' -f1)
      stripped=$(echo $i | cut -d'_' -f2-)
      key=$(echo $stripped | cut -d'=' -f1)
      value=$(echo -n "${!fullkey}" | base64 -w 0)
      echo "- name: $key" >> /tmp/secrets.yaml
      echo "  valueFrom:" >> /tmp/secrets.yaml
      echo "    secretKeyRef:" >> /tmp/secrets.yaml
      echo "      name: $KDH_KUBE_NAMESPACE-secrets-$STAGE" >> /tmp/secrets.yaml
      echo "      key: $key" >> /tmp/secrets.yaml
    done
  fi

  if env | grep -i -e "^$KDH_STAGE"_ > /dev/null; then
    IFS=$'\n'
    STAGE_SECRETS=$(env | grep -i -e "^$KDH_STAGE")
    for i in $STAGE_SECRETS; do
      fullkey=$(echo $i | cut -d'=' -f1)
      stripped=$(echo $i | cut -d'_' -f2-)
      key=$(echo $stripped | cut -d'=' -f1)
      value=$(echo -n "${!fullkey}" | base64 -w 0)
      echo "- name: $key" >> /tmp/secrets.yaml
      echo "  valueFrom:" >> /tmp/secrets.yaml
      echo "    secretKeyRef:" >> /tmp/secrets.yaml
      echo "      name: $KDH_KUBE_NAMESPACE-secrets-$STAGE" >> /tmp/secrets.yaml
      echo "      key: $key" >> /tmp/secrets.yaml
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
        if echo "$i" | grep -i -e "$KDH_STAGE" | grep -i -e "APP_ID" > /dev/null; then
            export NEWRELIC_APP_ID=$(echo $i | cut -d'=' -f2)
        fi
    done
  fi

  if env | grep -i -e '^SLACK' > /dev/null; then
    SLACK=$(env | grep -i -e '^SLACK')
    for i in $SLACK; do
        if echo "$i" | grep -i -e "$KDH_STAGE" | grep -i -e "WEBHOOK" > /dev/null; then
            export SLACK_WEBHOOK_URL=$(echo $i | cut -d'=' -f2)
        elif echo "$i" | grep -i -e "^SLACK_WEBHOOK" > /dev/null; then
            export SLACK_WEBHOOK_URL=$(echo $i | cut -d'=' -f2)
        fi
    done
  fi

  if env | grep -i -e '^TEAMS' > /dev/null; then
    TEAMS=$(env | grep -i -e '^TEAMS')
    for i in $TEAMS; do
        if echo "$i" | grep -i -e "$KDH_STAGE" | grep -i -e "WEBHOOK" > /dev/null; then
            export TEAMS_WEBHOOK_URL=$(echo $i | cut -d'=' -f2)
        elif echo "$i" | grep -i -e "^TEAMS_WEBHOOK" > /dev/null; then
            export TEAMS_WEBHOOK_URL=$(echo $i | cut -d'=' -f2)
        fi
    done
  fi

  if env | grep -i -e '^INSTANA' > /dev/null; then
    INSTANA=$(env | grep -i -e '^INSTANA')
    for i in $INSTANA; do
        if echo "$i" | grep -i -e "$KDH_STAGE" | grep -i -e "API_TOKEN" > /dev/null; then
            export INSTANA_API_TOKEN=$(echo $i | cut -d'=' -f2)
        elif echo "$i" | grep -i -e "^INSTANA_API_TOKEN" > /dev/null; then
            export INSTANA_API_TOKEN=$(echo $i | cut -d'=' -f2)
        fi
    done
  fi
}