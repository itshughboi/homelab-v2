### 1. Proxmox Setup
####  Cloud-Init
Go to Ubuntu Cloud Images Releases. Find the LTS I want. Navigate into the 'current' directory. Find the amd.img and right click and hit 'copy link address' and then on local storage in Proxmox query that URL.
https://cloud-images.ubuntu.com/

##### Shell

> [!NOTE] Template ID
> Replace '5003' below with whatever ID you wish to assign the template. Must be unique on each node. Change RAM + cores accordingly
``` 

qm create 5003 --memory 8192 --core 4 --name ubnt-cloud-noble --net0 virtio,bridge=vmbr0
```

###### Verify iso exists
```
cd /var/lib/vz/template/iso/
ls
```

###### Add iso to that machine
```
qm importdisk 5003 noble-server-cloudimg-amd64.img local-lvm
qm set 5003 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-5003-disk-0
```

###### Expand Hard drive
```
qm disk resize 5003 scsi0 50G
```

###### Attaching drive to vm
```
qm set 5003 --ide2 local-lvm:cloudinit
```

```
qm set 5003 --boot c --bootdisk scsi0
qm set 5003 --serial0 socket --vga serial0
```

##### Proxmox GUI

###### Hardware Tab
1. Click on the Hard Disk. Turn on **SSD Emulation** so that it can do S.M.A.R.T.
2. On Memory turn off **ballooning memory**

###### Cloud-init Tab
- Change username to **hughboi**
- Add public key from my automation machine (ansible) AND from proxmox host. I want to add it from the proxmox host so that I can **VNC** into it from console. I can create new ssh keys if I want from proxmox, but I just use the default ssh-rsa. Ansible I always create my own
Proxmox SSH location:
```
cat /root/.ssh/id_rsa.pub
```
***

> [!NOTE] In production I would want to specify separate specific keys for ^^
> 
> 

- Make sure IP Config is set to DHCP. Else it will clone each VM with same IP. Instead, take the hardware device after I do a Full Clone and then set a **DHCP Reservation**
- Right click vm BEFORE STARTING and hit **Convert to template**. Everything will fuck if I start that vm. 


> [!DANGER] DO NOT START THIS VM. CONVERT TO TEMPLATE. ELSE IT WILL **FUCK** UP
> 
> 

#### VM Clone + Networking
1. Right click on template on each node and hit **Full Clone**
2. Then under **Hardware -> Network Device -> MAC**, add this client to Unifi before starting the VM and set a name (alias) + desired IP.
	1. Otherwise, start the VM, generate network traffic by pinging 'google.com', then find the device in Unifi + give it a DHCP reserveration. Reboot and it will have the IP I want

> [!WARNING] IMPORTANT!!! SNAPSHOT VM'S BEFORE PROCEEDING!!!
> 
> 



### 2. Ansible VM Setup

> [!NOTE] Ansible Cloud-Init
> Technically I do this after I get the cloud-init template up and going, and I full clone that
```

sudo apt update
sudo apt install software-properties-common -y
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install ansible -y
```
1. Create new SSH keys. Leave password empty. We'll need ths for **Cloud-Init**
```
ssh-keygen -t ed25519 -C "ansible" -f ~/.ssh/ansible
ls ~/.ssh/ansible*
```
1. copy ssh public key from /.ssh to home directory (ansible.pub or id_rsa.pub)
```
cd ./.ssh
cp ansible.pub /home/hughboi
```



### 3. Ansible Deploy
#### SSH-Keys
> [!NOTE] Preconfigured Keys
> In Cloud-Init for the workers + masters, I can specify these SSH keys during or after creation so it automatically gets uploaded. Otherwise, will need to do ssh-copy-id command. HOWEVER, this is a last resort option if nothing else works. Will need PermitRootLogin
> 
> 
```
ssh-copy-id -i ~/.ssh/ansible.pub hughboi@remote-machine-ip
```
2. Test SSH without password
```
ssh -i ~/.ssh/ansible hughboi@remote-machine-ip
```
3. Test Ansible connections
```
ansible all -m ping --key-file ~/.ssh/ansible
```

###### PubKey Authentication
- If I get a PubKey Authentication error, I need to console into each of those vm's, and enable authentication. However, as long as SSH is in cloud-init, it SHOULD work without needing to do this config. May need to specify the ssh key if it gives me permission denied (pubkey) error

> [!NOTE] Try This first
> On ansible, go into ~/.ssh/config and add the following:
> 

