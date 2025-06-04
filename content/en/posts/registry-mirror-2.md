---
date: "2025-06-04T13:32:53+09:00"
draft: false
tags:
  - kubernetes
  - registry
  - guide
title: "Configuring clients to use a container registry mirror"
---

This is part two in a series of blogposts about container registry mirrors.
[The previous post](https://blog.froystein.jp/en/posts/registry-mirror-1/) focused on setting up a mirror in Kubernetes, now we will look at how to configure various clients to use it.

{{< notice note >}}
If you do not have your own mirror you can use https://mirror.gcr.io, which is what will be used in this guide for simplicity.
{{< /notice >}}

## Docker

```jsonc
// /etc/docker/daemon.json
{
  "registry-mirrors": ["https://mirror.gcr.io"],
}
```

### Docker Desktop

![docker desktop settings](/images/2025-06-04-13-44-18.png)

## Podman

```toml
# /etc/containers/registries.conf.d/001-mirrors.conf
[[registry]]
  location = "docker.io"

  [[registry.mirror]]
    location = "mirror.gcr.io:443"
    pull-from-mirror = "all"
```

## OpenShift

From the [OpenShift documentation:](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/images/image-configuration#images-configuration-registry-mirror_image-configuration):

- `ImageDigestMirrorSet` (IDMS). _This object allows you to pull images from a mirrored registry by using digest specifications.
  The IDMS CR enables you to set a fall back policy that allows or stops continued attempts to pull from the source registry if the image pull fails._
- `ImageTagMirrorSet` (ITMS). _This object allows you to pull images from a mirrored registry by using image tags.
  The ITMS CR enables you to set a fall back policy that allows or stops continued attempts to pull from the source registry if the image pull fails._

Examples:

```yaml
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: example
spec:
  imageDigestMirrors:
    - mirrors:
        - mirror.gcr.io
      source: docker.io
      mirrorSourcePolicy: AllowContactingSource
```

```yaml
apiVersion: config.openshift.io/v1
kind: ImageTagMirrorSet
metadata:
  name: example
spec:
  imageDigestMirrors:
    - mirrors:
        - mirror.gcr.io
      source: docker.io
      mirrorSourcePolicy: AllowContactingSource
```

The possible values for `mirrorSourcePolicy` (fallback policy if the image pull fails) are:

- `AllowContactingSource`: Allows continued attempts to pull the image from the source repository. This is the default.
- `NeverContactSource`: Prevents continued attempts to pull the image from the source repository.
