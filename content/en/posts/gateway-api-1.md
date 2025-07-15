---
date: "2025-07-01T15:41:19+02:00"
draft: false
tags:
  - kubernetes
  - network
title: "Gateway API for dummies"
---

I recently had a use-case where I could finally tinker with Gateway API, a fairly new optional feature/extension for handling ingress traffic in Kubernetes. You can think of it as a successor to the current Ingress APIs.

Instead of an IngressController you set up a Gateway

| Ingress           | Gateway                       |
| ----------------- | ----------------------------- |
| IngressClass      | GatewayClass                  |
| IngressController | Gateway                       |
| Ingress           | HTTPRoute, TLSRoute, TCPRoute |

Instead of annotating an ingress with settings on how it should handle various types of traffic, you can use resources like BackendTrafficPolicy and (in the case of Envoy) BackendTLSTraffic.
You can refer to these from an individual HTTPRoute or for the whole Gateway.

compare ingress / ingresscontroller (openshift) with gateway api

praise statuses

envoy gateway

metallb

backendtrafficpolicy

tracing
no luck with tlsroute for some reason.
