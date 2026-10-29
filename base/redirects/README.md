# Redirects

This base contain a basic setup of Nginx behind Varnish to serve various
redirects.

Currently these domains are configured to redirect:

| Source | Destination |
|--------|-------------|
| w4.bgo1.test.rail.uib.no/.* | https://www4.uib.no/.*
| universitetsmuseet.no | https://www4.uib.no/universitetsmuseet |
| www.universitetsmuseet.no | https://www4.uib.no/universitetsmuseet |

## Adding new nginx vhost configurations

To add new nginx configurations you should palce the configuration
in a new file in the `nginx-vhosts` directory.
Then you need to update the patches in `patches/ingress.yaml` and
`patches/patch-deployment-nginx-redirect-configs.yaml` before 
updating the `kustomization.yaml` to include the new config file.