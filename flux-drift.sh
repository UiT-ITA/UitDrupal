#!/bin/bash

# Checks if anything has changed between what is deployed and what is in the Git repository
flux diff -n adm-it-pub kustomization adm-it-pub-$2 --path $1 --recursive --local-sources "GitRepository/flux-system/adm-it-pub=."
