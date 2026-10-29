# Combined VCL: Drupal cache policy + Varnish cluster self-routing
#
# Based on:
#   - zeroconfig.vcl from the varnish_purge contrib module for Drupal
#     (Drupal 8+ cache tag support)
#   - Varnish StatefulSet self-routing for Kubernetes
#
# Supports the following PURGE and BAN requests:
#
#  - PURGE: single URL purge
#    $ curl 'http://VARNISH/path' -X PURGE
#
#  - BAN with pipe-separated Cache-Tags header (Drupal varnish_purge module):
#    $ curl 'http://VARNISH/' -X BAN -H 'Cache-Tags: node_list'
#    $ curl 'http://VARNISH/' -X BAN -H 'Cache-Tags: media:3918 media_list'
#
#  - BAN with wildcard URL:
#    $ curl 'http://VARNISH/.*projects.*' -X BAN
#
#  - URIBAN for image purge (requires varnish_image_purge module)
#
# PURGE/BAN/URIBAN auth: allowed from the purge ACL (localhost + 10.0.0.0/8)
# for unproxied requests (X-Forwarded-For is only client.ip), or from
# anywhere with an X-Ban-Token header matching the non-empty
# $VARNISH_BAN_TOKEN env var.

vcl 4.1;

import std;
import directors;

# =============================================================================
#   ORIGIN BACKEND — Drupal / nginx
# =============================================================================

backend drupal {
    .host = "${uibstart_nginx_service}";
    .port = "80";
    .max_connections = 300;
    .first_byte_timeout     = 300s;
    .connect_timeout        = 30s;
    .between_bytes_timeout  = 30s;
}

# =============================================================================
#   PURGE / BAN ACL
# =============================================================================

acl purge {
    "127.0.0.1";
    "::1";
    "10.0.0.0"/8;
}

# =============================================================================
#   DIRECTORS — initialised in vcl_init
# =============================================================================

sub vcl_init {
    # Round-robin director for origin (Drupal/nginx)
    new drupal_hosts = directors.round_robin();
    drupal_hosts.add_backend(drupal);
}

# =============================================================================
#   INCOMING REQUESTS
# =============================================================================

