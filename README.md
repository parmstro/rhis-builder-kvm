# rhis-builder-kvm
Build KVM hypervisors and connect them to Satellite

Of course this will use rhis-builder-pipelines/platform_node_build to create the instances.
The hostgroup on Satellite will have an identifier for AAP post-provisioning callback to run.
This project will provide the post-provisioning code and will be synchronized to the AAP server.

Once the system is up, the compute resource will get configured in Satellite.
