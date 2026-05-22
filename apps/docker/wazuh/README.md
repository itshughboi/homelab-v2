
# Deploy Wazuh Docker in single node configuration

1) Increase max_map_count on your host (Linux). This command must be run with root permissions:
```sh
sysctl -w vm.max_map_count=262144
#Make it persistent
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
```
2) Run the certificate creation script:
```sh
docker compose -f generate-indexer-certs.yml run --rm generator
```
3) Start the environment with docker-compose:
```sh
docker compose up -d
```

The environment takes about 1 minute to get up (depending on your Docker host) for the first time since Wazuh Indexer must be started for the first time and the indexes and index patterns must be generated.




## Manual
- Code in repo as is should work, but if I need to do the cert generation at all again...

```sh
git clone https://github.com/wazuh/wazuh-docker.git -b v4.12.0 #replace with desired wazuh tag
```
- Then move config/ to ${CODE_ROOT}/wazuh/config
- Run the generator command
```sh
docker compose -f generate-indexer-certs.yml run --rm generator
```
- Then stand up container once I see certs generated successfully
```sh
docker compose up -d
```


### Password Change (Do before you stand up compose stack)
- Run the below inside the **wazuh_indexer** container
```sh
# Generate hash for admin (INDEXER_PASSWORD)
JAVA_HOME=/usr/share/wazuh-indexer/jdk bash -c "/usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh -p 'YOUR_PASSWORD_HERE'"

# Generate hash for kibanaserver (DASHBOARD_PASSWORD)
JAVA_HOME=/usr/share/wazuh-indexer/jdk bash -c "/usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh -p 'YOUR_PASSWORD_HERE'"
```
- Then update *internal_users.yml* with the new hashes. The .env should contain the plaintext of the YOUR_PASSWORD_HERE
- After making changes to internal_users.yml you need to reload the security script
```sh
docker exec wazuh_indexer bash -c "JAVA_HOME=/usr/share/wazuh-indexer/jdk \
  /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
  -cd /usr/share/wazuh-indexer/opensearch-security/ \
  -icl -nhnv \
  -cacert /usr/share/wazuh-indexer/certs/root-ca.pem \
  -cert /usr/share/wazuh-indexer/certs/admin.pem \
  -key /usr/share/wazuh-indexer/certs/admin-key.pem \
  -h 127.0.0.1"
```
- You do not need to do this for the API password. That is just plaintext inside of the env


### Essential Permissions
```sh
sudo chmod 600 ${DATA_ROOT}/wazuh/wazuh_indexer_ssl_certs/*.key
sudo chmod 644 ${DATA_ROOT}/wazuh/wazuh_indexer_ssl_certs/*.pem
# Ensure indexer can write to its data
sudo chown -R 1000:1000 ${DATA_ROOT}/wazuh/wazuh_indexer_ssl_certs
```

### API
- API password needs to be updated manually to match API_PASSWORD in .env since variable substitutes aren't allowed
- Add wazuh.yml to gitignore as it contains a API password in plain text that shouldn't be uploaded to git

### Post Install Notes
- Cert generator 0.0.2 not 0.0.4 << 0.0.4 was breaking
- Certs go in data/, configs in code/
- Indexer certs mount to /usr/share/wazuh-indexer/certs/
- Comment out SSL in opensearch_dashboards.yml for Traefik
- Hash passwords with JAVA_HOME=/usr/share/wazuh-indexer/jdk before running hash.sh
- Run securityadmin.sh after changing internal_users.yml
- Wipe wazuh_api_configuration volume to reset API users (IF NEEDED!!! If I get API connection issues, try this)
    ```sh
    docker compose down
    docker volume rm wazuh_wazuh_api_configuration
    docker compose up -d
    ```


### Traefik issues
- it took me a long time to find how to put this behind traefik. Everything was configured, but I could only access it via ip, not the dns name. Fixed by commenting the following in this file:
 *${CODE_ROOT}/wazuh/config/wazuh_dashboard/opensearch_dashboards.yml*
 ```
    #server.ssl.enabled: true
    #server.ssl.key: "/usr/share/wazuh-dashboard/certs/wazuh-dashboard-key.pem"
    #server.ssl.certificate: "/usr/share/wazuh-dashboard/certs/wazuh-dashboard.pem"
```


## Notifications

### Discord
- Add ${DISCORD_WEBHOOK} environment variable first!
- Hamburger Menu -> Server Management -> Settings -> Edit Configuration (Top right corner)
1. Add the following in the </global> field
```
 <integration>
     <name>custom-discord</name>
    <hook_url>${DISCORD_WEBHOOK}</hook_url>
     <alert_format>json</alert_format>
 </integration>
```

 2. Save + Restart Manager
 3. On the ubuntu host, go to the integrations mapped folder in the cli and do the following while under **sudo su**
      1. Grab the integration files
        ```sh
        wget https://raw.githubusercontent.com/maikroservice/wazuh-integrations/main/discord/custom-discord <br>
        wget https://raw.githubusercontent.com/maikroservice/wazuh-integrations/main/discord/custom-discord.py
        ```

      2. Then run the following:
        ```sh
        sudo chmod 750 ${DATA_ROOT}/wazuh/integrations/custom-*
        sudo chown root:wazuh ${DATA_ROOT}/wazuh/integrations/custom-*
        ```
      3. Then get the python extension <br>
        ```
        sudo apt-get install python3-pip
        pip3 install requests
        ```
  4.  Restart Wazuh's controls
  ```sh
  sudo docker compose up -d --force-recreate
  ```
