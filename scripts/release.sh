#!/usr/bin/env nix-shell
#! nix-shell -p doctl -p kubectl -i bash
doctl kubernetes cluster kubeconfig save kubermemes
dhall-to-yaml-ng < ../printerfacts.dhall | kubectl apply -n apps -f -
kubectl rollout status -n apps deployment/printerfacts
