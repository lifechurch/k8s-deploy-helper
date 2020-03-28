[![Docker Repository on Quay](https://quay.io/repository/lifechurch/k8s-deploy-helper/status "Docker Repository on Quay")](https://quay.io/repository/lifechurch/k8s-deploy-helper)

# Description
k8s-deploy-helper (KDH) is a tool to help build and deploy containerized applications into Kubernetes using GitLab CI along with templated manifest files. Major features include:

* Automated Kubernetes Secret Management using GitLab's UI. Version 3.0.0 can automatically insert secrets into Kubernetes manifests and Dockerfiles to lessen manual work.
* Build via Heroku buildpacks or via Dockerfiles starting in 3.1.0.
* Automated canary deployments. Dynamic creation is included in version 3.0.0.
* Automated review app deployments.
* Automated deployment of applications using Heroku Procfile in 3.1.0.
* Deployment notifications to New Relic, Datadog and Slack.
* Templated manifest deployments to Kubernetes living in the same repo as the code, giving developers more control.
* Uses [kubeval](https://github.com/garethr/kubeval) to evaluate manifest yaml before any are deployed.
* Easy, standardized image creation with build arguments and multiple Dockerfile support.
* Standardized building conventions to allow for easy rollbacks through GitLab UI and better caching.


This project is not endorsed or affiliated with GitLab in any way.

# Examples
In addition to this documentation, the best way to get started is to look at our [example repository](https://github.com/lifechurch/example-go).

Need some help getting started? Feel free to join us on [Open Digerati Slack](https://join.slack.com/t/opendigerati/shared_invite/enQtMjU4MTcwOTIxMzMwLTcyYjQ4NWEwMzBlOGIzNDgyM2U5NzExYTY3NmI0MDE4MTRmMTQ5NjNhZWEyNDY3N2IyOWZjMDIxM2MwYjEwMmQ) in #k8s and we'll be more than happy to assist.

# Why?
GitLab's Auto DevOps initiative is amazing for getting simple apps running quickly, but for slightly more complex and production workloads, you need more control in the process. For instance, what if you have a pod with sidecar containers? What if you want a deployment of worker pods using something like celery for async work? You'll need to interact with Kubernetes at a deeper level to do stuff like this, and that's where our project comes in.

At Life.Church, we wanted to create a standardized tool along with corresponding conventions that our developers could use with GitLab CI to allow us to get up and running with manifest-based deployments as quickly and easily as possible. So, we took the work that GitLab started, and used it as the base of a new project that would meet our needs.

This tool was built akin to an airplane that was built while we were flying it. Our process is constantly maturing as we learn more about how to deploy into k8s. Our goal isn't to say 'this is the best way of deploying', but simply to share how we're doing it now, knowing that it will at least be a helpful starting place for others who are embarking on their Kubernetes journey.

# Prerequisites

* GitLab w/customizable runners
* Kubernetes

## Configuring GitLab Runner

There is a lot of discussion around the best way to build docker images from within Docker. We ended up going the route of sharing the Docker socket.  Here is a sample GitLab Runner configuration. Of particular note, is the volumes section, to share the socket the way we expect. Additionally, we use dind for some stages, so privileged needs to be turned on as well.

```
[[runners]]
  name = "runner01"
  limit = 16
  url = "https://runneriurl/ci"
  token = "token"
  executor = "docker"
  [runners.docker]
    tls_verify = false
    image = "docker:latest"
    privileged = true
    disable_cache = false
    volumes = ["/var/run/docker.sock:/var/run/docker.sock", "/cache"]
    shm_size = 0
  [runners.cache]
```

## Integrate Kubernetes into your Project

In your GitLab Project, go to Operations->Kubernetes to give GitLab the ability to talk to your Kubernetes cluster. See GitLab's documentation on how to do this properly.

## GitLab Credentials
GitLab has finally introduced a way to have persistent deploy tokens that can fetch things from the Docker registry. k8s-deploy-helper 3.0 now uses this more secure token. You can create a deploy token at Settings->Repository->Deploy Tokens and make one named ```gitlab-deploy-token``` with read_registry access. It HAS to be called ```gitlab-deploy-token``` due to GitLab limitations. Once this token is created, k8s-deploy-helper will pick it up automatically.

# Building Docker Images

Our goal was to make sure Docker containers could be built as quickly as possible without the developers having to micromanage each docker build command on a per-project basis.

Here is a quick example from the .gitlab-ci.yml:

```
build_container:
  stage: build
  script:
    - command build
  only:
    - branches
```

Notice the script only has one command: ```command build``` - k8s-deploy-helper takes it from there, building the container, tagging it with a unique id (commit hash), and pushing it into the GitLab docker registry.

## Caching Docker FS Layers

By default, k8s-deploy-helper and the accompanying examples use a convention where the build that is deployed to production is given the ```latest``` tag after successful deployment. When building Docker containers, we use --cache-from your docker image's ```latest``` tag. This will allow for more optimized caching when using multiple GitLab runners or runners without persistent storage.

If you're managing your own runners, and you only have one, then you may want to think about setting a variable named  ```KDH_SKIP_LATEST``` to ```true``` in your build stages or in the GitLab variables UI. When k8s-deploy-helper finds this variable set to true, we don't use --cache-from, and will just build the Docker container normally, which will try and make use of the cache that is already present in the runner.

## Build Arguments

Sometimes you need to pass in arguments to containers at build time to do things like putting a token in place to pull from a private npm registry. To pass in build arguments, simply go to your GitLab project and go to Settings->CI/CD->Variables and create a variable in this form:

```BUILDARG_npmtoken=1111```

When we build the Docker container, we look for all environment variables that start with ```BUILDARG_```, strip that prefix out, and pass it into docker via --build-arg. In the example above, this will create a build argument ```npmtoken``` with a value of ```1111```

In the example above, you would have to put the following line into your Dockerfile in order to use it at build time:

```ARG npmtoken```

## Automatic ARG Insertion
Starting in 3.0, you can set a variable named ```KDH_INSERT_ARGS``` to ```true```, and k8s-deploy-helper will automatically take all your build arguments and insert corresponding ARG commands into your Dockerfile at build time, immediately after FROM lines. This makes GitLab the source of truth and you as a developer will no longer have to worry about setting things in multiple places.

Inserting things into your Dockerfile at runtime is definitely considered a bit magic though, so we make this a feature you have to opt into.

## Secrets as Buildargs
Sometimes you may have an application that has logic that looks to make sure all environment variables are present before you can run any command (like asset generation). k8s-deploy-helper has the ability to automatically create secrets and use them in your Kubernetes manifests, which we will go into later on. If you set the variable ```BUILDARGS_FROM``` to ```production```, it will take all the secrets that would be created to run in the ```production``` stage and automatically use them as build arguments when creating your Docker container. This will also turn on the ```KDH_INSERT_ARGS``` feature and will insert ```ARG``` statements into your Dockerfile automatically.

## Build Multiple Dockerfiles

If your project needs to build multiple Dockerfiles, the helper will automatically handle all the naming convention management to avoid collisions.  All you need to do is pass in the file name of the Dockerfile that is in the root of your repository. For example, if you have two Dockerfiles, Dockerfile-app, and Dockerfile-worker, this is what your .gitlab-ci.yml would look like:

```
build_app:
  stage: build
  script:
    - command build Dockerfile-app
  only:
    - branches

build_worker:
  stage: build
  script:
    - command build Dockerfile-worker
  only:
    - branches
```

## Buildpack Builds
Starting in 3.1.0, KDH can build applications using [Heroku Buildpacks](https://devcenter.heroku.com/articles/buildpacks) via [herokuish](https://github.com/gliderlabs/herokuish). To do this, we run the latest herokuish docker container to make sure you have access to the latest buildpacks. Because we mount your code into the herokuish docker container, we need to use dind, so you'll need to make sure your GitLab runner has privileged access. All you need to do is not have a Dockerfile in your root, and we'll use the buildpack method. In the gitlab-ci, you'll need to expose docker:stable-dind as a service like so:

```
build:
  stage: build
  services:
    - docker:stable-dind
  script:
    - command build
  only:
    - branches
```

You can use BUILDARG_ syntax from above to pass in build arguments, such as npm tokens, etc...

# Kubernetes Deployment

The key to success here is being able to use variables in your manifests. By using the right variables in the right places, you can have one single deployment manifest to maintain that can create deployments for review apps, staging, canaries, and production. See our [example repository](https://github.com/lifechurch/example-go) for more information on how to properly set up your manifests.

## Directory Structure
To deploy applications into Kubernetes, you need to place your templated manifest files into a ```kubernetes``` directory at the root of your repository.

```
kubernetes
|-->deployment.yaml
|-->service.yaml
```

## Per-Stage Directory Structure

Sometimes you have manifests that you only want to run in particular stages. For instance, you may want horizontal pod autoscalers only for production, but not for staging or review apps. All you have to do is create a directory name that corresponds to your build stage.

```
kubernetes
|production
||-->hpa.yaml
|-->deployment.yaml
|-->service.yaml
```

## Debugging
Starting in 3.0, k8s-deploy-helper renders all templates before trying to apply them. All rendered manifests are displayed in the runner for easy debugging. The rendered templates are put in ```/tmp/kubernetes``` if you want to grab them using GitLab artifacts for some reason. In addition, we now use kubeval.

## kubeval
KDH will try to figure out the version of Kubernetes you are deploying to, and then target kubeval specificaly for that version.

Optionally, you can set the KDH_SKIP_KUBEVAL variable to true in order to skip the use of kubeval.

## Canary Deploys
As of 3.0, k8s-deploy-helper will automatically support canary deployments via rewriting your deployment manifests. To use this functionality, you just need to be in a GitLab CI stage named canary, and k8s-deploy-helper will search for manifests where the ```track``` label is set to ```stable```.

The canary stage operates as a production deployment.

Check out our (example repo)[https://www.github.com/lifechurch/example-go] to see how to set up your manifests to support this automation.

## Environment Variable Substitution
As of 7.0, k8s-deploy-helper added some logic that will only substitute environment variables that exist into your manifest files.  

# Secret Management

For people just getting started with deploying apps to Kubernetes, one of the first questions is 'how do I keep secrets out of my repositories?' k8s-deploy-helper has built-in secret management that allows you to securely use GitLab as the source of truth for all secrets.

How k8s-deploy-helper handles secrets is probably the hardest part to wrap your minds around initially, so read these documents carefully.


## Secret Creation
To create a secret, go to your GitLab project and go to Settings->CI/CD->Variables and create a variable with this name pattern:

```SECRET_mykeyname```

During deployment, our scripts will look for all environment variables that start with the prefix ```SECRET_```, strip out the prefix and sticks the key and value into a kubernetes secret named ```$KUBE_NAMESPACE-secrets-$STAGE```, which translates to something like ```yournamespacename-secrets-production``` or ```yournamespacename-secrets-staging```

In the example above, there would be an entry in the secret file named ```mykeyname``` with the corresponding value you put in GitLab. You can then access these secrets in your manifest files. The below will create an environment variable in your pod called mykeyname.

```
        env:
          - name: mykeyname
            valueFrom:
              secretKeyRef:
                name: $KUBE_NAMESPACE-secrets-$STAGE
                key: mykeyname
```
**The important thing to note is that k8s-deploy-helper does the stripping of the SECRET_ prefix during secret creation TO RUN IN KUBERNETES. When dealing with stages outside of k8s-deploy-helper, like for instance, a testing stage or a stage that does database migrations, your variables are sent as is to your GitLab Runners, prefixes and all.**

## Per-Stage Secret Creation

Sometimes you have secrets that have different values depending on if you're running in production or staging. Our helper allows you to do this by prefixing your secret with the uppercased version of your GitLab CI stage name.

For example, let's say you have a secret called ```api_env```, that needs to have different values depending on if you're deploying to one of three stages: review, staging, or production.

Instead of creating a variable in GitLab called ```SECRET_api_env```, you would create three:

```
REVIEW_api_env
STAGING_api_env
PRODUCTION_api_env
```

Combined with a templated section like below, this would pull in the secret from wherever.

```
        env:
          - name: api_env
            valueFrom:
              secretKeyRef:
                name: $KUBE_NAMESPACE-secrets-$STAGE
                key: api_env
      imagePullSecrets:
```
## Automated Secret Management in manifests

New in version 3.0 is the {{SECRETS}} command. In the examples above, we gave the code that you would insert into manifests to make the secrets that k8s-deploy-helper creates in Kubernetes usable from within your deployments. This meant for adding a new secret, you would have to set the value of the secret in GitLab, and then add some code to the manifest to make it accessible.

Wanting to make developers lives easier and make GitLab the source of truth, we introduced the {{SECRETS}} command that you can insert into your templates at the appropriate place, and when we render your manifest templates, we will loop through all the secrets that k8s-deploy-helper created on your behalf, and insert the appropriate code into the manifest for you!

To use it, just stick {{SECRETS}} in the right place underneath your env: section. Make sure it's placed correctly.

```
env:
  {{SECRETS}}
```

# Deploy Events

Currently NewRelic, Slack, Datadog, Instana, & Microsoft Teams deploy events are supported.

In Gitlab for NewRelic, you'll need to add a secret variable with the NewRelic API key and App Ids
for each stage you want a deployment event for. Like:

```
NEWRELIC_API_KEY=xxx
NEWRELIC_STAGING_APP_ID=xxx
NEWRELIC_PRODUCTION_APP_ID=xxx
```

For Slack, you can simply set a Gitlab secret variable with the [Slack webhook URL](https://api.slack.com/incoming-webhooks) if you want notifications for every stage.

```
SLACK_WEBHOOK=xxx
```

If you want notifications for specific stages use the following format.

```
SLACK_{{STAGE}}_WEBHOOK
```

E.g.

```
SLACK_STAGING_WEBHOOK=xxx
SLACK_PRODUCTION_WEBHOOK=xxx
```

For Datadog, you *must* set your Datadog API key with:

```
DATADOG_API_KEY=xxx
```

Optionally, you may set an [app key, message text, and tags to send to Datadog.] (https://docs.datadoghq.com/api/?lang=bash#post-an-event)

The text attribute supports markdown. [This help article](https://help.datadoghq.com/hc/en-us/articles/204778779)
best explains how to add markdown text to the deploy event.

The DATADOG_TAGS variable can be used to send one or more tags with the event. Because this is an
array in the POST, you *must* include quotes around each value. Multiple tags should then be
separated by commas.

```
DATADOG_APP_KEY=xxx
DATADOG_TAGS="deploys:api","foo:bar"
DATADOG_TEXT=\n%%%\n### Success\n%%%
```

For Teams, you can simply set a Gitlab secret variable with a [Teams Incoming Webhook](https://docs.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook#add-an-incoming-webhook-to-a-teams-channel) if you want notifications for every stage.

```
TEAMS_WEBHOOK=xxx
```

If you want notifications for specific stages use the following format.

```
TEAMS_{{STAGE}}_WEBHOOK=xxx
```

E.g.

```
TEAMS_STAGING_WEBHOOK=xxx
TEAMS_PRODUCTION_WEBHOOK=xxx
```

For Instana, you *must* set your Instana API Token & Instana Base URL with:

```
INSTANA_API_TOKEN=xxx
INSTANA_BASE_URL=https://<dashboard-url>
```

If you want notifications for specific stages use the following format.

```
INSTANA_{{STAGE}}_API_TOKEN
```

E.g.

```
INSTANA_STAGING_API_TOKEN=xxx
INSTANA_PRODUCTION_API_TOKEN=xxx
```

Per Instana's docs it's important to note:

    The used API Token requires the permission “Configuration of releases”.
    A release has no scope and is therefore globally applied to the whole monitored system.

Based on that last note you can set these variables at a group level and not have to manage them at the project level.

# Manifest-less Deploys
Starting in 3.1.0, we added an option for manifest-less deploys to help us migrate away from Deis Workflow. In order for this to work, we had to make some very opinionated decisions regarding our manifests. These may not work for your organization. If this is the case, we encourage you to fork our project and make your own default manifests. They can be found in the manifests directory.

## Manifest-less Requirements

* nginx Ingress Controller

* cert-manager or kube-lego that can issue "Let's Encrypt" certificates via the ```kubernetes.io/tls-acme: 'true'``` annotation.

## Conventions

* We will obey Procfiles and every line will get its own deployment. Web will get an ingress, service, pod disruption budget, and autoscaling. Every other line will be treated as worker, and will just get autoscaling.

## Variables & Defaults

### Web

* LIMIT_CPU: 1 - CPU Resource Limit

* LIMIT_MEMORY: 512Mi - Memory Resource Limit

* SCALE_REPLICAS (Production Only): Not Set - If SCALE_REPLICAS is set, SCALE_MIN and SCALE_MAX will be set to the value of SCALE_REPLICAS.

* SCALE_MIN (Production Only): 2 - Minimum amount of running pods set in the HPA

* SCALE_MAX (Production Only): 4 - Maximum amount of running pods set in the HPA

* SCALE_CPU (Production Only): 60 - CPU usage at which autoscaling occurs

* PDB_MIN (Production Only): 50% - Minimum available percentage

* PORT: 5000 - The port your app listens on

* PROBE_URL: / - The URL that will get hit for readiness probe

* LIVENESS_PROBE: /bin/true - The command used for the liveness probe

### Other (workers)

To set variables for your other runtimes specified in the Procfile, you can create variables with this pattern. For example, let's say you have a worker that's named ```worker``` in your Procfile and you want to assign 2 CPU to each pod, you would set a variable named ```worker_LIMIT_CPU``` to ```2```.

Variables you can set to control your worker stages are listed below, along with their default values. We'll refer to the name of your stage as ${1}.

```
  ${1}_LIMIT_CPU: 1
  ${1}_LIMIT_MEMORY: 512Mi
  ${1}_LIVENESS_PROBE: /bin/true
  ${1}_REPLICAS: Not Set
  ${1}_SCALE_MIN: 1
  ${1}_SCALE_MAX: 1
  ${1}_SCALE_CPU : 60%
```


# Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct, and the process for submitting pull requests.

# Versioning
To make sure the community can use this project with their sanity intact, we will be committing to incrementing major versions when we introduce breaking changes.  We anticipate this happening frequently, as this tool is still under heavy development.

We use [SemVer](http://semver.org/) for versioning. For the versions available, see the [tags on this repository](https://github.com/lifechurch/k8s-deploy-helper/tags).

# License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.
