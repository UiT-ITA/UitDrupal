# Accessing clusters from local machine

It is possible to proxy the clusters to your local machine, allowing to run
kubectl, k9s, sops encryption or other other commands and utilities. This
allows for a much more flexible work environment.

## Setting up kubeconfig

1. Open your kubeconfig file (usually ~/.kube/config).
1. ssh into the cluster you want to proxy and find the kubeconfig there.
1. Add the cluster, context and user entry to your kubeconfig. After adding it
   should look something like this:

```yaml
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: [BIG STRING OF AUTH DATA]
    server: [IP OF THE SERVER, HAS PORT 6443]
  name: bgo1-test-wc
contexts:
- context:
    cluster: bgo1-test-wc
    namespace: adm-it-pub
    user: user@bgo1-test-wc
  name: bgo1-test-wc
current-context: osl1-test-wc
kind: Config
preferences: {}
users:
- name: user@bgo1-test-wc
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      args:
      - oidc-login
      - get-token
      - --oidc-issuer-url=[DEX URL]
      - --oidc-client-id=[CLIENT_ID]
      - --oidc-client-secret=[CLIENT_SECRET]
      - --oidc-extra-scope=email
      - --oidc-extra-scope=groups
      - --listen-address=127.0.0.1:22024
      command: kubectl
      env: null
      interactiveMode: IfAvailable
      provideClusterInfo: false
```

1. Then we need to add proxy-url and change the listen-address port (To avoid
   conflicts) Afterwards it should look like this:


```yaml
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: [BIG STRING OF AUTH DATA]
    # NOTE: Added proxy-url with socks5 socket connection. Port is optional,
    # but must be the same when running ssh later
    proxy-url: socks5://localhost:8002
    server: [IP OF THE SERVER, HAS PORT 6443]
  name: bgo1-test-wc
contexts:
- context:
    cluster: bgo1-test-wc
    namespace: adm-it-pub
    user: user@bgo1-test-wc
  name: bgo1-test-wc
current-context: osl1-test-wc
kind: Config
preferences: {}
users:
- name: user@bgo1-test-wc
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      args:
      - oidc-login
      - get-token
      - --oidc-issuer-url=[DEX URL]
      - --oidc-client-id=[CLIENT_ID]
      - --oidc-client-secret=[CLIENT_SECRET]
      - --oidc-extra-scope=email
      - --oidc-extra-scope=groups
      # NOTE: port change, 22024 -> 22025
      - --listen-address=127.0.0.1:22025
      command: kubectl
      env: null
      interactiveMode: IfAvailable
      provideClusterInfo: false
```

## Connecting with SSH

1. Now you just need to run `ssh -D 8002 -N {CLUSTER_URL}` to establish an open
   proxy connection to bgo1.test. You can have a connection to multiple
   clusters at once, just make sure to change the port.

**NB:** It must always run, when disconnecting or connecting to VPN, it tends
to break the ssh connection. Just rerun the command. This command must run in
order to reach the cluster from your local machine!

### Creating an ssh config host entry and an alias

Instead of manually opening an ssh connection each time, you can add an ssh
config and an alias command to run i.e kubectl against the bgo1-test api
endpoint as `kbt`.
From the examples above this would be similar to these:

```bash
# ~/.ssh/config
Host rail-bgo1-test
    User <your jumphost user>
    LocalForward 22025 localhost:22025
    Hostname login-01.bgo1.test.rail.uhdc.no
    DynamicForward 8002
    # ControlMaster settings
    #ControlMaster auto
    #ControlPath ~/.ssh/control-%C
    #ControlPersist 180m
```

```bash
# ~/.bash_aliases
alias kbt='ssh -f -N rail-bgo1-test && kubectl --context bgo1-test-wc
```

In the above the `-N` parameter tell ssh to NOT start a shell and the `-f`
parameter request ssh to go into background before command execution.
ssh then continue to run in the background.

If you want the connection to persist for a certain period of time, you can
uncomment the ControlMaster settings an tune t your needs.

**Note:** As noted above, ff you connect or disconnect to VPN or otherwise
switch networks, you likely have to tear down an existing connection.

```bash
# Find pid of the process you need to kill
ps aux | grep ssh

# kill the active process
kill -n 9 <pid>
```
