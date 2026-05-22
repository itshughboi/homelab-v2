### Running Playbook

1. go onto ansible machine and cd to playbook
```
ansible-playbook update.yaml -i inventory.ini
```
^^ This only works if you have key authentication setup. Otherwise, run the following. You would also do this if you need to become sudo with the '--ask-become-pass'
```
ansible-playbook update.yaml -i inventory.ini --key-file ~/.ssh/ansible --ask-become-pass
```

***


### Manual Commands to update to newest Ubuntu Server LTS
1. Backup data
2. Update current version
```
sudo apt update
sudo apt upgrade
sudo apt dist-upgrade
```

3. Install update manager
```
sudo apt install update-manager-core
```

4. Check curent distribution
```
lsb_release -a
```

5. Upgrade:
```
sudo do-release-upgrade -d
```

7. Follow on-screen instructions
8. Cleanup
```
sudo apt autoremove
sudo apt clean
```
