### Running Playbook

1. go onto ansible machine and cd to playbook
```
ansible-playbook install.yaml -i inventory.ini
```
^^ This only works if you have key authentication setup. Otherwise, run the following. You would also do this if you need to become sudo with the '--ask-become-pass'
```
ansible-playbook install.yaml -i inventory.ini --key-file ~/.ssh/ansible --ask-become-pass
```