```
Host 10.10.30.1
  User hughboi
  IdentityFile ~/.ssh/ansible  

Host 10.10.30.2
  User hughboi
  IdentityFile ~/.ssh/ansible  

Host 10.10.30.3
  User hughboi
  IdentityFile ~/.ssh/ansible  

Host 10.10.30.11
  User hughboi
  IdentityFile ~/.ssh/ansible

Host 10.10.30.12
  User hughboi
  IdentityFile ~/.ssh/ansible

Host 10.10.30.13
  User hughboi
  IdentityFile ~/.ssh/ansible  

Host 10.10.30.21
  User hughboi
  IdentityFile ~/.ssh/ansible

Host 10.10.30.22
  User hughboi
  IdentityFile ~/.ssh/ansible

Host 10.10.30.23
  User hughboi
  IdentityFile ~/.ssh/ansible
```


> [!NOTE] If ^^ Didn't work after trying to ssh again...
> 
> Do these steps. However, this should be unnecessary as it's cloud-init

```
sudo nano /etc/ssh/sshd_config
```
	- Uncomment 'PubkeyAuthentication yes'
	- 'PasswordAuthentication no'
```
sudo systemctl daemon-reload
sudo systemctl restart ssh
```
	- Reboot VM + Retry connection
- If problem persists, try to ssh specifying the keys
```
ssh -i ~/.ssh/ansible hughboi@ansible
```

#### Script Deploy
4. Copy down k3s-deploy script from my public GitHub
```
curl -o k3s-deploy.sh https://raw.githubusercontent.com/itshughboi/k3s/refs/heads/main/k3s-deploy.sh
```
2. Make executable, run, then sit back and get some coffee
```
cd
chmod +x deploy.sh
./deploy.sh
```



### 4. Rancher Management
#### Install helm
```

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```

#### Add Rancher Helm Repository
```
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
kubectl create namespace cattle-system
```

#### Install Cert-Manager
```
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.crds.yaml
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
--namespace cert-manager \
--create-namespace \
--version v1.13.2
kubectl get pods --namespace cert-manager
```

#### Install Rancher
```
helm install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --set hostname=rancher.hughboi.vip \
  --set bootstrapPassword=admin
kubectl -n cattle-system rollout status deploy/rancher
kubectl -n cattle-system get deploy rancher
```


#### Expose Rancher via Loadbalancer

```
kubectl get svc -n cattle-system
kubectl expose deployment rancher --name=rancher-lb --port=443 --type=LoadBalancer -n cattle-system
kubectl get svc -n cattle-system
```

#### Go to Rancher GUI
1. Hit the url… and create your account. Be patient as it downloads and configures a number of pods in the background to support the UI (can be 5-10mins)
2. Leave the server IP as is.
3. **Bootstrap password:** admin  


### 5. Longhorn (Storage)
1. Create 3 new VM's from cloud-init template
2. Increase Hard Disk Size (I add 150GB on top of the 50GB from cloud-init for **200GB** total)
3. Make script (k3s-longhorn.sh) executable, and enjoy :) 
```
wget -o longhorn.sh https://raw.githubusercontent.com/itshughboi/k3s/refs/heads/main/longhorn.sh
```

4. You will now see a new 'Longhorn' Tab in rancher that will take you to the management page
5. I should see my 3 longhorn nodes + 3 worker nodes. However, the worker nodes are currently **schedulable** which we don't want. Check the box next to each worker node -> Edit Node -> Node Scheduling: Disable -> Save


##### PVC Claims
- For applications to use Longhorn storage, there needs to be a Persistent Volume Claim available to the volume that you create in your app deployment 
	- Rancher -> Longhorn -> Volume (should see detatched volume from app) -> action menu on right side of volume -> Create PVC (namespace needs to match what I did in app deployment, most likely just the name) and hit OK. It should automatically be assigned a few seconds later



### 6. Traefik
1. Pull down MY altered script to ansible. Had to make changes to get it working
```
cd
wget https://raw.githubusercontent.com/itshughboi/k3s/main/Traefik/traefik-deploy.sh
```
2. Edit script if needed + make it executable + run
```
chmod +x traefik-deploy.sh
./traefik-deploy.sh
```
3. This will pull down all the necessary files from my GitHub and then stop the script to allow me to edit them before I re-run

> [!WARNING]  ADD VALUES TO THESE VALUES BEFORE CONTINUING
> Cert-Manager/Issuers/letsencrypt-production.yaml >> Cloudflare Email
> Cert-Manager/Issuers/secret-cf-token.yaml >> Cloudflare API token
> Dashboard/secret-dashboard.yaml >> login credentials
> values.yaml  >> (loadBalancerIP)
> 


