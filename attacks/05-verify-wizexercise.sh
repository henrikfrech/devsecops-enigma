#!/usr/bin/env bash
kubectl exec -it $(kubectl get pod -l app=wiz-app -o jsonpath='{.items[0].metadata.name}') \
  -- cat /app/wizexercise.txt
