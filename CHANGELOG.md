# Version 7.1.0

Docker Image: quay.io/lifechurch/k8s-deploy-helper:7.1.0

## Feature

* Adds a deploy-flagger command for Flagger canary deployments

## Bugfixes

* Update destroy command to include configmaps and certificates

# Version 7.0.2

Docker Image: quay.io/lifechurch/k8s-deploy-helper:7.0.2

## Bugfixes

* Herokuish build process couldn't build successfully unless at least one environment variable was set.

# Version 7.0.1

Docker Image: quay.io/lifechurch/k8s-deploy-helper:7.0.1

## Updates

* Updated helm to 2.14.1

# Version 7.0.0

Docker Image: quay.io/lifechurch/k8s-deploy-helper:7.0.0

## Backwards Incompatible Changes

* Depracated use of ${DOLLAR} in manifests in favor of telling envsubst to only substitute environment variables that exist in the CI run. If you previously used ${DOLLAR}, you can just remove the {DOLLAR} portion and it should work fine.

The following command (on macOS) should do the replacement for you: ```find kubernetes -type f -name '*.yaml' | xargs -I {} sed -i '' -e "s/\${DOLLAR}/$/g" "{}"```

## Feature

* Datadog notification text is more easily searchable. You can now overlay KDH deployment events by doing a string like "KDH Deployment: $NAMESPACE production", substituting $NAMESPACE for your namespace.

# Version 6.0.3

Docker Image: quay.io/lifechurch/k8s-deploy-helper:6.0.3

## Updates

* Updated kubeval to 0.12.0

## Bugfixes

* kubeval will skip missing schemas now

# Version 6.0.0

Docker Image: quay.io/lifechurch/k8s-deploy-helper:6.0.0

## Updates

* Updated docker dind image to docker:18.06.3-ce-dind

* Updated Helm to 2.13.1

* Updated kubectl to 1.12.6

* Updated kubeval to 0.8.1

# Version 5.0.1

Docker Image: quay.io/lifechurch/k8s-deploy-helper:5.0.1

## Bug Fixes

* Fixed race condition in {{SECRETS}} substitution.

* Added additional debugging to trap bash errors.

# Version 5.0.0

Docker Image: quay.io/lifechurch/k8s-deploy-helper:5.0.0

## Feature

* DEPLOY: KDH will determine the Kubernetes version you are deploying against and run kubeval manifests specifically against that version.

* DEPLOY: You can now set KDH_SKIP_KUBEVAL variable to true in order to skip kubeval runs.

# Version 4.0.3

Docker Image: quay.io/lifechurch/k8s-deploy-helper:4.0.3

## Feature

* BUILD: Docker builds now pass the --pull flag in case you build from an image that pushes different content to the same tag.

# Version 4.0.2

Docker Image: quay.io/lifechurch/k8s-deploy-helper:4.0.2

## Bug Fixes

* Version 4.0.1 introduced a bug where deployment rollouts were not checked correctly. This is fixed.

## New Features

* New Relic deployment notifications now use the v2 API

* Deployment notifications have more contextual information about what was deployed.

# Version 4.0.1 - DO NOT USE

Docker Image: quay.io/lifechurch/k8s-deploy-helper:4.0.1

## Bug Fixes

* Canary stage was deploying manifests without ```track: stable``` label. This shouldn't happen. Fixed.

* KDH no longer tries to create the namespace if it exists already. This was causing issues because GitLab is now supposed to be creating the namespace when you add the GitLab integration.

# Version 4.0.0

Docker Image: quay.io/lifechurch/k8s-deploy-helper:4.0.0

## Backwards Incompatible Changes

* Starting in GitLab 11.5, GitLab decided to start managing service accounts for namespaces automatically. This broke k8s-deploy-helper because KUBE_TOKEN was no longer the token you specified in the cluster. Moving forward, k8s-deploy-helper is not going to generate a Kubernetes configuration itself, it will rely on GitLab to create it for us.

## New Features

* Slack Deploy Events now support separate notifications per stage, allowing you to only send deploy events on specific stages if desired, or to different Slack channels for each stage.

# Version 3.1.1

Docker Image: quay.io/lifechurch/k8s-deploy-helper:3.1.1

## Bug Fixes

* BUILDARGS_FROM now works with buildpack builds.

