### Loki is a database for all your logs
It only will attach labels to logs to index logs, rather than index everything. Makes it more responsive and faster queries. The logs
are in a compressed format

### Promtail pushes to Loki
Going to be replaced by Grafana Alloy. Integrates with Kubernetes. Essentially it is designed to scrape logs from things like syslog
and push them into Loki.

Promtail looks at host it's installed on e.g. /var/logs

### Docker plugin
Attaching labels to containers will allow containers to send logs directly to Loki

### Loki Storage
Filesystem isn't recommended in production but I use it. You can also send to something like S3 or off to TrueNAS

### Grafana Visualization
Grafana is the visualization piece we will integrate with

### Query Language
promql is pretty much logql so if you know promethesus queries, you'll be set


***


## Installation
Docker Compose AND Helm available

#### Docker Compose
1. Edit docker-compose.yaml and config.yaml
2. On docker machines install the loki docker plugin
```
docker plugin install grafana/loki-docker-driver:3.3.2-arm64 --alias loki --grant-all-permissions
docker plugin ls
```
3. Attach labels to docker containers I want to ship to Loki in docker-compose.yaml
```
logging:
      driver: loki
      options:
        loki-url: "https://loki.hughboi.cc/loki/api/v1/push"
        loki-retries: 2
        loki-max-backoff: 800ms
        loki-timeout: 1s
        keep-file: "true"
        mode: "non-blocking"
```
4. Restart containers
5. Go to existing Grafana instance. Connections -> Data Sources -> Add Data Source -> Loki
connection: https://loki.hughboi.cc
6. You can now query and view logs 


***


## Machine2Machine Authentication via HTTP Basic Auth
Prerequisites: middleware created in traefik for Authentik
1. Uncomment Authentik label. Make sure it matches the middleware i have in traefik/config/middlewares.yaml
2. Go to Authentik -> Applications -> Providers -> New Provider
```
name: loki
Authorization flow: implicit-consent (Authorize Application)
Forward auth (single application)
External host: https://loki.hughboi.cc
```
3. Create a new application and select provider we just created
4. Under Applications -> Outposts add loki to 'Selected Applications' for the Outpost Proxy
5. Restart container and make sure when you go to https://fQDN you hit Authentik
6. Navigate to Directory -> Tokens and App passwords -> Create
```
identifier: loki
user: loki ### << create this first. We'll give privileges to just this application for security best practices
intent: App password
```
7. Then hit on the newly created identifier and hit copy token and you will see the random password
8. Test with Grafana. Test the Loki connection and I should get an authentication error now. 
9. Under the Authentication settings for Loki, select Basic authentication as the method and put in the user and password I just setup.
Hit save and test and make sure it works.
10. Change loki labels to send Basic Auth credentials
```
 logging:
      driver: loki
      options:
        loki-url: "https://hughboi:RANDOMLY_GENERATED_PASSWORD_FROM_AUTHENTIK@loki.hughboi.cc/loki/api/v1/push"
        loki-retries: 2
        loki-max-backoff: 800ms
        loki-timeout: 1s
        keep-file: "true"
        mode: "non-blocking"
```
With .env 
```
 logging:
      driver: loki
      options:
        loki-url: "https://${USER}:${PASS}@loki.hughboi.cc/loki/api/v1/push"
        loki-retries: 2
        loki-max-backoff: 800ms
        loki-timeout: 1s
        keep-file: "true"
        mode: "non-blocking"
```

<br>
**Currently using** 

```
logging:
  driver: loki
  options:
    loki-url: https://loki.hughboi.cc/loki/api/v1/push
    loki-retries: 2
    loki-max-backoff: 800ms
    loki-timeout: 1s
    keep-file: "true"
    mode: non-blocking
```

11. Restart container and check if you see logs