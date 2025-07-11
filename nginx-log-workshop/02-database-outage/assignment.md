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

Lets take a look at how the SLO is constructed, head over to the SLO navigation on the left hand side.

![Jul-11-2025_at_15.14.03-image.png](../assets/Jul-11-2025_at_15.14.03-image.png)

Click on the Database SLO

![Jul-11-2025_at_15.14.28-image.png](../assets/Jul-11-2025_at_15.14.28-image.png)

Select "Definition"

![Jul-11-2025_at_15.14.55-image.png](../assets/Jul-11-2025_at_15.14.55-image.png)

Notice that this SLO is constructed entirely from Log data, we are looking specifically for any errors in our mysql log files.

Next up we will explore the alert and try to find the root cause of the database outage.