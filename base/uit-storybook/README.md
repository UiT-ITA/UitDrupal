# UiT Storybook

Static Storybook of the uit_theme, built by www.uit.no (`docker/storybook`,
image `uit/www-uit-no-storybook`).

The stories are rendered server side by the drupal/storybook module. nginx in
the image serves the Storybook build and passes `/storybook/stories/render/…`
and the assets the stories use (`/core`, `/themes`, `/modules`, `/sites`,
`/libraries`) to a Drupal instance, so everything is on the same origin.

## Instances

One instance per Drupal it renders against, named `uit-storybook-<env>`
(`app_name: uit-storybook`, `app_env: <env>`), e.g. `bgo1-test/uit-storybook-dev`
with uit-web-dev as backend, https://uit-storybook-dev.bgo1.test.rail.uib.no
A later `uit-storybook-prod` would use the Storybook built from master and
uit-web-prod as backend.

## Flux substitution variables

Like `base/uit-web` (`app_name`, `app_env`, `rail_*`, `ip_whitelist`,
`image_pull_secret_name`), plus:

- `storybook_drupal_backend`: Drupal nginx that renders the stories, as
  `host:port` (plain HTTP), e.g.
  `nginx.uit-it-webadm-uit-web-dev.svc.cluster.local:8080`. It has to resolve
  when the storybook container starts, and the namespace has to allow traffic
  from the storybook namespace.

The Drupal instance needs the storybook module enabled and the permission
`render storybook stories` for anonymous users (both in www.uit.no
`config/sync`).
