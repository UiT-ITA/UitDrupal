## example-from-docs
This is a readme file for this application or set of resources, telling you that these files should contain:
* What this is
* Why it's here
* Any caveats or notes on the deployment

In this case:
* It's an example of an NGINX container, almost ready and defined for deployment in your `test/osl1` cluster
* It will give you an idea of how the structure of this repo works
* You need to change some thing to get started:
  * You need to change these values in <env>/<cluster>/example-from-docs/ingress-patch.yaml to a uniqe name:
    * spec.rules.host
    * spec.tls.hosts
    * spec.tls.secretName
  * You need to uncomment the resource references in <env>/<cluster>/example-from-docs/kustomization.yaml to include the base files

To deploy the application in another cluster:
1. Copy the existing <env>/<cluster>/example-from-docs to the appropriate subdirectory
2. Change the mentioned values in `ingress-path.yaml` to match the cluster
3. Push
4. Success
