---
slug: root-cause-analysis
id: tzjd19eywmsw
type: challenge
title: Root cause analysis
tabs:
- id: mvt3yalrsywn
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
- id: sfd55lnvx39n
  title: SSH
  type: terminal
  hostname: kubernetes-vm
difficulty: ""
timelimit: 0
enhanced_loading: null
---
Right lets take a look at this "Log Spike" Alert, when we click on the ... and click "View Alert Details" we can see Elastic has started to run root cause analysis.

![Jul-10-2025_at_12.46.31-image.png](../assets/Jul-10-2025_at_12.46.31-image.png)

