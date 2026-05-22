> **DEPRECATED** — RKE2 was evaluated as the Kubernetes distribution before k3s was chosen.
> k3s is lighter, has better tooling for this homelab size, and is what's running in production.
> This playbook and its roles are kept as a reference for the RKE2 approach.
> For the active k3s deployment, see `ansible/playbooks/kubernetes/k3s/`.

## Instructions
1. Edit values under group_vars/all.yaml
2. Add add machines to hosts.ini
3. On ansible machine add this to .ssh/config
```
Host 10.10.40.1
  User hughboi
  IdentityFile ~/.ssh/ansible  
Host 10.10.40.2
  User hughboi
  IdentityFile ~/.ssh/ansible  
Host 10.10.40.3
  User hughboi
  IdentityFile ~/.ssh/ansible  
Host 10.10.40.11 
  User hughboi
  IdentityFile ~/.ssh/ansible
Host 10.10.40.12
  User hughboi
  IdentityFile ~/.ssh/ansible
Host 10.10.40.13
  User hughboi
  IdentityFile ~/.ssh/ansible  
```

4. Run the playbook
```
ansible-playbook site.yaml -i inventory/hosts.ini --key-file ~/.ssh/ansible
```


## Verification (run on one of the rke machines)
1. Make sure all nodes are visible
```sh
kubectl get nodes
```

Working Output:
```
rke-agent-1   Ready    <none>                      3m17s   v1.29.4+rke2r1
rke-agent-2   Ready    <none>                      3m21s   v1.29.4+rke2r1
rke-agent-3   Ready    <none>                      3m19s   v1.29.4+rke2r1
rke-srv-1     Ready    control-plane,etcd,master   3m51s   v1.29.4+rke2r1
rke-srv-2     Ready    control-plane,etcd,master   2m27s   v1.29.4+rke2r1
rke-srv-3     Ready    control-plane,etcd,master   3m      v1.29.4+rke2r1
```

2. Make sure necessary pods are visible
```sh
kubectl get pods -n metallb-system
```

Working Output:
```
NAME                          READY   STATUS    RESTARTS   AGE
controller-786f9df989-kjpqq   1/1     Running   0          3m37s
speaker-6nbqv                 1/1     Running   0          3m37s
speaker-9nbvh                 1/1     Running   0          2m57s
speaker-dl2jk                 1/1     Running   0          2m53s
speaker-gsh84                 1/1     Running   0          2m44s
speaker-rtl9c                 1/1     Running   0          2m8s
speaker-sss4w                 1/1     Running   0          2m53s
```