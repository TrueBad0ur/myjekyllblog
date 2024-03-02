---
title: Kubectl commands (CKAD, CKA, CKS) [eng]
published: true
tags: [ "devops", "kubernetes", "kubectl" ]
image: /assets/previews/28.jpg
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
| k create deploy NAME --image=httpd:alpine -oyaml --dry-run=client > deploy.yaml |
| k exec desploy NAME -- sh |
| k scale deploy NAME --replicas 0 |


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

Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  creationTimestamp: null
  labels:
    app: my-label
  name: my-label
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-label
  strategy: {}
  template:
    metadata:
      creationTimestamp: null
      labels:
        app: my-label
    spec:
      containers:
      - image: httpd:alpine
        name: httpd
        resources: {}
        readinessProbe:
          exec:
            command:
            - stat
            - /tmp/ready
          initialDelaySeconds: 10
          periodSeconds: 5

```

Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app: my-app
  name: my-app
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 80
    nodePort: 30090
  selector:
    app: my-app
    version: v1
  type: NodePort
```