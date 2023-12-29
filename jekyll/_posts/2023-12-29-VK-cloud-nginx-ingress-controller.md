---
title: VK cloud nginx ingress controller [eng]
published: true
tags: [ "devops", "kubernetes" ]
image: /assets/previews/26.jpg
layout: page
pagination: 
  enabled: true
---

Some links at first as always:

- [Official manual](https://cloud.vk.com/docs/base/k8s/use-cases/ingress/ingress-tcp)
- [Git k8s cluster on vk cloud](https://github.com/TrueBad0ur/vkcloud_kubernetes)

Well, because I've changed my field of interests, here will be a lot of devops/cloud posts

Hope you'd like it :)

### [](#header-3)All what you need

There are many options how to set up k8s cluster:

1. locally minikube
2. locally k3s
3. in the cloud (our case)

Locally we should provide all of the controllers and network solutions by ourselves

In the cloud all of this staff has already been done by the cloud provider

Why vk cloud? Because I don't have aws accout :( and vk cloud gives 3k ru for tests :)

What we'll need:

1. terraform configs for k8s cluster
2. configs for k8s for all of our services
3. helm nginx ingress controller

### [](#header-3)Terraform

I use debian as main OS, so the man will also be targeted on it

- [Official manual](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)

```bash
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common

wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt update

sudo apt-get install terraform
```

WooHoo, we have terraform!

### [](#header-3)kubectl

- [Official manual](https://kubernetes.io/docs/tasks/tools/)

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

WooHoo, we have kubectl!

### [](#header-3)helm

- [Official manual](https://helm.sh/docs/intro/install/)

```bash
wget https://get.helm.sh/helm-v3.13.3-linux-amd64.tar.gz

tar -zxvf helm-v3.13.3-linux-amd64.tar.gz

mv helm-v3.13.3-linux-amd64/linux-amd64/helm /usr/local/bin/helm
```

### [](#header-3)Setup k8s cluster in vk cloud

We need some files for terraform in vk cloud:

- [Official manual](https://cloud.vk.com/docs/manage/tools-for-using-services/terraform/quick-start)

```bash
main.tf

data "vkcs_compute_flavor" "k8s-master-flavor" {
    name = "STD3-4-8"
}

data "vkcs_compute_flavor" "k8s-node-group-flavor" {
 name = "STD2-2-4"
}

data "vkcs_kubernetes_clustertemplate" "k8s-template" {
    version = "1.26"
}

resource "vkcs_kubernetes_cluster" "k8s-cluster" {

  depends_on = [
    vkcs_networking_router_interface.k8s,
  ]

  name                = "k8s-cluster-tf"
  cluster_template_id = data.vkcs_kubernetes_clustertemplate.k8s-template.id
  master_flavor       = data.vkcs_compute_flavor.k8s-master-flavor.id
  master_count        = 1
  network_id          = vkcs_networking_network.k8s.id
  subnet_id           = vkcs_networking_subnet.k8s.id
  availability_zone   = "GZ1"

  floating_ip_enabled = true

}

resource "vkcs_kubernetes_node_group" "k8s-node-group" {
  name = "k8s-node-group"
  cluster_id = vkcs_kubernetes_cluster.k8s-cluster.id
  flavor_id = data.vkcs_compute_flavor.k8s-node-group-flavor.id

  node_count = 2


  labels {
        key = "env"
        value = "test"
    }

  labels {
        key = "disktype"
        value = "ssd"
    }

  taints {
        key = "taintkey1"
        value = "taintvalue1"
        effect = "PreferNoSchedule"
    }

  taints {
        key = "taintkey2"
        value = "taintvalue2"
        effect = "PreferNoSchedule"
    }
}
```

```bash
network.tf

data "vkcs_networking_network" "extnet" {
  name = "ext-net"
}

resource "vkcs_networking_network" "k8s" {
  name           = "k8s-net"
  admin_state_up = true
}

resource "vkcs_networking_subnet" "k8s" {
  name            = "k8s-subnet"
  network_id      = vkcs_networking_network.k8s.id
  cidr            = "192.168.199.0/24"
  dns_nameservers = ["8.8.8.8", "8.8.4.4"]
}

resource "vkcs_networking_router" "k8s" {
  name                = "k8s-router"
  admin_state_up      = true
  external_network_id = data.vkcs_networking_network.extnet.id
}

resource "vkcs_networking_router_interface" "k8s" {
  router_id = vkcs_networking_router.k8s.id
  subnet_id = vkcs_networking_subnet.k8s.id
}
```

```bash
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply

to delete: terraform destroy
```

Wait 10-15 minutes and download kubeconfig file from vk cloud

Put it into ```~/.kube/config```

### [](#header-3)Apply k8s configs and install nginx ingress controller via helm

```bash
~ ❯ kubectl apply -f cafe.yml
```

```yaml
cafe.yml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: coffee
spec:
  replicas: 2
  selector:
    matchLabels:
      app: coffee
  template:
    metadata:
      labels:
        app: coffee
    spec:
      containers:
      - name: coffee
        image: nginxdemos/nginx-hello:plain-text
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: coffee-svc
spec:
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
    name: http
  selector:
    app: coffee
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tea
spec:
  replicas: 3
  selector:
    matchLabels:
      app: tea
  template:
    metadata:
      labels:
        app: tea
    spec:
      containers:
      - name: tea
        image: nginxdemos/nginx-hello:plain-text
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: tea-svc
  labels:
spec:
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
    name: http
  selector:
    app: tea
```

```bash
~ ❯ kubectl get svc,rs,deployment -n default
NAME                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/coffee-svc   ClusterIP   10.254.46.139   <none>        80/TCP    81m
service/kubernetes   ClusterIP   10.254.0.1      <none>        443/TCP   3h12m
service/tea-svc      ClusterIP   10.254.60.151   <none>        80/TCP    81m

NAME                                DESIRED   CURRENT   READY   AGE
replicaset.apps/coffee-77df955494   2         2         2       81m
replicaset.apps/tea-6b8fc7844       3         3         3       81m

NAME                     READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/coffee   2/2     2            2           81m
deployment.apps/tea      3/3     3            3           81m
```

### [](#header-4)helm

```bash
helm repo add nginx-stable https://helm.nginx.com/stable
helm repo update

helm install nginx-ingress-tcp nginx-stable/nginx-ingress --set-string 'controller.config.entries.use-proxy-protocol=true' --create-namespace --namespace example-nginx-ingress-tcp

~ ❯ kubectl get svc -n example-nginx-ingress-tcp
NAME                           TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)                      AGE
nginx-ingress-tcp-controller   LoadBalancer   10.254.73.94   ...              80:30203/TCP,443:31767/TCP   83m

```

### [](#header-4)continue applying kubectl configs

```bash
~ ❯ kubectl apply -f cafe-ingress.yaml
```

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: cafe-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: cafe.xn--w8je.xn--tckwe
    http:
      paths:
      - path: /tea
        pathType: Prefix
        backend:
          service:
            name: tea-svc
            port:
              number: 80
      - path: /coffee
        pathType: Prefix
        backend:
          service:
            name: coffee-svc
            port:
              number: 80
```

```bash
~ ❯ kubectl describe ingress cafe-ingress

Name:             cafe-ingress
Labels:           <none>
Namespace:        default
Address:          212.233.123.57
Ingress Class:    nginx
Default backend:  <default>
Rules:
  Host                     Path  Backends
  ----                     ----  --------
  cafe.xn--w8je.xn--tckwe  
                           /tea      tea-svc:80 (10.100.197.6:8080,10.100.197.7:8080,10.100.249.200:8080)
                           /coffee   coffee-svc:80 (10.100.197.5:8080,10.100.249.199:8080)
Annotations:               <none>
Events:                    <none>
```

After some waiting you will get external ip address and you will see:

```bash
~ ❯ kubectl get svc -n example-nginx-ingress-tcp

NAME                           TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)                      AGE
nginx-ingress-tcp-controller   LoadBalancer   10.254.73.94   212.233.123.57   80:30203/TCP,443:31767/TCP   88m
```

To check we can do:

```bash
~ ❯ curl cafe.きく.コム/tea           
Server address: 10.100.197.6:8080
Server name: tea-6b8fc7844-9mcmn
Date: 29/Dec/2023:15:50:49 +0000
URI: /tea
Request ID: 0789fe10b31c67c4da0f6ab3b2dec8a1

~ ❯ curl cafe.きく.コム/coffee
Server address: 10.100.197.5:8080
Server name: coffee-77df955494-wh987
Date: 29/Dec/2023:15:50:52 +0000
URI: /coffee
Request ID: 0f8fe754ba5833cd2de074d506080a54
```

We can see that ips are from pull that was allocated for out pods(see in ```kubectl describe ingress cafe-ingress```)