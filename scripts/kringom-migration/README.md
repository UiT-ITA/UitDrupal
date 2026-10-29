# Kringom migration script

This script will automatically migrate the database and file directory from the
production site to a RAIL equivalent site.

NB: You will need to verify yourself two times during the script, once to
trigger the database dump and once to rsync the files from on-prem to RAIL. NB:
You will need to input two different otp.

NB: All files in the storage directory will be placed in this repository under
the directory `tmp/kringom`, make sure to delete it afterwards.

NB: Make sure you have enough space on your device to temporarily store all files.

## Requirements:

Software:
- ssh
- rsync
- kubectl
- bash compatible shell

NB: Your .kubeconfig must be set up such that you can proxy the relevant RAIL
cluster

Required .ssh/config: (Because the script assumes `ssh p1w4app` works)
```
Host p1w4app
  ProxyJump p1publogin.uib.no
  HostName p1w4app.uib.no
  IdentityFile [PATH TO YOUR IDENTITY FILE]
  User [p1w4app SSH USERNAME]

Host t1pubdocker01
  ProxyJump p1publogin.uib.no
  HostName t1pubdocker01.uib.no
  IdentityFile [PATH TO YOUR IDENTITY FILE]
  User [t1pubdocker01 SSH USERNAME]

Host p1publogin.uib.no
  IdentityFile [PATH TO YOUR IDENTITY FILE]
  User [p1publogin SSH USERNAME]
```

## Setup:

- You need to create a tunnel to the RAIL cluster by running something like `ssh
  -D 8004 -N [RAIL_LOGIN_URL]` and make sure that you are in the correct cluster
  context in your kubeconfig.

- Make sure you are located on-premises or connected to VPN to be able to reach
  the on-prem production server.