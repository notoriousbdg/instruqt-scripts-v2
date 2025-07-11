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
  path: /app/observability/alerts?_a=(filters:!(),kuery:%27%27,rangeFrom:now-1h,rangeTo:now,status:all)
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
Right lets take a look at this "Spike in Database Errors" Alert, when we click on the ... and click "View Alert Details" we can see Elastic immediately runs our root cause analysis engine.

![Jul-10-2025_at_13.44.39-image.png](../assets/Jul-10-2025_at_13.44.39-image.png)

Wow - we can see a lot of new error messages in the database logs, this is not good news.  The problem is I don't fully understand these logs, lets use our AI Assistant to translate these into something I can understand.

Click on "Possible causes and remediations" to call in reinforcements.

![Jul-10-2025_at_13.49.39-image.png](../assets/Jul-10-2025_at_13.49.39-image.png)

The anomalous messages in our logs and only those messages are sent to the AI Assistant for analysis and it conducts an analysis for us.

![Jul-10-2025_at_13.50.35-image.png](../assets/Jul-10-2025_at_13.50.35-image.png)

Now lets check and see if this is impacting our front end, click on "Start Conversation"

![Jul-10-2025_at_13.51.27-image.png](../assets/Jul-10-2025_at_13.51.27-image.png)

Now lets ask the assistant:

> [!NOTE]
> Using lens create a single graph of all http response status codes < 400 and >=400 from logs-nginx.access-default over the last 3 hours.

![Jul-10-2025_at_14.01.05-image.png](../assets/Jul-10-2025_at_14.01.05-image.png)

So we can see this is affecting quite a few people on the frontend, not a good sign.  Now lets also see if the impact is global.

Ask the assistant:

> [!NOTE]
> What are the top 10 source.geo.country_name with http.response.status.code>=400 over the last 3 hours. Use logs-nginx.access-default. Provide counts for each country name.

![Jul-10-2025_at_14.04.20-image.png](../assets/Jul-10-2025_at_14.04.20-image.png)

Ooof, this is clearly a global issue, we need to get moving on this fast.

Next lets look at teaching the AI Assistant a few tricks so it can help us with the business impact.
