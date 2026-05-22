## Ansible VM Setup

> [!NOTE] Ansible Cloud-Init
> Create and full clone a cloud-init template
```sh
sudo apt update
sudo apt install software-properties-common -y
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install ansible -y
```
1. Check successful installation. In output take note of "config file" path
```sh
ansible --version
```

### Inventory (yaml or ini)
This is a list of machines that the playbook can target
- Default location for ansible host file
```sh
sudo nano /etc/ansible/hosts
```
Option 1 (Not-Recommended): Use default ansible host file (above), See full /ansible/inventory/all_hosts.ini for template hosts.ini file // https://raw.githubusercontent.com/itshughboi/iac/refs/heads/main/ansible/inventory/all_hosts.ini

.ini syntax
```
[k3s]
10.10.30.1
10.10.30.2
10.10.30.3
10.10.30.11
10.10.30.12
10.10.30.13
		
[masters]
10.10.30.1
10.10.30.2
10.10.30.3

[workers]
10.10.30.11
10.10.30.12
10.10.30.13
```

**All Vars**
- Add this to the top of the .ini to apply global variables. Essentially this changes inventory to use specified Ansible key file for authentication
```
[all:vars]
ansible_user='hughboi'
ansible_become=yes
ansible_become_method=sudo
ansible_ssh_private_key_file=~/.ssh/ansible
```



Option 2 (Recommended): inventory.yaml // https://raw.githubusercontent.com/itshughboi/iac/refs/heads/main/ansible/inventory/inventory.yaml. Gives a better granular way to control which hosts are group to what, rather than doing it from the default location

.yaml syntax
```
all:
  children:
    proxmox:
      hosts:
        pve-srv-1:
          ansible_host: 10.10.10.1
          ansible_user: hughboi
        pve-srv-2:
          ansible_host: 10.10.10.2
          ansible_user: hughboi
        pve-srv-3:
          ansible_host: 10.10.10.3
          ansible_user: hughboi
        pve-srv-3:
          ansible_host: 10.10.10.3
          ansible_user: hughboi
    docker_hosts:
      hosts:
        docker:
          ansible_host: 10.10.10.10
          ansible_user: hughboi
    k3s:
      hosts:
        k3s-master-1:
          ansible_host: 10.10.30.1
          ansible_user: hughboi
        k3s-master-2:
          ansible_host: 10.10.30.2
          ansible_user: hughboi
        k3s-master-3:
          ansible_host: 10.10.30.3
          ansible_user: hughboi
        k3s-worker-1:
          ansible_host: 10.10.30.11
          ansible_user: hughboi
        kes-worker-2:
          ansible_host: 10.10.30.12
          ansible_user: hughboi
		k3s-worker-3:
		  ansible_host: 10.10.30.13
          ansible_user: hughboi
    storage:
      hosts:
        truenas:
          ansible_host: 10.10.10.5
          ansible_user: hughboi
        pbs:
          ansible_host: 10.10.10.6
          ansible_user: hughboi
  vars:
    ansible_ssh_private_key_file: ~/.ssh/ansible
```

- ^^ These allow you to target specific groups from this one inventory file when running playbooks


***


### SSH Keys
1. Create new SSH keys. Leave password empty so it can be automated. We'll need this for all other **Cloud-Init** machines
```sh
ssh-keygen -t ed25519 -C "ansible" -f ~/.ssh/ansible
ls ~/.ssh/ansible*
```
- You should see both private and public key here

2. Restrict SSH permissions
```sh
chmod 600 ~/.ssh/ansible
```

3. Enable Public Key Authentication on Remote Machines
```
sudo nano /etc/ssh/sshd_config
```
```
PubkeyAuthentication yes
PasswordAuthentication no
```
```
sudo systemctl restart sshd
```

4. Copy SSH key to remote machine. Needs password authentication enabled
```sh
cd ~/.ssh
ssh-copy-id -i ~/.ssh/ansible.pub hughboi@remote-machine-ip
```

5. Test Ansible connections with SSH key
```sh
ansible all -m ping --private-key ~/.ssh/ansible
```


Add the following to Inventory file to use Ansible Keys and not have to sepcify private key
```
[all:vars]
ansible_user='hughboi'
ansible_become=yes
ansible_become_method=sudo
ansible_ssh_private_key_file=~/.ssh/ansible
```

#### Verify Inventory & SSH Keys: I may need to attempt ssh, accept the key host, get denied with public key, then try again once it's in authorized hosts
```
ansible all -m ping 
```



***



## Ansible Secrets

1. Create a 'secrets_file.enc' that contains sensitive values
```
api_key: SuperSecret
```

2. Encrypt the secret
```
ansible vault encrypt secrets_file.enc
```
3. Add in vault password and you will see the file gets totally encrypted with AES-256
##### Using playbook while referencing vault encrypted file
1. Create a new fileecalled something like *secret* or *passwords*
```
ansible-playbook PLAYBOOKNAME -i inventory.yaml -e @secrets_file.enc --private-file ~/.ssh/ansible --ask-become-pass --vault-password-file secret
```

##### Editing encrypted secrets file
```
ansible-vault edit secrets_file.enc
```
- As soon as you write, it will encrypt it again



## Ansible Secrets Continued...

File Setup:
(on ansible host): /home/hughboi/secrets/APPS << all secrets for each app split up
/home/hughboi/secrets/global << global variables I can use throughout all applications

### Create secret
1. Setup the vault on ansible
```
ansible-vault create group_vars/docker/mealie.yml
```

> [!NOTE] group_vars
> Ansible auto loads variables from a group_vars/ directory **if the name matches a group of host in your inventory**. In this case **docker** matches a host name in /home/hughboi/inventory/hosts.yml

2. Create secrets file:
```
ansible-vault create group_vars/appname/vault.yml
```

> [!NOTE] appname
> appname in the above command should match a group or host from inventory.yml


2.  Now put in the .env values into this app-vault.yml file
3. Then in Ansible playbook, you can reference the values like such
```
- name: Deploy Immich
  hosts: dockerhosts
  vars:
    app_name: immich
  tasks:
    - name: Create .env file
      template:
        src: env.j2
        dest: "/home/hughboi/code/docker/APPLICATION/{{ app_name }}/.env"
      vars:
        env_vars:
          - { name: "DB_PASSWORD", value: "{{ vault_immich_db_password }}" }
          - { name: "API_KEY", value: "{{ vault_immich_api_key }}" }
}
```


### **What happens when Ansible runs:**
- Ansible decrypts the `vault.yml` secrets (like passwords, API keys).
- It uses those values to **generate a `.env` file** or pass them inline to your `docker-compose` command.
- The container is brought up using `docker compose`, and it reads the `.env` file during startup.
- Once the container is up, the `.env` file **still exists on the host filesystem** unless you explicitly remove it as part of the playbook.

