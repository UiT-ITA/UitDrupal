# Image update automations

TODO: How to set up automation, look at example in profile. One ImageRepository for each container registry, one image-policy for each policy logic requires (usually per environment, e.g sandbox, test, prod).

## Listening to tags

In RAIL (/ Welkin) is using certain simple tags like latest disallowed. It is also hard for FluxCD and Kubernetes to know whether something has updated on a single image tag. This means that we are required to have some tag pattern for each deployment we do. Here are some tag patterns that we have noticed works well for different environments.

### Prod environments

Every prod deployment should be based on a tagged commit, which also means that each image should be tagged with the same tag. Optimally one would use a semver compatible tag, but you are free to do any kind of sortable logic. It must be describable with a regex for the ImagePolicy.

### Test environments

Test environments often deploy directly, in the on-prem systems, this is usually done by having a single tag and updating that. If we were to do this on Kubernetes we would need some listen script that checks the digest manifest for whether it has updated and restart the service and manually do any deployment job. A simpler solution is to tag the image with the pipeline run number and do cleanup of old images in gitlab, which allows us to re-use the same deployment pipeline as production making it simpler and more consistent.

TODO: More details?

## Why are image update automations hosted in bgo1-prod in the root namespace?

Due to safety concerns are dependencies on resources between namespaces not allowed in RAIL. To avoid having to recreate the image repository in each namespace and causing a lot of unnecessary traffic, it was decided in Teams that we should put all image update logic inside one cluster and in the root namespace. For no particular reason, bgo1-prod was chosen.