sub vcl_recv {

    # Cache invalidation (PURGE, BAN, URIBAN) is allowed from the purge ACL only
    # when the request was not proxied, or from anywhere with a valid
    # X-Ban-Token. Varnish appends client.ip to X-Forwarded-For before
    # vcl_recv, so any other value means a proxy hop (ingress-nginx pods are
    # inside 10.0.0.0/8). An empty or unset VARNISH_BAN_TOKEN never matches.
    if (req.method == "PURGE" || req.method == "BAN" || req.method == "URIBAN") {
        if (!((client.ip ~ purge && req.http.X-Forwarded-For == "" + client.ip) ||
              (std.getenv("VARNISH_BAN_TOKEN") != "" &&
               req.http.X-Ban-Token == std.getenv("VARNISH_BAN_TOKEN")))) {
            return (synth(405, "Not allowed."));
        }
    }

    # URIBAN: image purge support (varnish_image_purge module)
    if (req.method == "URIBAN") {
        ban("req.http.host == " + req.http.host + " && req.url == " + req.url);
        return (synth(200, "Ban added."));
    }

    # BAN: cache-tag invalidation (varnish_purge module) or wildcard URL ban.
    if (req.method == "BAN") {
        if (req.http.Cache-Tags) {
            ban("obj.http.Cache-Tags ~ " + req.http.Cache-Tags);
        } else {
            ban("req.url ~ " + req.url);
        }
        return (synth(200, "Ban added."));
    }

    # PURGE: single URL purge.
    if (req.method == "PURGE") {
        return (purge);
    }

    # Respond to local health probe requests immediately — no Drupal dependency.
    if (req.url == "/varnish-probe" && client.ip ~ purge) {
        return (synth(200, "OK"));
    }

    # Non-idempotent requests must bypass cluster self-routing.
    # Auth flows like openid_connect POST /user/login depend on the origin
    # handling the request directly instead of being sharded to a peer first.
    if (req.method != "GET" && req.method != "HEAD") {
        set req.backend_hint = drupal_hosts.backend();
        return (pass);
    }

    # Session-sensitive Drupal flows should stay on the first Varnish instance
    # and go straight to origin instead of peer-hopping.
    if (req.url ~ "^/user/reset/" ||
        req.http.Cookie ~ "(^|;\s*)(S?SESS[a-zA-Z0-9]+|NO_CACHE)=") {
        set req.backend_hint = drupal_hosts.backend();
        return (pass);
    }

    # Single-replica setup: route all cacheable traffic directly to origin.
    set req.backend_hint = drupal_hosts.backend();

    # Don't cache healthchecks.
    if (req.url ~ "healthcheck") {
        return (pipe);
    }

    # While origin is considered healthy, allow short stale serving during refreshes.
    set req.grace = 10m;

    # Pipe large-file requests flagged in a previous pass.
    if (req.http.x-pipe && req.restarts > 0) {
        return (pipe);
    }

    # Pipe executables and archives to avoid buffering large objects.
    if (req.url ~ "\.(msi|exe|dmg|zip|tgz|gz)") {
        return (pipe);
    }

    # Cache static assets for all users (except private file system).
    # Matches /(modules|themes|files)/ and any /assets/ path (e.g. Drupal's aggregated JS/CSS).
    # Query string pattern allows arbitrary key=value pairs (e.g. Drupal JS aggregation params).
    if (req.url ~ "(?i)/(modules|themes|files|assets)/.*\.(png|gif|jpeg|jpg|ico|swf|css|js|flv|f4v|mov|mp3|mp4|pdf|doc|ttf|eot|svg|woff|eof|ppt)(\?[^#]*)?$" && req.url !~ "/system/files") {
        unset req.http.Cookie;
        set req.http.X-static-asset = "True";
    }

    # Don't cache cron.php.
    if (req.url ~ "^/cron.php") {
        return (pass);
    }

    # Pass HTTP auth'd requests through.
    if (req.http.Authorization) {
        return (pass);
    }

    # Strip cookies Drupal doesn't need. Any remaining cookie bypasses cache.
    if (req.http.Cookie) {
        set req.http.Cookie = ";" + req.http.Cookie;
        set req.http.Cookie = regsuball(req.http.Cookie, "; +", ";");
        set req.http.Cookie = regsuball(req.http.Cookie, ";(S?SESS[a-z0-9]+|NO_CACHE)=", "; \1=");
        set req.http.Cookie = regsuball(req.http.Cookie, ";[^ ][^;]*", "");
        set req.http.Cookie = regsuball(req.http.Cookie, "^[; ]+|[; ]+$", "");

        if (req.http.Cookie == "") {
            unset req.http.Cookie;
        } else {
            return (pass);
        }
    }

    # Set X-Forwarded-For so the backend knows the true client IP.
    if (req.http.x-forwarded-for) {
        set req.http.X-Forwarded-For = req.http.X-Forwarded-For;
    } else {
        set req.http.X-Forwarded-For = client.ip;
    }

    return (hash);
}

# Hashing rules — include host for multi-tenant setups.
sub vcl_hash {
    hash_data(req.url);
    if (req.http.host) {
        hash_data(req.http.host);
    }
}

# HIT handling for expired objects.
#
# Serve stale from grace when available to avoid transient 5xx exposure.
sub vcl_hit {
    if (obj.ttl >= 0s) {
        return (deliver);
    }

    if (obj.ttl + obj.grace > 0s) {
        return (deliver);
    }

    return (miss);
}

# Piped requests should not support keepalive.
sub vcl_pipe {
    set req.http.connection = "close";
}

# =============================================================================
#   BACKEND FETCH — called just before the backend request is sent
# =============================================================================

