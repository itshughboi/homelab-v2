## Installation
Help: https://www.youtube.com/watch?v=SVMHsoWMKI4


1. Create config file
```
sudo docker run -it --rm
--mount type=volume,src=synapse-data,dst=/data
-e SYNAPSE_SERVER_NAME=matrix.hughboi.cc
-e SYNAPSE_REPORT_STATS=no
matrixdotorg/synapse:latest generate
```

2. Grab config and put in volume mount
``` 
sudo -i 
cd /var/lib/docker/volumes/synapse-data/_data
ls
cp * /home/hughboi/synapse
```

3. Permissions
```
chown hughboi:hughboi *
su hughboi
```

4. Match homeserver.yaml so that it uses postgres instead
5. Edit docker compose if needed
6. Fill in .env variables for postgres
7. Spin up container and check logs
8. Go to 'matrix.hughboi.cc' and I can verify that Matrix/Synapse is working/operational
9. Make admin user
```
sudo docker exec -it synapse register_new_matrix_user http://localhost:8008 -c /data/homeserver.yaml --help #remove help once ready
```
10. Go to app.element.io and pick 'Homeserver' and put in 'https://matrix.hughboi.cc' and login with admin user
11. Start using it. Make sure to backup my security keys for any rooms I create with End to End Cryption

## Discord Bridge
1. Configure docker compose including volume mount
2. Fill out .env files for the Postgres databasae
3. run docker compose up one time and then I will get config
4. Edit config.yaml
Change:
- domain
- hostname
- postgres URI
5. Set permissions for my user (bottom of config.yaml)
```
    permissions:
        "*": relay
        "matrix.hughboi.cc": user
        "@hughboi:matrix.hughboi.cc": admin
```
6. Deploy container again with --force-recreate
7. This time I will get registration.yaml (can't view it because permissions are 1337:1337. Have to use sudo to view it or edit)
- Copy these contents to synapse home directory
8. Change homeserver.yaml to point to this registration
```
app_service_config_files:
- /data/registration.yaml
```
9. Get back into Element
10. Start new chat with discord bot to be put into a chat with it. 
```
@discordbot:matrix.hughboi.cc
```
11. After bot creates room, type ``` help ```
12. Authenticate with qr code
```
login -qr
```
^^ Then scan from discord on phone and it will log me in automatically. 
13. Bridge discord
```
guilds bridge ID --entire #find in the web browser URL
```
14. Configure Relay
- Go into a room
```
!discord set-relay create 
```
^^ Show now be bridged and two way sync should now be working between discord and element. Have to do this with every person/server I want to chat with