4. Rerun the script and I should then be able to see traefik in Workloads -> Deployments on Rancher with 3/3
5. Also watchthe status under More Resources -> Cert Manager -> Certificates to make sure it LetsEncrypt validated it and I see active and no errors. This can take a bit of time so come back if it's not ready yet.


##### DNS
- At this point it is essential to have my kubernetes domain (hughboi.vip) pointing to the LoadBalancerIP I picked. I have it currently set to **10.10.30.75**. Once my Bind9 DNS server points hughboi.vip there, I will be able to go to **traefik.hughboi.vip** and login with credentials I made under Dashboard/secret-dashboard.yaml with base64 encoding


##### Rancher Ingress TLS Troubleshooting
From everything we setup earlier with rancher.hughboi.vip, once Traefik is up and going, Rancher should now be automatically added to Traefik's ingress
You can validate the contents of your `tls-rancher-ingress` Secret using commands like this:

```bash

kubectl -n cattle-system get secret tls-rancher-ingress -o jsonpath='{.data}' | jq '."tls.crt"' | tr -d '"' | base64 --decode | openssl x509 -text

```


### 6a. Traefik Continued
Do you want that precious green lock in your URL bar?  If you have Traefik (or another Kubernetes Ingress controller)
deployed and a Let's Encrypt issuer with Cert-Manager, the Rancher Helm chart offers support to automatically configure
an ingress route with TLS certificate injection to access the Rancher UI via the `rancher` Kubernetes Service created
by the Helm install (`kubectl -n cattle-system get service`). This can be configured retroactively after your initial
`helm install ...`, but is a bit simpler to set up as part of your initial Rancher installation if you have the
prerequisites in place.

  
You first need to save the TLS certificate and key that you want Traefik to use for Rancher as a Kubernetes Secret
called `tls-rancher-ingress`.  You can do this manually, or let Cert-Manager generate a certificate for you and
store it in a Secret, using `kubectl` to create a Kubernetes Certificate resource to generate the certificate and
populate the Secret for you:
```yaml

---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: rancher-my-org
  namespace: cattle-system
spec:
  commonName: rancher.my.org
  dnsNames:
    - rancher.my.org
  issuerRef:
    name: letsencrypt-production
    kind: ClusterIssuer
  secretName: tls-rancher-ingress

```

This can take anywhere from a few minutes to 15-20 minutes to generate, so sit tight.  You'll know it is ready when
the certificate's `Ready` status shows `True` in the output of:

```bash
kubectl -n cattle-system get certificate rancher-my-org
```

While you're waiting, make sure that your DNS record for `rancher.my.org` points to your Traefik deployment,
instead of a LoadBalancer IP from kubeVIP.
This can be an CNAME record using your Traefik FQDN, or an A record using the same IP address as Traefik.

Once the certificate and DNS record are ready, you can run your Rancher installation with one extra value set to
configure your Ingress provider to use your custom certificate:
```bash

helm install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --set hostname=rancher.my.org \
  --set bootstrapPassword=admin \
  --set ingress.tls.source=secret
```

If you are doing this after already installing Rancher (with the default setting of `ingress.tls.source=rancher`),
you can overwrite the self-generated `tls-rancher-ingress` secret with your own certificate, then update your
deployment. You may want to get your current Rancher version using `helm ls -n cattle-system` and provide it
in your `helm upgrade` command so you don't unexpectedly upgrade your Rancher version.
```bash
helm upgrade rancher rancher-stable/rancher \
  --namespace cattle-system \
  --set hostname=rancher.my.org \
  --set ingress.tls.source=secret \
  --version <DEPLOYED_RANCHER_VERSION>
```

## Ingress TLS Troubleshooting
You can validate the contents of your `tls-rancher-ingress` Secret using commands like this:
```bash
kubectl -n cattle-system get secret tls-rancher-ingress -o jsonpath='{.data}' | jq '."tls.crt"' | tr -d '"' | base64 --decode | openssl x509 -text
```

If you previously had your `rancher.my.org` DNS record associated with your LoadBalancer IP, your browser may be caching
that old record.  You may need to clear your browser's DNS cache, use an Incognito/Private window, etc.


There are also helpful instructions covering a handful of situations in Rancher's documentation:

