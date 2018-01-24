# Description
k8s-deploy-helper is a tool to help build and deploy containerized applications into Kubernetes using GitLab CI along with templated manifest files. Major features include:

* Automated Kubernetes Secret Management using GitLab's UI
* Templated manifest deployments to Kubernetes living in the same repo as the code, giving developers more control.
* Easy, standardized image creation with build arguments and multiple Dockerfile support
* Standardized container tag conventions to allow for easy rollbacks through GitLab UI and better caching
* New Relic deployment notification

This project is not endorsed or affiliated with GitLab in any way.

# Examples
In addition to this documentation, the best way to get started is look at our [example repository](https://github.com/lifechurch/example-go)

Need some help getting started? Feel free to join us on [Open Digerati Slack](https://join.slack.com/t/opendigerati/shared_invite/enQtMjU4MTcwOTIxMzMwLTcyYjQ4NWEwMzBlOGIzNDgyM2U5NzExYTY3NmI0MDE4MTRmMTQ5NjNhZWEyNDY3N2IyOWZjMDIxM2MwYjEwMmQ) in #k8s and we'll be more than happy to assist.

# Why?
GitLab's Auto DevOps initiative is amazing for getting simple apps running quickly, but for slightly more complex and production workloads, you need more control in the process. For instance, what if you have a pod with sidecar containers because you want to run inside a service mesh? What if you want a deployment of worker pods using something like celery for async work? You'll need to interact with Kubernetes at a deeper level to do stuff like this, and that's where our project comes in.

At Life.Church, we wanted to create a standardized tool along with corresponding conventions that our developers could use with GitLab CI to allow us to get up and running with manifest-based deployments as quickly and easily as possible. So, we took the work that GitLab started, and used it as the base of a new project that would meet our needs.

This tool was built akin to an airplane that was built while we were flying it. Our process is constantly maturing as we learn more about how to deploy into k8s. Our goal isn't to say 'this is the best way of deploying', but simply to share how we're doing it now knowing that it will at least be a helpful starting place for others who are embarking on their Kubernetes journey.

# Prerequisites

* GitLab w/customizable runners
* Kubernetes

## Configuring GitLab Runner

There is a lot of discussion around the best way to build docker images from within Docker. We ended up going the route of sharing the Docker socket.  Here is a sample GitLab Runner configuration. Of particular note, is the volumes section, to share the socket the way we expect.

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
    privileged = false
    disable_cache = false
    volumes = ["/var/run/docker.sock:/var/run/docker.sock", "/cache"]
    shm_size = 0
  [runners.cache]
```


## Integrate Kubernetes into your Project

In your GitLab Project, go to Settings->Integrations and setup Kubernetes. See GitLab's documentation on how to do this properly.

## GitLab Credentials
By far the most annoying part of GitLab's CI system is that the credentials to connect to the registry that they pass down are only valid for a certain amount of time. While that works well for pushing a container into the registry, it doesn't work well for running things in Kubernetes. Because the credentials expire after a certain amount of time, if a pod reboots or some scaling event happens, Kubernetes will no longer be able to grab your containers from the GitLab registry if it's private.

**The only workaround to this is to create an actual user in GitLab and make sure it has access to the necessary groups and projects.**

Our helper expects the ```GL_USERNAME``` and the ```GL_PASSWORD``` variables to exist, and have the newly created credentials. It will take those variables, and create a secret in your kubernetes namespace called gitlab-registry, which your manifests can then use.

You can do this in one of two ways:

1) Create these variables in GitLab by going to your Project Settings->CI/CD->Secret Variables, and creating them there.

OR

2) If your GitLab setup is only used by one team, or if you're ok with the security ramifications that this creates, you could configure the credentials in your runner, so your developers don't have to complete this step. The runner config would look something like:

```
[[runners]]
  name = "runner01"
  limit = 16
  url = "https://runneriurl/ci"
  token = "token"
  executor = "docker"
  environment = ["GL_USERNAME=dockeruser", "GL_PASSWORD=mysupersecuredockerpassword"]
  [runners.docker]
    tls_verify = false
    image = "docker:latest"
    privileged = false
    disable_cache = false
    volumes = ["/var/run/docker.sock:/var/run/docker.sock", "/cache"]
    shm_size = 0
  [runners.cache]
```


# Building Docker Images

Our goal was to make sure Docker containers could be built as quickly as possible without the developers having to micromanage each docker build command on a per-project basis.

**All that is required is that the Dockerfile be in the root of the repo**

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

In addition to tagging your build with a unique id, we also tag each new build with the latest tag. We needed a stable tag that our builder could use the --cache-from feature of Docker to allow for faster container builds when you have multiple runners. We are open to PR's with a better way to do this!

## Build Arguments

Sometimes you need to pass in arguments to containers at build time to do things like putting a token in place to pull from a private npm registry. To pass in build arguments, simply go to your GitLab project and go to Settings->CI/CD->Secret Variables and create a secret in this form:

```BUILDARG_npmtoken=1111```

When we build the Docker container, we look for all environment variables that start with ```BUILDARG_```, strip that prefix out, and pass it into docker via --build-arg. In the example above, this will create a build argument ```npmtoken``` with a value of ```1111```

In your Dockerfile, you'll need to have something ready to take in these build arguments.

```
ARG npmtoken
ENV npmtoken: $npmtoken
```

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

# Kubernetes Deployment

Here's a sample of kicking the deployer helper off in the .gitlab-ci.yml

```
staging:
  stage: staging
  only:
    - master
  script:
    - command deploy
  environment:
    name: staging
    url: https://stagingurl
```

## Directory Structure
To deploy applications into Kubernetes, you need to place your templated manifest files into a kubernetes directory at the root of your repository. The deploy script will go into the kubernetes directory and kubectl apply -f every file in the directory.

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

## Manifest Templates

At a base level, this is very easy to understand, but the implementation details require a little bit more explanation. Let's take a look at a sample deployment file.


```
---
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: app-$CI_ENVIRONMENT_SLUG
  namespace: $KUBE_NAMESPACE
  labels:
    app: app-$CI_ENVIRONMENT_SLUG
    pipeline_id: "$CI_PIPELINE_ID"
    build_id: "$CI_JOB_ID"
spec:
  selector:
    matchLabels:
      app: app-$CI_ENVIRONMENT_SLUG
      name: app-$CI_ENVIRONMENT_SLUG
      space: $KUBE_NAMESPACE
  template:
    metadata:
      labels:
        name: app-$CI_ENVIRONMENT_SLUG
        app: app-$CI_ENVIRONMENT_SLUG
        space: $KUBE_NAMESPACE
    spec:
      terminationGracePeriodSeconds: 60
      containers:
      - name: $KUBE_NAMESPACE-app-$CI_ENVIRONMENT_SLUG
        image: $CI_REGISTRY_IMAGE:app-$CI_COMMIT_SHA
        imagePullPolicy: IfNotPresent
        ports:
          - containerPort: 80
        env:
          - name: api_env
            valueFrom:
              secretKeyRef:
                name: $KUBE_NAMESPACE-secrets-$STAGE
                key: api_env
      imagePullSecrets:
        - name: gitlab-registry
```

You can see it looks very much like a normal kubernetes manifest file, with one big exception, variables. Rather than invent a more complex solution that covers more edge cases, our quick solution was to simply use environment variable names within our manifest files, and then use the envsubst command to substitute the values into the file at deploy time, before we apply the manifest file. While this makes the manifests harder to read and create, there are gains in flexibility and customization.

**The biggest gotcha with this is that every environment variable you use in your manifest have to exist, or templating will break.**

### $STAGE
All of the variables provided above are supplied by GitLab except for one: ```$STAGE``` - This is a special environment variable our deployer creates in order to help with review apps. If this is called from within a GitLab CI stage called review, the value will be GitLab's $CI_ENVIRONMENT_SLUG in order to create a unique name for the review app. If it's being called from any other stage, it will default to the stage name you are currently executing in GitLab ($CI_JOB_STAGE).

### Escaping $
If you have to use a $ in your manifests outside the scope of environment variable substitution, you can use ${DOLLAR} in its place:

```
  annotations:
    ingress.kubernetes.io/configuration-snippet: |
      if (${DOLLAR}denynotfromlocalbind) {
        return 403;
      }
```

This will evaluate to the following before it's applied:

```
  annotations:
    ingress.kubernetes.io/configuration-snippet: |
      if ($denynotfromlocalbind) {
        return 403;
      }
```

## Secret Management

For people just getting started with deploying apps to Kubernetes, one of the first questions is 'how do I keep secrets out of my repositories?' When we started building our deployment system, we wanted to create a system that allowed for easy out-of-repository management of secrets but didn't want to force vault on our developers quite yet, as we were trying to get more buy-in on k8s.

Instead, we opted to store our secrets in GitLab. This allowed us to:

1) Have a UI to allow developers to create secrets without them being in the repo
2) Have a basic authentication and authorization system behind who could access and edit secrets for each repository

### Secret Creation
To create a secret, go to your GitLab project and go to Settings->CI/CD->Secret Variables and create a variable with this name pattern:

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


### Per-Stage Secret Creation

Sometimes you have secrets that have different values depending on if you're running in production or staging. Our helper allows you to do this by prefixing your secret with the uppercased version of your GitLab CI stage name.

For example, let's say you have a secret called api_env, that needs to have different values depending on if you're deploying to one of three stages: review, staging or production.

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

# Deploy Events

Currently NewRelic and Slack deploy events are supported.
In Gitlab for NewRelic, you'll need to add a secret variable with the NewRelic API key and App Ids
for each stage you want a deployment event for. Like:

```
NEWRELIC_API_KEY=xxx
NEWRELIC_STAGING_APP_ID=xxx
NEWRELIC_PRODUCTION_APP_ID=xxx
```

For Slack, simply set a Gitlab secret variable with the [Slack webhook url](https://api.slack.com/incoming-webhooks).

```
SLACK_WEBHOOK=xxx
```

# Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct, and the process for submitting pull requests.

# Versioning
To make sure the community can use this project with their sanity intact, we will be committing to incrementing major versions when we introduce breaking changes.  We anticipate this happening frequently, as this tool is still under heavy development.

We use [SemVer](http://semver.org/) for versioning. For the versions available, see the [tags on this repository](https://github.com/lifechurch/k8s-deploy-helper/tags).

# License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details
