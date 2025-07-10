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
- id: 6floxcaiyjna
  title: SSH
  type: terminal
  hostname: kubernetes-vm
difficulty: ""
timelimit: 0
enhanced_loading: null
---
Now everything being green in our environment is great but we want to have a little more fun. Lets bring down the database.

Firstly head over to the SSH tab and enter the following commands.

```text
cd instruqt-scripts-v2/
./trigger-database-outage.sh
```
Make sure the time range is set to the last hour and head over to the business health dashboard.

Notice on the business health dashboard we start top see errors in our MySQL logs immediately:

![Jul-10-2025_at_11.50.51-image.png](../assets/Jul-10-2025_at_11.50.51-image.png)

Over time you can see on the dashboard our Database SLO starts to degrade.

Heading over to Alerts - we have two alerts that have popped up. The first alert is about the Database SLO is burning down rapidly and the second alert is about the spike in error logs.

![Jul-10-2025_at_11.57.03-image.png](../assets/Jul-10-2025_at_11.57.03-image.png)