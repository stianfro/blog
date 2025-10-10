---
date: "2025-10-10T00:00:00+02:00"
draft: false
tags:
  - kubernetes
  - network
  - Gateway API
title: "Gateway API for dummies"
---

I recently had a use-case where I could finally tinker with Gateway API, a new interface for handling service traffic in Kubernetes. You can think of it as a successor to the current Ingress APIs.
Gateway API is built and maintained by the Kubernetes Network Special Interest Group.

## What is Gateway API?

Gateway API is essentially just an API, it is a set of CRDs that you install in your cluster and does not come with a controller of any kind. A separate Gateway Controller has to be installed for things to work, there are [many implementations to choose from](https://gateway-api.sigs.k8s.io/implementations) but some examples include Envoy Gateway, Traefik Proxy, Cilium and Istio.

In this post I will focus on [Envoy Gateway](https://gateway.envoyproxy.io) but the general concepts should stay the same for other implementations.

When explaining Gateway API it can be useful to have the illustration below in the back of your mind.
Feel free to use it as a reference as you read on.

![gateway-api illustration](/images/2025-07-16-12-35-56.png)
_Gateway API illustration from the official documentation_

If you are familiar with Ingress in Kubernetes, think of Gateway API like this:

| Ingress API       | Gateway API                   |
| ----------------- | ----------------------------- |
| IngressClass      | GatewayClass                  |
| IngressController | Gateway                       |
| Ingress           | HTTPRoute, TLSRoute, TCPRoute |

Let us go through the most important resources one by one.

### GatewayClass

We start at the top, with the GatewayClass (equivalent to an IngressClass).

{{< notice note >}}
If you want to test Envoy Gateway locally, I recommend you look at their [quickstart](https://gateway.envoyproxy.io/docs/tasks/quickstart) instead of using my examples as they have been simplified a bit.
{{</notice>}}

In the simplest type of setup, you would only need a single GatewayClass:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
```

A common scenario is when you want to provide developers with a way of exposing applications publicly on the internet, but also the ability to expose them on an internal private network.
In this case you would typically create two GatewayClasses like this:

```yaml
kind: GatewayClass
metadata:
  name: internet
```

```yaml
kind: GatewayClass
metadata:
  name: private
```

### Gateway

The next resource it the Gateway itself. In OpenShift this is equivalent to the `IngressController` resource but for other Ingress providers there is usually not a separate resource for this.
The Gateway is responsible for configuring the infrastructure so that network traffic in some way (up to the implementation) can reach the cluster, for example with a LoadBalancer service, in addition to the software that routes this traffic (typically a reverse proxy of some sort).

In the case of Envoy Gateway, an [Envoy proxy](https://www.envoyproxy.io) is started and is what does the actual proxying and loadbalancing.
Below is a simple example of a Gateway with a single http listener:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
spec:
  gatewayClassName: eg
  listeners:
    - name: http
      port: 80
      protocol: HTTP
```

The gateway deployment can be customized using an `EnvoyProxy` resource that is attached via `spec.infrastructure.parametersRef`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
spec:
  gatewayClassName: eg
  infrastructure:
    parametersRef:
      group: gateway.envoyproxy.io
      kind: EnvoyProxy
      name: proxy-config
  listeners:
    - name: http
      port: 80
      protocol: HTTP
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: proxy-config
spec:
  logging:
    level:
      default: warn
  provider:
    type: Kubernetes
    kubernetes:
      envoyDeployment:
        replicas: 3
      envoyService:
        annotations:
          metallb.universe.tf/address-pool: default
        type: LoadBalancer
        allocateLoadBalancerNodePorts: false
```

We can also add more listeners if we want to, here is an example with listeners for https (terminated in the gateway) and passthrough tls.
Hostname matchers are added to control what listener an httproute is attached to.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: eg
spec:
  gatewayClassName: eg
  infrastructure:
    parametersRef:
      group: gateway.envoyproxy.io
      kind: EnvoyProxy
      name: proxy-config
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: "www.example.com"
    - name: https
      protocol: HTTPS
      port: 443
      hostname: "*.example.com"
      tls:
        mode: Terminate
        certificateRefs:
          # assume this contains a wildcard certificate for *.example.com
          - kind: Secret
            name: eg-https
    - name: tls
      port: 6443
      protocol: TLS
      tls:
        mode: Passthrough
```

In this case an httproute with `www.example.com` as the hostname would match the _HTTP_ listener, while httproutes with hostnames like `foo.example.com` or `bar.example.com` would match the _HTTPS_ listener.
This can of course be tweaked and modified further and you can read more about it in the `HTTPRouteSpec` mentioned below.
The tls listener can only be used by a TLSRoute.

By default a Gateway can only be used by routes in the same namespace, this can be modified with the `allowedRoutes` field on each listener.

If we want to make a listener available in all namespaces we can do it like this:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: eg
spec:
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: "www.example.com"
      allowedRoutes:
        namespaces:
          from: All
```

Or if we only make it available from namespaces matching a selector:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: eg
spec:
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: "www.example.com"
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              gateway-access: "true"
```

### HTTPRoute

Now lets take a look at a simple example on how to expose an application with an HTTPRoute.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: static-site
spec:
  parentRefs:
    - name: eg
  hostnames:
    - "www.example.com"
  rules:
    - backendRefs:
        - group: ""
          kind: Service
          name: static-site
          port: 8080
          weight: 1
      matches:
        - path:
            type: PathPrefix
            value: /
```

At first glance this [looks similar](https://kubernetes.io/docs/concepts/services-networking/ingress/#the-ingress-resource) to an Ingress resource, but the actual structure is in fact quite different.

Some of the biggest differences:

- Because it is an HTTPRoute, http is implicit and does not need to be specified under rules
- parentRefs is used to select the desired Gateway(s) instead of ingressClassName
- Annotations are not used for configuration (more on this below)

To convert existing ingresses to their corresponding Gateway API resources, some providers support using the tool [ingress2gateway](https://github.com/kubernetes-sigs/ingress2gateway).

### TLSRoute

If we wanted to use the tls passthrough listener in the Gateway above, we would need to create a [TLSRoute](https://gateway-api.sigs.k8s.io/concepts/api-overview/?h=tlsroute#tlsroute) which is available in the Experimental Channel of Gateway API.

```yaml
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: TLSRoute
metadata:
  name: backend-tls
spec:
  parentRefs:
    - name: eg
  hostnames:
    - "foo.example.com"
  rules:
    - backendRefs:
        - group: ""
          kind: Service
          name: backend
          port: 443
          weight: 1
```

### Traffic Overview

With these resources we can now access our application and the overall traffic flow looks like this:

1. Client sends an http request to the Gateway (usually via a LoadBalancer service)
2. Gateway sees that the request matches one of its listeners
3. HTTPRoute / TLSRoute sends the traffic to the correct backend according to its rules
4. Service proxies the traffic to the pod(s) running the application

![httproute](/images/2025-10-10-13-39-50.png)

## Gateway vs Ingress

You might be asking, why do we need Gateway API when we already have Ingress?

First of all, development on Kubernetes Ingress is frozen, which means that any new features will be added to Gateway API from now on.
This also means that most of the big providers have transitioned their implementation to use Gateway API.

![frozen](/images/2025-10-10-17-04-41.png)

Second, the current implementation of Ingress in Kubernetes is very bare-bones and lacks extensibility, which has resulted in a big sprawl between the different implementations on how things are done.
With Gateway API everyone is using the same standardized specification, while still allowing for extending functionality with implementation-specific resources.

There are several other benefits of using Gateway API over Ingress, one of the most obvious improvements is with configuration and customization.

With Ingress, this is usually handled with annotations on the Ingress resource and you could in a worst case scenario end up with something like this:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
  annotations:
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "https://example.com"
    nginx.ingress.kubernetes.io/cors-allow-methods: "GET,POST,PUT,DELETE,OPTIONS"
    nginx.ingress.kubernetes.io/cors-allow-headers: "Authorization,Content-Type"
    nginx.ingress.kubernetes.io/cors-expose-headers: "X-Request-Id"
    nginx.ingress.kubernetes.io/cors-max-age: "86400"
    nginx.ingress.kubernetes.io/cors-allow-credentials: "true"
    nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8,192.168.0.0/16"
spec:
  ingressClassName: nginx
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app-svc
                port:
                  number: 80
```

With Gateway API however, you could do do the same like this:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app
spec:
  parentRefs:
    - name: edge
  hostnames:
    - app.example.com
  rules:
    - backendRefs:
        - name: app-svc
          port: 80
---
# SecurityPolicy: CORS + IP allowlist (replaces the Ingress annotations above)
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: app-security
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: app
  cors:
    allowOrigins: ["https://example.com"]
    allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allowHeaders: ["Authorization", "Content-Type"]
    exposeHeaders: ["X-Request-Id"]
    allowCredentials: true
    maxAge: 86400
  authorization:
    defaultAction: Deny
    rules:
      - action: Allow
        principal:
          clientCIDRs:
            - 10.0.0.0/8
            - 192.168.0.0/16
```

The HTTPRoute itself stays tidy and any extra customization can be offloaded to a SecurityPolicy, HTTPRouteFilter, BackendTrafficPolicy or ClientTrafficPolicy resource.

By utilizing `spec.targetRefs`, this SecurityPolicy resource for example can be used per HTTPRoute or enforced for all routes on a specific Gateway.

{{< notice note >}}
[SecurityPolicy](https://gateway.envoyproxy.io/latest/concepts/gateway_api_extensions/security-policy/) is specific to Envoy Gateway, but other implementations should have similar ways of configuring these types of settings.
{{</notice>}}

## In praise of good statuses

When using Gateway API you can really tell that is a modern Kubernetes API with a lot of thought put into it. This is especially true when it comes to the statuses and conditions for all the resources.

Just by looking at the status of a resource you can quickly tell if everything is working or if there is something wrong with the configuration and _why_.

Many Kubernetes APIs are unfortunately not great at this, so it is very refreshing to see it done well and it is a joy to work with.

Examples from HTTPRoute and Gateway:

**HTTPRoute**

```yaml
status:
  parents:
    - conditions:
        - message: Route is accepted
          reason: Accepted
          status: "True"
          type: Accepted
      controllerName: gateway.envoyproxy.io/gatewayclass-controller
      parentRef:
        group: gateway.networking.k8s.io
        kind: Gateway
        name: eg
```

**Gateway**

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

It is also very noticeable when working with all the different resources. Every field of every CRD is extremely well documented and has great validation as well,

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

The full API documentation can be found [here](https://gateway-api.sigs.k8s.io/reference/spec)

## Conclusion

That concludes this post about Gateway API, thanks for reading!

If I ever write a new article on the topic it will be about the Gateway API [Inference Extension](https://gateway-api-inference-extension.sigs.k8s.io) and [Envoy AI Gateway](aigateway.envoyproxy.io/docs).

Useful links:

- Gateway API
  - [Introduction](https://gateway-api.sigs.k8s.io/)
  - [Getting Started](https://gateway-api.sigs.k8s.io/guides)
  - [Glossary](https://gateway-api.sigs.k8s.io/concepts/glossary)
  - [API Reference](https://gateway-api.sigs.k8s.io/reference/spec)
- Envoy Gateway
  - [Documentation](https://gateway.envoyproxy.io/docs/)
  - [Quickstart](https://gateway.envoyproxy.io/docs/tasks/quickstart)
  - [Extensions](https://gateway.envoyproxy.io/docs/concepts/gateway_api_extensions)
