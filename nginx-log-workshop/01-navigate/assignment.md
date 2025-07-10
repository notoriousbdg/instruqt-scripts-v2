---
slug: navigate
id: xncysodll5xj
type: challenge
title: Navigate around the environment
tabs:
- id: vdgzlgzyxtzc
  title: Kibana
  type: service
  hostname: kubernetes-vm
  path: /app/dashboards
  port: 30001
  custom_request_headers:
  - key: Content-Security-Policy
    value: 'script-src ''self''; worker-src blob: ''self''; style-src ''unsafe-inline''
      ''self'''
  custom_response_headers:
  - key: Content-Security-Policy
    value: 'script-src ''self''; worker-src blob: ''self''; style-src ''unsafe-inline''
      ''self'''
- id: ieelvfgxnayo
  title: SSH
  type: terminal
  hostname: kubernetes-vm
difficulty: ""
timelimit: 0
enhanced_loading: null
---
Welcome to the Elastic Logging Workshop

You're now in Kibana, the Elastic user interface.

> [!NOTE]
> Did you know: **Kibana** was named by Rashid Khan as the Swahili translation of "log cabin" - a home made of logs.

Firstly lets have a quick look at our environment.

Our eCommerce application exists as a simple three tier application, with a frontend (hosted on nginx) a backend (also hosted by nginx) and a mysql database hosted on Kubernetes. As shown below.

![Jul-10-2025_at_10.34.45-image.png](../assets/Jul-10-2025_at_10.34.45-image.png)

We are using Elastic Agent in a sidecar configuration to collect the logs from each pod.

You'll notice in Elastic that you are brought initally to the dashboard page.

![Jul-10-2025_at_10.49.39-image.png](../assets/Jul-10-2025_at_10.49.39-image.png)

Lets start by poking around in the environment. Open up the "Business Health Dashboard".

![Jul-10-2025_at_10.50.23-image.png](../assets/Jul-10-2025_at_10.50.23-image.png)

As you can see at the moment everything is green, no major issues, revenue looks to be flowing in nicely and we have a manageable number of errors.


