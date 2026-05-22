# Overview
Watchtower ONLY runs on services using the **latest** tag. Best practice is to specify which containers to skip (e.g. traefik) for critical services

# API
**Pre-Requisisites**
1. Setup API endpoint. Add this to environment
```sh
- WATCHTOWER_HTTP_API_METRICS=true
- WATCHTOWER_HTTP_API_TOKEN=/run/secrets/watchtower_api_token
```
2. Add API Token
   1. Create new file called **watchtower_api_token** and put in a random complex string. Put this string into prometheus.yml
3. Add a port mapping for port **8080** e.g. 8765:8080
