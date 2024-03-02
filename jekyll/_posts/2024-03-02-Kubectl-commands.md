---
title: Kubectl commands (CKAD, CKA, CKS) [eng]
published: true
tags: [ "devops" "kubernetes" "kubectl" ]
image: assets/previews/28.jpg
layout: page
pagination: 
  enabled: true
---

Interactive notes/commands for kubectl, which may help for certifications:

| Command |
|:-------------|
| k -n NAMESPACE run NAME --image=httpd:alpine --dry-run=client -oyaml > pod.ya |
| k replace --force -f ./pod.yaml |
| k create configmap NAME --from-literal key=value --dry-run=client -oyaml > cm.yml |


Templates:

Pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: my-pod
  name: my-pod
  namespace: my-namespace
spec:
  containers:
  - image: httpd:alpine
    resources:
      requests:
        memory: "30Mi"
        cpu: "30m"
      limits:
        memory: "30Mi"
        cpu: "300m"
    name: httpd-container
  restartPolicy: Always
```