sub vcl_backend_fetch {
    # No-op for single replica.
}

# =============================================================================
#   BACKEND RESPONSE — Drupal caching policy
# =============================================================================

sub vcl_backend_response {

    # Preserve which Varnish pod ultimately talked to Drupal.
    if (!beresp.http.X-Varnish-Backend-Pod) {
        set beresp.http.X-Varnish-Backend-Pod = server.identity;
    }

    if (!beresp.http.X-Varnish-Entry-Pod) {
        if (bereq.http.X-Cluster-Entry-Pod) {
            set beresp.http.X-Varnish-Entry-Pod = bereq.http.X-Cluster-Entry-Pod;
        } else {
            set beresp.http.X-Varnish-Entry-Pod = server.identity;
        }
    }

    # BigPipe streaming support.
    if (beresp.http.Surrogate-Control ~ "BigPipe/1.0") {
        set beresp.do_stream = true;
        set beresp.ttl = 0s;
    }

    # Ban-lurker friendly headers for cache invalidation.
    set beresp.http.X-Url = bereq.url;
    set beresp.http.X-Host = bereq.http.host;

    # Allow objects to remain in grace up to 6h past expiry.
    set beresp.grace = 6h;

    # Remove Set-Cookie from static assets.
    if (bereq.http.X-static-asset) {
        unset beresp.http.Set-Cookie;
    }

    # Don't cache responses with status ≥ 302, zero/negative TTL, or non-GET.
    if (beresp.status >= 302 || !(beresp.ttl > 0s) || bereq.method != "GET") {
        call varnish_pass;
    }

    # Cache 301 redirects for at least 15 minutes.
    if (beresp.status == 301) {
        if (beresp.ttl < 15m) {
            set beresp.ttl = 15m;
        }
    }

    # Don't cache cron.php.
    if (bereq.url ~ "^/cron.php") {
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
        return (deliver);
    }

    # Don't cache if a Drupal session cookie is set.
    if (beresp.http.Set-Cookie ~ "(^|;\s*)(S?SESS[a-zA-Z0-9]*)=") {
        call varnish_pass;
    }

    # Keep stale metadata around for conditional revalidation after grace.
    set beresp.keep = 1h;

    # Set a shorter Cache-Control for browsers than Drupal's default.
    if (beresp.ttl > 0s) {
        unset beresp.http.expires;
        #set beresp.http.Cache-Control = "public, max-age=300";
        set beresp.http.magicmarker = "1";
    }

    # Stream objects ≥ 10 MB without buffering or caching.
    if (beresp.http.Content-Length &&
        std.integer(beresp.http.Content-Length, 0) >= 10000000) {
        set beresp.ttl = 0s;
        set beresp.uncacheable = true;
        set beresp.do_stream = true;
        set beresp.do_gzip = false;
        set beresp.do_esi = false;
    }

    return (deliver);
}

# =============================================================================
#   DELIVERY — Response to client
# =============================================================================

