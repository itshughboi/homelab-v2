### Running the playbook
```
ansible-playbook harden.yaml -i inventory.ini
```


##### .cfg file
- if using a ansible.cfg file, that specifies where the inventory file is so all you have to do is this:
```
ansible-playbook harden.yaml
```


#### Hardening Targets
1. Enable Firewall (UFW)
2. Enable Fail2ban (create copy of jail.conf to make an editiable copy)
3. Add hughboi to sudo group
4. Install VPN agent (tailscale) << Optional



***

### Manual Commands

##### 1. Initial Config
- Storage: NON-LVM
##### 2. Post-install
###### Sudo permissions
`sudo usermod -aG sudo hughboi` >> add hughboi to sudo group. Log out + log in

######  Firewall
`sudo ufw allow 22` // Alternatively: `ufw allow OpenSSH`
`sudo ufw enable`
`sudo ufw reload`

###### Updates
`sudo apt update && sudo apt upgrade -y`

###### Fail2ban (look at this more. Need to know how to get into logs to verify)
`sudo apt install fail2ban -y` >> installs

`cd /etc/fail2ban` 

`sudo cp jail.conf jail.local` >> makes editable copy. IMPORTANT!
`sudo nano jail.local` >> edit bantimes

`sudo systemctl enable fail2ban`
`sudo systemctl start fail2ban`

###### Tailscale
`curl -fsSL https://tailscale.com/install.sh | sh`

`sudo tailscale up`