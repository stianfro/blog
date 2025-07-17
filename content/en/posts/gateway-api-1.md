---
date: "2025-07-01T15:41:19+02:00"
draft: false
tags:
  - kubernetes
  - network
title: "Gateway API for dummies"
---

I recently had a use-case where I could finally tinker with Gateway API, a new interface for handling service traffic in Kubernetes. You can think of it as a successor to the current Ingress APIs.
Gateway API is built and maintained by the Kubernetse Network Special Interest Group.

| Ingress           | Gateway                       |
| ----------------- | ----------------------------- |
| IngressClass      | GatewayClass                  |
| IngressController | Gateway                       |
| Ingress           | HTTPRoute, TLSRoute, TCPRoute |

Lets take a look at a simple example with HTTPRoute.

{{< notice note >}}
If you want to test Envoy Gateway locally, I recommend you look at their [quickstart](https://gateway.envoyproxy.io/docs/tasks/quickstart) instead of using my examples as they have been simplified quite a bit.
{{</notice>}}

Instead of annotating an ingress with settings on how it should handle various types of traffic, you can use resources like BackendTrafficPolicy and (in the case of Envoy) BackendTLSTraffic.
You can refer to these from an individual HTTPRoute or for the whole Gateway.

You can add one or more _listeners_ to a Gateway resource,

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
spec:
  listeners:
    - name: http
      allowedRoutes:
        namespaces:
          from: All
      hostname: "*.example.com"
      port: 80
      protocol: HTTP
```

What is important to be aware of is that Gateway API is just an API, it is just a set of CRDs that you install in your cluster and does not come with a controller of any kind. A separate Gateway Controller has to be installed for things to work, there are [many implementations to choose from] but some examples include Envoy Gateway, Traefik Proxy, Cilium and Istio.

compare ingress / ingresscontroller (openshift) with gateway api

praise statuses
When using Gateway API you can really tell that is a modern Kubernetes API with a lot of thought put into it. This is especially true when it comes to the status and conditions for all the resources.
Just by looking at the status of a resource you can quickly tell if everything is working or if there is something wrong with the configuration and _why_.
Many Kubernetes APIs are unfortunately not great at this, so it is very refreshing to see it done well and it is a joy to work with.

httproute

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: backend
  namespace: marketing
spec:
  hostnames:
    - www.marketing.example.com
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: internal
      namespace: gateway-a
  rules:
    - backendRefs:
        - group: ""
          kind: Service
          name: backend
          port: 3000
          weight: 1
      matches:
        - path:
            type: PathPrefix
            value: /
```

httproute status

```yaml
status:
  parents:
    - conditions:
        - message: Route is accepted
          reason: Accepted
          status: "True"
          type: Accepted
      controllerName: gateway.envoyproxy.io/a-gatewayclass-controller
      parentRef:
        group: gateway.networking.k8s.io
        kind: Gateway
        name: internal
        namespace: gateway-a
```

gateway

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: internal
  namespace: gateway-a
spec:
  gatewayClassName: a-gatewayclass
  listeners:
    - allowedRoutes:
        namespaces:
          from: All
      hostname: "*.marketing.example.com"
      name: http
      port: 8080
      protocol: HTTP
```

status

```yaml
status:
  addresses:
    - type: IPAddress
      value: 172.18.0.3
  conditions:
    - message: The Gateway has been scheduled by Envoy Gateway
      reason: Accepted
      status: "True"
      type: Accepted
    - message: Address assigned to the Gateway, 1/1 envoy replicas available
      reason: Programmed
      status: "True"
      type: Programmed
  listeners:
    - attachedRoutes: 1
      conditions:
        - message: Sending translated listener configuration to the data plane
          reason: Programmed
          status: "True"
          type: Programmed
        - message: Listener has been successfully translated
          reason: Accepted
          status: "True"
          type: Accepted
      name: http
      supportedKinds:
        - group: gateway.networking.k8s.io
          kind: HTTPRoute
```

It is also very noticable when working with all the different resources. Every field of every CRD is extremely well documented and has great validation as well,

Just take a look at the documentation for the [`.spec.hostnames`](https://github.com/kubernetes-sigs/gateway-api/blob/bc08c0ff375ad76fdda7089121c6e1e06662c137/apis/v1/httproute_types.go#L55-L125) field in the HTTPRoute resource as an example:

```go
// HTTPRouteSpec defines the desired state of HTTPRoute
type HTTPRouteSpec struct {
	// Hostnames defines a set of hostnames that should match against the HTTP Host
	// header to select a HTTPRoute used to process the request. Implementations
	// MUST ignore any port value specified in the HTTP Host header while
	// performing a match and (absent of any applicable header modification
	// configuration) MUST forward this header unmodified to the backend.
	//
	// Valid values for Hostnames are determined by RFC 1123 definition of a
	// hostname with 2 notable exceptions:
	//
	// 1. IPs are not allowed.
	// 2. A hostname may be prefixed with a wildcard label (`*.`). The wildcard
	//    label must appear by itself as the first label.
	//
	// If a hostname is specified by both the Listener and HTTPRoute, there
	// must be at least one intersecting hostname for the HTTPRoute to be
	// attached to the Listener. For example:
	//
	// * A Listener with `test.example.com` as the hostname matches HTTPRoutes
	//   that have either not specified any hostnames, or have specified at
	//   least one of `test.example.com` or `*.example.com`.
	// * A Listener with `*.example.com` as the hostname matches HTTPRoutes
	//   that have either not specified any hostnames or have specified at least
	//   one hostname that matches the Listener hostname. For example,
	//   `*.example.com`, `test.example.com`, and `foo.test.example.com` would
	//   all match. On the other hand, `example.com` and `test.example.net` would
	//   not match.
	//
	// Hostnames that are prefixed with a wildcard label (`*.`) are interpreted
	// as a suffix match. That means that a match for `*.example.com` would match
	// both `test.example.com`, and `foo.test.example.com`, but not `example.com`.
	//
	// If both the Listener and HTTPRoute have specified hostnames, any
	// HTTPRoute hostnames that do not match the Listener hostname MUST be
	// ignored. For example, if a Listener specified `*.example.com`, and the
	// HTTPRoute specified `test.example.com` and `test.example.net`,
	// `test.example.net` must not be considered for a match.
	//
	// If both the Listener and HTTPRoute have specified hostnames, and none
	// match with the criteria above, then the HTTPRoute is not accepted. The
	// implementation must raise an 'Accepted' Condition with a status of
	// `False` in the corresponding RouteParentStatus.
	//
	// In the event that multiple HTTPRoutes specify intersecting hostnames (e.g.
	// overlapping wildcard matching and exact matching hostnames), precedence must
	// be given to rules from the HTTPRoute with the largest number of:
	//
	// * Characters in a matching non-wildcard hostname.
	// * Characters in a matching hostname.
	//
	// If ties exist across multiple Routes, the matching precedence rules for
	// HTTPRouteMatches takes over.
	//
	// Support: Core
	//
	// +optional
	// +kubebuilder:validation:MaxItems=16
	Hostnames []Hostname `json:"hostnames,omitempty"`
}
```

_note: slightly modified for brevity_

envoy gateway

metallb

backendtrafficpolicy

tracing
no luck with tlsroute for some reason.

deployment modes, multi-tenancy (part 2?)

![gateway-api illustration](/images/2025-07-16-12-35-56.png)

In my case this diagram will most of the time look like this:
_TODO: stian in the diagram_

ns / ew

In the next post I will go through how to set up Envoy Gateway for multi-tenancy.

Useful links:

- Gateway API
  - [Introduction](https://gateway-api.sigs.k8s.io/)
  - [Getting Started](https://gateway-api.sigs.k8s.io/guides)
  - [Glossary](https://gateway-api.sigs.k8s.io/concepts/glossary)
  - [API Reference](https://gateway-api.sigs.k8s.io/reference/spec)
