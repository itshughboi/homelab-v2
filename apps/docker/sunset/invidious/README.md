## Installation
1. Generate po_token and visitor_data
```
docker run quay.io/invidious/youtube-trusted-session-generator
```
2. Edit docker-compose.yaml with updates values. Fill out .env for Postgres db connection <br>
hmac key: random password

## Preferences - Multi User setup
- Once installed go to Settings -> User Preferences. Proxy: CHECKED <br>
With this on, other users using my instance will show as my public IP rather than their own as I am becoming the forward proxy at this point. Increases bandwidth. Only useful in multi-user environment

