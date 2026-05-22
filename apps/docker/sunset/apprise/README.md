## DECOMMISSIONED
Now I am only using mailrise which uses the apprise engine underneath. I have no more use of this web apprise-api. See my 'mailrise' project instead.


***

#### Test via CLI

###### Discord
apprise -b "message" -t "title" discord://webhook_id/webhook_token


#### Test via API
curl -X POST https://apprise.hughboi.cc/notify \
  -H "Content-Type: application/json" \
  -d '{
        "urls": "discord://DISCORD_SERVER_URL",
        "title": "Test Notification",
        "body": "This is a test message sent via Apprise!"
      }'