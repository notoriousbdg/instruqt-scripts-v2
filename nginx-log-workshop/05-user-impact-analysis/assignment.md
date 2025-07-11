---
slug: user-impact-analysis
id: 0qme9n0asqur
type: challenge
title: User impact using ES|QL and Discover
tabs:
- id: x9rqwsxlqrk3
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
- id: vrhdozi9ioyy
  title: SSH
  type: terminal
  hostname: kubernetes-vm
difficulty: ""
timelimit: 0
enhanced_loading: null
---
For our final assignment we are going to be using Discover to find which users were impacted because of the database outage.

Firstly select "Discover" from the left hand menu:

![Jul-10-2025_at_14.40.19-image.png](../assets/Jul-10-2025_at_14.40.19-image.png)

Click "Try ES|QL"

![Jul-10-2025_at_14.40.33-image.png](../assets/Jul-10-2025_at_14.40.33-image.png)

Put the following query in (note that the date in here ".ds-logs-mysql.error-default-2025.07.10-000001" and here " .ds-logs-nginx.access-default-2025.07.10-000001" will need to be changed to todays date):

```
from logs-mysql.slowlog-default | LOOKUP JOIN .ds-logs-mysql.error-default-2025.07.10-000001 ON mysql.thread_id | where mysql.thread_id is not null | LOOKUP JOIN .ds-logs-nginx.access-default-2025.07.10-000001 ON request_id | KEEP user.name, mysql.slowlog.query
```

Now we can see the users that were affected by our database outage and which queries were affected using the new Lookup Join function!