sub vcl_deliver {

    set resp.http.X-Varnish-Served-By = server.identity;

    if (!resp.http.X-Varnish-Entry-Pod) {
        if (req.http.X-Cluster-Entry-Pod) {
            set resp.http.X-Varnish-Entry-Pod = req.http.X-Cluster-Entry-Pod;
        } else {
            set resp.http.X-Varnish-Entry-Pod = server.identity;
        }
    }

    if (!resp.http.X-Varnish-Backend-Pod) {
        set resp.http.X-Varnish-Backend-Pod = server.identity;
    }

    if (resp.http.X-Varnish-Backend-Pod == server.identity) {
        set resp.http.X-Varnish-Route = "direct";
    } else {
        set resp.http.X-Varnish-Route = "via " + resp.http.X-Varnish-Backend-Pod;
    }

    # Keep Drupal/nginx Cache-Control as-is for clients, except remove
    # shared-cache directives not meant for browsers:
    # s-maxage, stale-if-error, stale-while-revalidate.
    if (resp.http.Cache-Control) {
        # Prefer Cache-Control as the source of truth when it exists.
        unset resp.http.Expires;

        # Remove shared-cache TTL directive from client-facing header.
        # First remove comma-prefixed entries, then start-of-header entries.
        set resp.http.Cache-Control = regsuball(
            resp.http.Cache-Control,
            "(?i),[[:space:]]*s-maxage(=[^,]*)?",
            ""
        );
        set resp.http.Cache-Control = regsuball(
            resp.http.Cache-Control,
            "(?i)^[[:space:]]*s-maxage(=[^,]*)?[[:space:]]*,?",
            ""
        );

        # Remove stale-on-error directive from client-facing header.
        set resp.http.Cache-Control = regsuball(
            resp.http.Cache-Control,
            "(?i),[[:space:]]*stale-if-error(=[^,]*)?",
            ""
        );
        set resp.http.Cache-Control = regsuball(
            resp.http.Cache-Control,
            "(?i)^[[:space:]]*stale-if-error(=[^,]*)?[[:space:]]*,?",
            ""
        );

        # Remove stale-while-revalidate directive from client-facing header.
        set resp.http.Cache-Control = regsuball(
            resp.http.Cache-Control,
            "(?i),[[:space:]]*stale-while-revalidate(=[^,]*)?",
            ""
        );
        set resp.http.Cache-Control = regsuball(
            resp.http.Cache-Control,
            "(?i)^[[:space:]]*stale-while-revalidate(=[^,]*)?[[:space:]]*,?",
            ""
        );

        # Normalize separators after removals (e.g. avoid ", ," and trim edges).
        set resp.http.Cache-Control = regsuball(resp.http.Cache-Control, "[[:space:]]*,[[:space:]]*,", ",");
        set resp.http.Cache-Control = regsuball(resp.http.Cache-Control, "[[:space:]]*,[[:space:]]*", ", ");
        set resp.http.Cache-Control = regsub(resp.http.Cache-Control, "^[[:space:]]*,[[:space:]]*|[[:space:]]*,[[:space:]]*$", "");

        # Drop the header entirely if nothing remains.
        if (resp.http.Cache-Control ~ "^[[:space:]]*$") {
            unset resp.http.Cache-Control;
        }
    }

    if (resp.http.magicmarker) {
        unset resp.http.magicmarker;
        set resp.http.age = "0";
    }

    # Remove ban-lurker headers before sending to client.
    unset resp.http.X-Url;
    unset resp.http.X-Host;
    # Hide origin software/version fingerprinting.
    unset resp.http.X-Generator;
    # Hide cache diagnostics from upstream Drupal and Varnish.
    unset resp.http.X-Drupal-Dynamic-Cache;
    # Comment these out for easier cache-tag debugging in development:
    unset resp.http.Cache-Tags;
    unset resp.http.X-Drupal-Cache-Tags;
    unset resp.http.X-Drupal-Cache-Contexts;

    # Set cache diagnostics first; they are stripped below for normal client traffic.
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
        set resp.http.X-Cache-Hits = obj.hits;
        unset resp.http.Set-Cookie;
    } else {
        set resp.http.X-Cache = "MISS";
    }

    # Strip Age header for Akamai requests.
    if (req.http.Via ~ "akamai") {
        set resp.http.X-Age = resp.http.Age;
        unset resp.http.Age;
    }

    # Remove Set-Cookie from static assets.
    if (req.http.X-static-asset) {
        unset resp.http.Set-Cookie;
    }

    # ELB health checker keep-alive fix.
    if (req.http.user-agent ~ "ELB-HealthChecker") {
        set resp.http.Connection = "close";
    }

    # Hide internal routing debug headers from clients.
    unset resp.http.X-Varnish-Served-By;
    unset resp.http.X-Varnish-Entry-Pod;
    unset resp.http.X-Varnish-Backend-Pod;
    unset resp.http.X-Varnish-Route;
    unset resp.http.X-Varnish;
    unset resp.http.X-Cache;
    unset resp.http.X-Cache-Hits;
    unset resp.http.Via;

    return (deliver);
}

