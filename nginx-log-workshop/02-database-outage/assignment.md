---
slug: database-outage
id: rhhmjgk3benv
type: challenge
title: Database outage!
tabs:
- id: t0kbe2wclh3u
  title: Kibana
  type: service
  hostname: kubernetes-vm
  path: /app/dashboards#/view/4e60e0c7-3106-49bc-a814-890b6cbf085c?_g=(filters:!(),refreshInterval:(pause:!t,value:60000),time:(from:now-1h,to:now))
  port: 30001
  custom_request_headers:
  - key: Content-Security-Policy
    value: 'script-src ''self''; worker-src blob: ''self''; style-src ''unsafe-inline''
      ''self'''
  custom_response_headers:
  - key: Content-Security-Policy
    value: 'script-src ''self''; worker-src blob: ''self''; style-src ''unsafe-inline''
      ''self'''
- id: 6floxcaiyjna
  title: SSH
  type: terminal
  hostname: kubernetes-vm
difficulty: ""
timelimit: 0
enhanced_loading: null
---
> [!WARNING]
> OH NO, THE DATABASE HAS GONE DOWN! WE NEED TO FIND OUT WHATS HAPPENING AND FAST!

![Jul-11-2025_at_14.37.35-image.png](../assets/Jul-11-2025_at_14.37.35-image.png)

Make sure the time range is set to the last hour and head over to the business health dashboard.

Notice on the business health dashboard we start top see errors in our MySQL logs immediately:

![Jul-10-2025_at_11.50.51-image.png](../assets/Jul-10-2025_at_11.50.51-image.png)

Over time you can see on the dashboard our Database SLO starts to degrade.

Heading over to Alerts - we have two alerts that have popped up. The first alert is about the Database SLO is burning down rapidly and the second alert is about the spike in error logs.

![Jul-10-2025_at_11.57.03-image.png](../assets/Jul-10-2025_at_11.57.03-image.png)