* BUILDARGS_FROM is less chatty.


# Version 3.1.0

Docker Image: quay.io/lifechurch/k8s-deploy-helper:3.1.0

**NOTE: Starting with this version, your GitLab runners need to run in privileged mode to allow for Heroku buildpack builds, and container scanning that will come in the next release.**

## New Features

* BUILD - If no Dockerfile is present in the root directory, we will attempt to build an image using Heroku Buildpacks via herokuish. 

* DEPLOY - If no kubernetes folder is present in the root directory, we will attempt to use our own default manifests. This has Procfile support, allowing you to run workers as well. See documentation for more details.

## Bug Fixes

* 3.0.1 introduced a template evaluation error, fixed.

* Slack and Datadog will now announce canary deploys as canary, rather than production.

# Version 3.0.1 - DO NOT USE

## Changes

* Kubeval will not evaluate ```cloud.google.com``` schemas correctly, so we skip these now. 

# Version 3.0.0

## Backwards Incompatible Changes
* kubectl - Due to a bug in kubectl, you'll need to delete the gitlab-registry secret in your namespace before you deploy. Make sure to do it right before you do a deploy to make it non-impactful. To do this, run ```kubectl delete secret gitlab-registry -n=yournamespace```.

* Deploy Token Usage - Previous versions used an actual GitLab username because GitLab didn't have persistent deploy tokens until recently. Now that this feature is in GitLab, we're going to stop using the shared credentials as this is much more secure. Create a deploy token at Settings->Repository->Deploy Tokens and make one named gitlab-deploy-token with read_registry access. As long as it's named gitlab-deploy-token, that's all you should have to do.

* Canary Usage - Delete your canary manifest templates. We will create them automatically now. Make sure track: stable is present as labels in deployments you want to go out in the canary stage.

## New Features
* DEPLOY - Canary manifests are now dynamically created in canary stages.
* DEPLOY - Automatically insert secrets as environment variables into Kubernetes manifest using {{SECRETS}} command in manifest templates. Make sure {{SECRETS}} is indented right, so it looks something like:
```
env:
  {{SECRETS}}
```
* DEPLOY - Deploy script now uses [kubeval](https://github.com/garethr/kubeval) to look for manifest errors before manifests are applied.
* DEPLOY - Deploy script now leaves a copy of the post-processed files in /tmp/kubernetes for easier debugging and artifact grabbing
* BUILD - Added BUILDARGS_FROM feature. Set BUILDARGS_FROM=production in your gitlab-ci stage, and it will make your GitLab secrets become build arguments for your Docker container. EXAMPLE: If you set BUILDARGS_FROM=production and have SECRET_VAR1 and PRODUCTION_VAR2 defined, it will automatically create build arguments named var1 and var2. *It also turns on KDH_INSERT_ARGS and will dynamically insert build arguments into your Dockerfile before build.* This is for applications that require all the environment variables to exist at buildtime as a sanity check.
* BUILD - Set KDH_INSERT_ARGS=true as a variable in your gitlab ci build stage and k8s-deploy-helper will automatically insert the ARG statements into your Dockerfile.

## Bug Fixes
* BUILD - BUILDARGS_ can now handle spaces correctly

## Changes
* Deployment events will not fire until after a deployment has been registered as rolled out successfully.

# Version 2.0.3

Docker Image: quay.io/lifechurch/k8s-deploy-helper:2.0.3

## What's New?
* Add ability to pass an variable to destroy in order to use destroy for namespaces with multiple apps

# Version 2.0.2

Docker Image: quay.io/lifechurch/k8s-deploy-helper:2.0.2

## What's New?
* Add DataDog [deployment event](https://github.com/lifechurch/k8s-deploy-helper#deploy-events) support

# Version 2.0.1

Docker Image: quay.io/lifechurch/k8s-deploy-helper:2.0.1

## What's New?
* Add KDH_SKIP_LATEST flag to skip pulling the latest docker image and using it as cache-from.

# Version 2.0.0

Docker Image: quay.io/lifechurch/k8s-deploy-helper:2.0.0

## What's New?
* Canary Deploys 

# Version 1.0.0

Docker Image: quay.io/lifechurch/k8s-deploy-helper:1.0.0

## What's New?
* Initial release
