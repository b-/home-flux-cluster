tag := "30"
template := "30000"
prefix := "3000"
ciuser := `yq e .bootstrap_nodes.master[0].password /home/bri/dev/home-flux-cluster/bootstrap/vars/config.yaml`
cipassword := `yq e .bootstrap_nodes.master[0].username /home/bri/dev/home-flux-cluster/bootstrap/vars/config.yaml`

# Default task: just list the tasks
_default:
  just --list

clone_vm node_id:
	ssh macpro qm clone {{template}} {{prefix}}{{ node_id }} --pool onedr0p-k3s ;
	ssh macpro qm set {{prefix}}{{ node_id }} -efidisk0 zssd:1,pre-enrolled-keys=0 -boot order=scsi0 -net0 "virtio,bridge=vmbr0,tag={{tag}}" -ipconfig0 "ip=192.168.30.3{{ node_id }}/24,gw=192.168.30.1,ip6=auto" -sshkey /root/pve-macpro.pub -ciuser "{{ciuser}}" -cipassword "{{cipassword}}"

deps:
  task deps
  task brew:deps
  task configure

name_vm node_id name:
	ssh macpro qm set {{prefix}}{{node_id}} --name {{name}}

start_vm node_id:
	ssh macpro qm start {{prefix}}{{node_id}}

stop_vm node_id:
	ssh macpro qm stop {{prefix}}{{node_id}}

destroy_vm node_id:
  -ssh macpro qm stop {{prefix}}{{node_id}}
  ssh macpro qm destroy {{prefix}}{{node_id}}

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

build_kube:
  task configure
  task ansible:prepare
  task ansible:list
  task ansible:ping
  task ansible:install
  flux check --pre
  task cluster:install

full_rebuild:
  just rebuild
  sleep 30s
  just build_kube
  -watch -d task cluster:resources

new_clone_rebuild:
  just deps
  just full_rebuild
