# rhis-builder-kvm
Build KVM hypervisors and connect them to Satellite

Steps to implement:

1. In your rhis-builder-inventory, edit the template that creates your list of kvm hosts.
   Regenerate your inventory.
   ```
   rhis-builder-inventory/inventory_templates/group_vars/provisioner/kvm_hosts.yml
   
   ./inventory_update.sh --basevars-file your.domain_inventory_basevars.yml

   ```

2. Launch your rhis-provisioner container using the help script created in your inventory for your domain.
   ```
   example.ca.25.sh
   ``` 
  
3. In your container instance, run:
   ```
   cd /rhis/rhis-builder-pipelines
   ./deploy_kvm_hypervisors.sh
   ```

4. After your hypervisors have deployed. You can run the kvm_host role from the rhis-builder-kvm directory against the kvm_hosts in your inventory using the helper script.

   Your inventory should have something like:
   ```
      kvm_hosts:
         hosts:
            kvm1.example.ca:
            kvm2.example.ca:
   ```
   Then you can run the following:

   ```
   cd /rhis/rhis-builder-kvm
   ./configure_kvm_hypervisors.sh
   ```
   
   This will configure your kvm systems with certificates issued by IdM and configure libvirtd for using TLS and optionally SASL for authentication.

   At the time of this writing, Satellite does not pick up the kerberos keytab for Libvirt compute resources, so SASL authentication is turned of by default.

   The Satellite system will be configured with kvm ready certificates by default as part of the satellite_post role. Sample satellite compute resources are also configured.

   FUTURE:
   Network and Storage configuration will be added shortly. Currently, this is a manual process. The goal is to add qubinode collection functionality.

   We will independently implement the ability to create a Satellite compute resource to this project so that you can use RHIS easily in brownfield Satellite environments to add KVM compute resources where RHIS has not been used to deploy the Satellite.

   The next step will be to use satellite to deploy new systems via kickstart and convert them to kvm qcow images and register them back to satellite for image based deployments.

   Lastly we will perform the complete configuration of KVM systems will via an Ansible Callback used for the kvm hypervisor hostgroup in Satellite.

     - satellite provisioning will integrate the system into IdM
     - satellite provisioning will deploy cockpit
     - satellite provisioning will configure an ansible call back for kvm host integration workflow  
     - the workflow runs the standard callback to configure motd, issue, time servers, and  generates certificates in IdM for the cockpit Web UI
     - the workflow will then implement the roles included in this project
     - validates the environment
     - configures firewalld
     - fetches a keytab for the libvirt service to handle kerberos communications from satellite capsule services
     - generates certificates in IdM for the libvirt/libvirtclient tls connections
     - configures libvirtd to use the generated certificates (and sasl communications)
     - configures a satellite compute resource for the kvm host.
     - configures one or more satellite compute profiles for the kvm host.
     - configures a basic hostgroup for host deployment using the compute resource.
     - optionally, validates that a test system can be deployed via kickstart.
     - optionally, deploys a qcow image to the kvm server, registers the image with the compute resource and validates that the satellite can deploy the test system.
     