- This repo is setup to run on my Macbook as I'm assuming I don't have any other infrastructure. I reference my Macbook SSH key in the group_vars in the .ini file and I just need to put in whatever the existing IP is for netboot. I assume I don't have my network fully up yet, so just put whatever DHCP IP it gets in the `.ini`. 
- The playbook puts the files inside of `/opt` instead of `/home/hughboi`!!!
- Make sure to update `hosts.ini` with the IP of netboot first !!!

###### Mac Ansible
- Install via brew
```sh
brew install ansible
```


### Best Practice:
- Setup DHCP reservation on Unifi router so that netboot can always be on a dedicated IP for provisioning/PXE booting. Assign it to the provisioning VLAN.
- Setup a webhook pull from Github so that the answer.toml is always up to date. DO NOT PUSH unless I add .gitignore for `initrd` and `vmlinuz`

#### Run Playbook (Sudo Password Required)
```
ansible-playbook - i hosts.ini setup-netboot.yaml --ask-become-pass
```
`--ask-become-pass`: prompts you to put in sudo password

#### Run Playbook (No sudo password)
```sh
sudo visudo
```
- Add this line to allow hughboi to run sudo without password
```sh
hughboi ALL=(ALL) NOPASSWD: ALL
```
- Run playbook
```sh
ansible-playbook - i hosts.ini setup-netboot.yaml
```

#### Verify netboot HTTP
```
curl http://10.10.99.99:8080 # IP of Le Potato
```
- I should get a success message where it shows HTML of page