# =============================================================================
#   ERROR HANDLING
# =============================================================================

sub vcl_backend_error {
    return (fail("Service unavailable"));
}

sub vcl_synth {
    # For successful synthetic responses (BAN/PURGE/probe), return a short
    # plain-text body instead of the generic error HTML page.
    if (resp.status >= 200 && resp.status < 300) {
        set resp.http.Content-Type = "text/plain; charset=utf-8";
        synthetic(resp.reason);
        return (deliver);
    }

    set resp.http.Content-Type = "text/html; charset=utf-8";
    set resp.http.Retry-After = "5";

    synthetic( {"<!DOCTYPE html>
<!--[if lt IE 7]>      <html class="no-js lt-ie9 lt-ie8 lt-ie7"> <![endif]-->
<!--[if IE 7]>         <html class="no-js lt-ie9 lt-ie8"> <![endif]-->
<!--[if IE 8]>         <html class="no-js lt-ie9"> <![endif]-->
<!--[if gt IE 8]><!--> <html class="no-js"> <!--<![endif]-->
<head>
    <link rel="shortcut icon" href="/UiBerror/img/favicon.ico" type="image/x-icon">
    <meta charset="utf-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <title>ERROR 50x: Siden kan ikke vises</title>
    <meta name="description" content="">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="https://www.uib.no/UiBerror/css/normalize.css">
    <link rel="stylesheet" href="https://shared.app.uib.no/css/uib/2024/uib_header.css">
    <link rel="stylesheet" href="https://shared.app.uib.no/css/uib/2024/uib_header_small_screen_override.css">
    <link rel="stylesheet" href="https://shared.app.uib.no/css/uib/2024/uib_footer.css">
    <style>
        /* Show only Norwegian */
        .lang_en {
            display: none;
        }
        /* Add new palette */
        .uib_palette_EW_error_page
         { /*Template: https://www.figma.com/design/aVaL0OhtXPnqU77Eq7BtzB/Error-pages?node-id=128-964 */
            --uib-header-background-color: #fef9f1;
            --uib-header-font-color: black;
            --uib-header-link-color: black;
            --uib-main-background-color: #fef9f1;
            --uib-main-font-color: #1D0606;
            --uib-main-link-color: #1D0606;
            --uib-footer-background-color: #1d0606;
            --uib-footer-font-color: #fef9f1;
            --uib-footer-link-color: #fef9f1;
        }
        /* Change logo color */
        .uib_palette_EW_error_page a img {
            filter: invert(100%);
        }
        footer a {  }

        /* EW 404 page 2024 version */
        .page__wrapper {
            min-height: 100vh;
        }
        main {
            display: flex;
            width: 100%;
        }
        .center {
            flex-grow: 1;
            min-width: 0;
            min-height: 0;
        }
        .right .decoreBox {
            padding: 20px;
            border: dashed 1px silver;
            margin-left: 1em;
            margin-top: 1em;
        }
        .right {
            padding-right: 2em;
        }
        .right .decoreBox h3 {
            margin-top: 0;
        }
        footer {
            margin-top: auto;
        }
        footer .footer_main {
            text-align: center;
            margin-top: 1em;
            margin-bottom: 1em;
            padding-top: 2em;
            padding-bottom: 2em;
        }
        @media (max-width: 720px) {
            /* Remove menu is not space. */
            nav {
                display: none;
            }
            main {
                flex-direction: column;
            }
            .center {
                flex-grow: 0;
            }
            .right .decoreBox {
                margin-left: 0;
                margin-right: 0;
                margin-bottom: 1em;
            }
        }
    </style>
    <script>
        function showNorwegian() {
            document.getElementById('mainTitle').innerText='Universitetet i Bergen';
            const element_en = document.getElementsByClassName('lang_en');
            const element_no = document.getElementsByClassName('lang_no');
            for (let i = 0 ; element_en.item(i) ; i++ ) {
                element_en.item(i).style.display="none";
            }
            for (let i = 0 ; element_no.item(i) ; i++ ) {
                element_no.item(i).style.display="block";
            }
        }
        function showEnglish() {
            document.getElementById('mainTitle').innerText='University of Bergen';
            const element_en = document.getElementsByClassName('lang_en');
            const element_no = document.getElementsByClassName('lang_no');
            for (let i = 0 ; element_no.item(i) ; i++ ) {
                element_no.item(i).style.display="none";
            }
            for (let i = 0 ; element_en.item(i) ; i++ ) {
                element_en.item(i).style.display="block";
            }
        }
    </script>
</head>
<body class="uib_palette_0">
<div class="page__wrapper"><!-- This div (page-wrapper) is in order to place the footer on the bottom -->
    <div class="header__wrapper">
        <header class="header">
            <a href="https://www.uib.no/">
                <img src="https://shared.app.uib.no/img/2024/UiB-emblem_white_no_padding.svg" alt="uib.no">
            </a>
            <hgroup>
                <h1 id="mainTitle">Universitetet i Bergen</h1>
            </hgroup>
            <div class="header_foot"></div>
        </header>
    </div>
    <main class="body">
        <div class="left">
            <div class="lang_en">
                <h2>We aploogize!</h2>
                <p>
                    This site is currently experiencing some technical issues. We are working to resolve the issues as soon as possible.
                </p>
                <div id="to_norwegian">
                    <a href="#" onmouseup="showNorwegian();">Norsk versjon</a>
                </div>
                <div id="contact"><h3>Contact us</h3>
                    <p>Telephone: 55 58 00 00 <br/>
                        E-mail: post@uib.no</p>
                </div>
            </div>
            <div class="lang_no">
                <h2>Vi beklager!</h2>
                <p>
                    Denne siden har tekniske problemer. Vi jobber med å løse dem så raskt som mulig.
                </p>
                <div id="to_english">
                    <a href="#" onmouseup="showEnglish();">English version</a>
                </div>
                <div id="contact"><h3>Kontakt</h3>
                    <p>Telefon: 55 58 00 00 <br/>
                    E-post: post@uib.no
                    </p>
                </div>
            </div>
        </div>
        <div class="center"></div>
        <div class="right">
            <div class="decoreBox">
                <div class="lang_no">
                    <h3>Andre nettbaserte tjenester fra UiB:</h3>
                    <ul class="links">
                        <li><a href="https://uibstart.no">På Høyden (Intern kanal for ansatte og studenter)</a></li>
                        <li><a href="https://mitt.uib.no">Mitt UiB (Læringsplattform)</a></li>
                        <li><a href="https://treet.uib.no/">UiBtreet (Dashbord for studenter)</a></li>
                        <li><a href="https://timer.uib.no">Selvbetjeningsportalen (For ansatte)</a></li>
                        <li><a href="https://hjelp.uib.no">UiBhjelp (Administrative tjenester for ansatte og studenter)</a></li>
                    </ul>
                </div>
                <div class="lang_en">
                    <h3>Other online services from UiB</h3>
                    <ul class="links">
                        <li><a href="https://uibstart.no">På Høyden (Internal channel for employees and students)</a></li>
                        <li><a href="https://mitt.uib.no">Mitt UiB (Learning platform)</a></li>
                        <li><a href="https://treet.uib.no/">UiBtreet (Dashbord for students)</a></li>
                        <li><a href="https://timer.uib.no">Self-service portal (For employees)</a></li>
                        <li><a href="https://hjelp.uib.no">UiBhjelp (Service management portal for employees and students)</a></li>
                    </ul>
                </div>
            </div>
        </div>
    </main>
</div>
</body>
</html>
"});

    return (deliver);
}

sub varnish_pass {
    set beresp.uncacheable = true;
    return (deliver);
}
