tag := "30"
template := "30000"
vmid_base := "30000"
ciuser := `yq e .bootstrap_nodes.master[0].username /home/bri/dev/home-flux-cluster/bootstrap/vars/config.yaml`
# get_ vars are basically hacky functions to not show the actual value in the immediate output
get_ciuser := "`just --evaluate ciuser`"
cipassword := `yq e .bootstrap_nodes.master[0].password /home/bri/dev/home-flux-cluster/bootstrap/vars/config.yaml`
get_cipassword := "`just --evaluate cipassword`"
queues := "6"
ip_base := "192.168.30.30/24"
gw := "192.168.30.1"
sshkey := "/root/pve-macpro.pub"
storage := "zssd"

# Default task: just list the tasks
_default:
  just --list

# Build an IP/prefix by adding {{ip_base}} + {{node_id}}
_ipaddressFactory node_id:
  #!/usr/bin/env python
  import ipaddress
  base=ipaddress.ip_interface('{{ip_base}}')
  node_ip=ipaddress.ip_interface(f"{base.ip + {{node_id}}}/{base.network.netmask}")
  print(str(node_ip))

# Build a VMID by adding {{vmid_base}} + {{node_id}}
_vmidFactory node_id:
  @python -c "print({{vmid_base}} + {{node_id}})"

clone_vm node_id:
	ssh macpro qm clone {{template}} $(just _vmidFactory {{ node_id }}) --pool onedr0p-k3s ;
	ssh macpro qm set $(just _vmidFactory {{node_id}}) -efidisk0 {{storage}}:1,pre-enrolled-keys=0 -boot order=scsi0 -net0 "virtio,bridge=vmbr0,tag={{tag}},queues={{queues}}" -ipconfig0 "ip=$(just _ipaddressFactory {{node_id}}),gw={{gw}}" -sshkey {{sshkey}} -ciuser "{{get_ciuser}}" -cipassword "{{get_cipassword}}"

deps:
  task deps
  task brew:deps
  task configure


name_vm node_id name:
	ssh macpro qm set $(just _vmidFactory {{node_id}}) --name {{name}}

start_vm node_id:
	ssh macpro qm start $(just _vmidFactory {{node_id}})

stop_vm node_id:
	ssh macpro qm stop $(just _vmidFactory {{node_id}})

destroy_vm node_id:
  -ssh macpro qm stop $(just _vmidFactory {{node_id}})
  ssh macpro qm destroy $(just _vmidFactory {{node_id}})

create_controller node_id:
  just clone_vm {{node_id}}
  just name_vm {{node_id}} "k3s-controller-0{{node_id}}"
  just start_vm {{node_id}}

create_worker node_id:
  just clone_vm {{node_id}}
  just name_vm {{node_id}} "k3s-worker-0{{node_id}}"
  just start_vm {{node_id}}

rebuild:
  -just destroy_vm 1
  just create_controller 1
  -just destroy_vm 2
  just create_worker 2

wait_for_ping:
  until task ansible:ping ; do sleep 1s ; done

build_kube:
  task configure
  task ansible:prepare
  task ansible:list
  just wait_for_ping
  task ansible:install
  flux check --pre
  task cluster:install

full_rebuild:
  just rebuild
  sleep 15s
  just build_kube
  -watch -d task cluster:resources

new_clone_rebuild:
  just deps
  just full_rebuild
