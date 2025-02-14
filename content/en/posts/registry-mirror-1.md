---
date: "2025-02-14T10:02:35+09:00"
draft: false
tags:
  - kubernetes
  - registry
  - guide
title: "How to set up a simple registry mirror in Kubernetes"
---

For the longest time I held off on setting up a container registry mirror because I assumed I would have to set up a
potentially maintenance heavy solution like [Harbor](https://goharbor.io), [Zot](https://zotregistry.dev) or [Quay](https://quay.io), that also have way more features than I actually need in
this specific use case.

If all you need is a mirror however, it is actually really simple to set up a bare minimum low-maintenance registry
for this purpose in Kubernetes.

There are a few reasons why having a mirror is a good idea:

- Avoid rate limiting from upstream registries
- Ensure you have access to vital images behind company firewall if anything should happen to the upstream
- Faster pull speeds

In this guide we will be using the [mirror](https://docs.docker.com/docker-hub/image-library/mirror) functionality of
the official [registry](https://docs.docker.com/docker-hub/image-library/mirror) image.

## Deploying the registry to Kubernetes

Let's set up our registry step by step.

### Deployment

First of all we need a `Deployment`, here is a basic example to get started:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: registry-mirror
  labels:
    app: registry-mirror
spec:
  selector:
    matchLabels:
      app: registry-mirror
  replicas: 1
  template:
    metadata:
      labels:
        app: registry-mirror
    spec:
      containers:
        - name: registry
          image: docker.io/registry:latest # 1
          imagePullPolicy: IfNotPresent
          resources:
            requests:
              cpu: 10m
              memory: 32Mi
            limits:
              cpu: 100m
              memory: 128Mi
          ports:
            - containerPort: 5000
              name: http
          volumeMounts:
            - name: data
              mountPath: /var/lib/registry
            - name: config
              mountPath: /etc/docker/registry/config.yml
              subPath: config.yml
          securityContext: # 2
            readOnlyRootFilesystem: true
            runAsNonRoot: true
            allowPrivilegeEscalation: false
            seccompProfile:
              type: RuntimeDefault
            capabilities:
              drop:
                - ALL
      restartPolicy: Always
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: registry-data # 3
        - name: config
          configMap:
            name: registry-config # 4
```

1. Ideally use a digest to refer to a specific image here. For example, if you wanted to use [registry:2.8.3](https://hub.docker.com/layers/library/registry/2.8.3/images/sha256-57350583fba19eaab4b4632aafa1537483a390dfd29c5b37c9d59e2467ce1b8e)
   you could refer to it like this in the deployment:
   ```
    docker.io/registry@sha256:319881be2ee9e345d5837d15842a04268de6a139e23be42654fc7664fc6eaf52
   ```
2. It is good hygiene to always use sane securityContext settings.
3. A persistent volume to store registry data in.
4. ConfigMap containing the registry configuration.

Also, in a production environment you would probably want to configure this with a proper HA setup
with multiple replicas, probes, anti-affinity and a pod disruption budget.\
I have written a blog post on how to do this [here](https://engineering.intility.com/article/guide-to-high-availability-in-kubernetes)

### Service

Nothing fancy, just a standard `Service` to expose our registry on the cluster network.

If your mirror is purely used inside the same cluster you could use the service hostname to access it
(in this case `registry-mirror.<namespace>.svc.cluster.local`),
but if not you will need an ingress of some sort to expose it (more on this later).

```yaml
apiVersion: v1
kind: Service
metadata:
  name: registry-mirror
spec:
  selector:
    app: registry-mirror
  type: ClusterIP
  ports:
    - name: registry-mirror
      protocol: TCP
      port: 5000
      targetPort: http
```

### ConfigMap

To feed the registry with the configuration to make it a mirror, we use a `ConfigMap`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: registry-config
data:
  config.yml: |
    # registry default config
    version: 0.1
    log:
      fields:
        service: registry
    storage:
      cache:
        blobdescriptor: inmemory
      filesystem:
        rootdirectory: /var/lib/registry
    http:
      addr: :5000
      headers:
        X-Content-Type-Options: [nosniff]
    health:
      storagedriver:
        enabled: true
        interval: 10s
        threshold: 3

    # mirror config
    proxy:
      remoteurl: https://registry-1.docker.io
```

If you want to tweak this (for example if you want to store data in an s3 bucket or set up authentication)
you can find the full documentation with all configuration options [here](https://distribution.github.io/distribution/about/configuration).

### PersistentVolumeClaim

If you want to persist the cache that is gradually built up by the registry,
you can use a volume and mount it to `/var/lib/registry`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: registry-data
  labels:
    app: registry-data
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
```

If you are using more than one replica you will need to use ReadWriteMany (RWX) as the access mode.

As mentioned briefly above it is also possible to store this data in an s3 bucket or similar.

### Ingress / Route

How you handle ingress traffic in your cluster depends a lot on your environment,
but here is a basic example on how to use an `Ingress`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: registry-ingress
spec:
  rules:
    - host: mirror.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: registry-mirror
                port:
                  number: 5000
```

## Wrapping up

That is all it takes to set up a simple registry mirror that requires minimum effort
to maintain,

There are some other cool registry mirroring solutions out there like [spegel](https://github.com/spegel-org/spegel),
but it unfortunately currently only supports containerd as the container runtime
and [does not work with OpenShift/cri-o](https://github.com/spegel-org/spegel/issues/36) which is what I usually work with.

In the next part we will be looking at how to configure nodes in a cluster to use a
mirror when pulling images.
