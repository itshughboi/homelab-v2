> **DEPRECATED** — Docker Swarm was the original multi-host container orchestration approach.
> It has been superseded by k3s (Kubernetes). The playbook and roles are kept for reference;
> do not use for new deployments.

## Playbook Run
1. Add swarm host ips to ansible /.ssh/config to specify the ansible key file
2. Edit IP's under inventory/inventory.yaml if needed
3. Make sure I have a NFS share on TrueNAS called **swarm**. On dataset, give hughboi full permissions. And on share itself, set mapall user to **hughboi**
4. 'cd' into this playbook and run the following
```sh
ansible-playbook site.yaml -i inventory/inventory.yaml --key-file ~/.ssh/ansible
```

## Testing
1. You should now be able to get to Portainer on any of the swarm hosts (currently including the manager nodes). <br>
i.e. go to any of the following on port **9443** and data will be shared across all <br>
https://10.10.20.1:9443 <br>
https://10.10.20.2:9443 <br>
https://10.10.20.3:9443 <br>
https://10.10.20.11:9443 <br>
https://10.10.20.12:9443 <br>
https://10.10.20.13:9443 <br>