* [Adding TLS Secrets](https://ranchermanager.docs.rancher.com/getting-started/installation-and-upgrade/resources/add-tls-secrets)
* [Update Rancher Certificate](https://ranchermanager.docs.rancher.com/getting-started/installation-and-upgrade/resources/update-rancher-certificate)



### 7. GitOps via Fleet
1. On GitHub, create a new Repository for **Fleet** 
2. Create Personal Access Key by clicking intitials -> Settings -> Developer Settings -> Personal Access Tokens -> Fine Grained Token -> Generate Token 
	
> [!NOTE] Permissions
> Just limit Fleet to the **fleet-ops** repository I made so it only has access to that

3. Go into Rancher UI and click **Continuous Delivery** from the left menu (Sailboat icon)
	1. Select Clusters and change in the top right corner 'fleet-default' to 'fleet-local'. 
	2. Still under **Continuous Delivery** select 'Dashboard' and hit 'Get Started' and select Git Repos.
		1. Name: fleet (must be lowercase)
		2. Repository URL: (take from GitHub. Enter CORRECT BRANCH e.g. main/master)
		3. Authentication:
			1. HTTP Basic Auth Secret 
				1. Username: Github email
				2. Password: github access token
4. Now, anything I upload to this repository will be automatically applied to my cluster. I can connect gitea to mirror push to this repo so that anything I do in Gitea will get synced to the fleet-ops GitHub repo, which then will apply to my cluster. Or, I can just add my Gitea as a separate fleet instance under **Continuous Delivery** so that I could do either, however, I would rather always pull from one source just to make sure nothing is fucked




### 8. Crowdsec
1. Update traefik values.yaml
	1. Include logging and plugins. See GitHub
2. Add directories and add values.yaml and a middleware for:
	1. Bouncer
	2. Crowdsec
	3. Reflector

##### Reflector

> [!WARNING] ONLY USE THIS CCOMMAND IF NOT INSTALLED YET
> It is built into the deploy script automatically, so I should already have this installed, but if not...

```
helm install \
 reflector emberstack/reflector \
 --create-namespace \
 --namespace reflector
```


##### Update Traefik values file
```
 helm upgrade \
 traefik traefik/traefik \
 --namespace traefik \
 -f /home/hughboi/Helm/Traefik/values.yaml
```


##### Crowdsec
```
 helm install \
 crowdsec crowdsec/crowdsec \
 --create-namespace \
 --namespace crowdsec \
 -f /home/hughboi/Helm/Crowdsec/values.yaml
```


> [!NOTE] IMPORTANT! Take note of the 'default credentials' the terminal spits out
> This is used for the LOCAL dashboard. Not the online one.


1. Test this by banning a local IP
2. Execute into crowdsec-lapi container and run this:
```
cscli decisions add -i IP.HERE
```
3. Test to make sure that IP can't access services routed through Traefik anymore
4. Unblock
```
cscli decisions delete -i IP.HERE
```


##### Bouncer
- Need to apply the manifest **bouncer-middleware.yaml** file to the stack. I can either push it into my Fleet Git repository to be auto applied, or need to use kubectl
```
kubectl apply -f Manifest/Bouncer/bouncer-middleware.yaml
```
- You should now see the crowdsec pods running
- Check the logs for the crowdsec agent and lapi pods. If any errors, just delete the containers, let them spin up again, and should be good to go






***



### 9. GPU Passthrough vm node join
- If I want to utilize a GPU for transcoding for **Immich** or **Jellyfin**, I can create a new VM, join it to the cluster using my deploy.sh script on GitHub, pass the GPU through from proxmox to the VM, and then I can schedule apps to use this gpu passthrough worker node

##### Immich via Helm
https://github.com/immich-app/immich-charts/blob/main/README.md

###### SMB Network Share



### 10. Upgrading Kubernetes Cluster
#### Recommendations Before Upgrading
1. Snapshot / Backup your VMs!
2. Backup data and volumes if necessary
3. Drain nodes / scale down deployments
##### Rancher
1. Consult Compatibility Manager before doing anything
Link: https://www.suse.com/suse-rancher/support-matrix/all-supported-versions/rancher-v2-11-4/

```
helm upgrade rancher-latest/rancher \
  --namespace cattle-system \
  --set hostname=rancher.hughboi.vip \

kubectl -n cattle-system rollout status deploy/rancher
kubectl -n cattle-system get deploy rancher
```



##### Longhorn
- run this from ansible machine:
```
kubectl apply -f https://raw.githubusercontent.com/itshughboi/k3s/main/longhorn.yaml
```
