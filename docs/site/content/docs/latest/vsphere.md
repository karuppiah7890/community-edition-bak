WIP - DRAFT - WIP - DRAFT

<!-- https://github.com/vmware-tanzu-private/tkg-docs/tree/main/tkg-docs.vmware.com/vsphere -->
# Prepare to Deploy Management Clusters to vSphere

This topic explains how to prepare before you deploy a management or stand-alone cluster on vSphere.

Before you can use the Tanzu CLI or the Tanzu Community Edition Installer to deploy a management or workload cluster, you must prepare your vSphere environment. You must:
   - Make sure that vSphere meets the general requirements.
   - Download and import the OVF image and covert it to a template.
   - Create an ssh key pair (if you don't already have one), you will provide the public key part of the SSH key pair to Tanzu Community Edition Installer when you deploy the management or workload cluster. 


## Before you begin

- **ENG TEAM -  PLEASE COMMENT ON VERSIONS** A vSphere 7, vSphere 6.7u3, VMware Cloud on AWS, or Azure VMware Solution account with:
    - **vSphere 6.7**: an Enterprise Plus license
    - **vSphere 7** see [vSphere with Tanzu Provides Management Cluster](#mc-vsphere7) below.
- **ENG TEAM -  PLEASE COMMENT ON OBJECTS**Your vSphere instance has the following objects in place:
    - Either a standalone host or a vSphere cluster with at least two hosts
    - If you are deploying to a vSphere cluster, ideally vSphere DRS is enabled.
    - Optionally, a resource pool in which to deploy the Tanzu Community Edition Instance
    - A VM folder in which to collect the Tanzu Community Edition VMs
    - A datastore with sufficient capacity for the control plane and worker node VM files
    - If you intend to deploy multiple Tanzu Community Edition instances to the same vSphere instance, create a dedicated resource pool, VM folder, and network for each instance that you deploy.
- **ENG TEAM -  PLEASE COMMENT ON OBJECTS** A network:  with:
    - A DHCP server to which to connect the cluster node VMs that Tanzu Community Edition deploys. The node VMs must be able to connect to vSphere.
    - A set of available static virtual IP (VIP) addresses for the clusters that you create, including management and Tanzu Kubernetes clusters. Each control plane and worker node requires a static IP address. Make sure that these IP addresses are not in the DHCP range, but are in the same subnet as the DHCP range. For more information, see [Static VIPs and Load Balancers for vSphere](#load-balancer).
    **NOTE:** To make DHCP-assigned IP addresses static, after you deploy the cluster, configure a DHCP reservation with enough IPs for each control plane and worker node in the cluster.
    - Traffic allowed out to vCenter Server from the network on which clusters will run.
    - Traffic allowed between your local bootstrap machine and port 6443 of all VMs in the clusters you create. Port 6443 is where the Kubernetes API is exposed.
    - Traffic allowed between port 443 of all VMs in the clusters you create and vCenter Server. Port 443 is where the vCenter Server API is exposed.
    - Traffic allowed between your local bootstrap machine out to the image repositories listed in the management cluster Bill of Materials (BoM) file, over port 443, for TCP. The BoM file is under `~/.tanzu/tkg/bom/` and its name includes the Tanzu Community Edition version, for example `bom-1.3.0+vmware.1.yaml` for v1.3.0.
    - The Network Time Protocol (NTP) service running on all hosts, and the hosts running on UTC. To check the time settings on hosts:
       1. Use SSH to log in to the ESXi host.
       1. Run the `date` command to see the timezone settings.
       1. If the timezone is incorrect, run `esxcli system time set`.
- If your vSphere environment runs NSX-T Data Center, you can use the NSX-T Data Center interfaces when you deploy management clusters. Make sure that your NSX-T Data Center setup includes a segment on which DHCP is enabled. Make sure that NTP is configured on all ESXi hosts, on vCenter Server, and on the bootstrap machine.

## Procedure 

Before you can deploy a management cluster to vSphere, you must import a base image template for the OS and Kubernetes versions that the management cluster nodes run on into vSphere.
VMware publishes base image templates in OVA format for each OS and Kubernetes version supported for management and workload clusters. After importing the OVA, you must convert the resulting VM into a VM template.
<!-- KOR: need a link here to OVA download-->


1. Download an OVA for the management cluster nodes, which can be either: 

   - Kubernetes v1.20.4: **Ubuntu v20.04 Kubernetes v1.20.4 OVA**
   - Kubernetes v1.20.4: **Photon v3 Kubernetes v1.20.4 OVA**
   
   You can also download base image templates for other OS and Kubernetes versions that you expect to create clusters from, or you can download them later.

2. Complete the following steps to deploy the OVF template:
   a. In the vSphere Client, right-click an object in the vCenter Server inventory, select **Deploy OVF template**.
   b. Select **Local file**, click the button to upload files, and navigate to the downloaded OVA file on your local machine.
   c. Follow the installer prompts to deploy a VM from the OVA.

    - Accept or modify the appliance name
    - Select the destination datacenter or folder
    - Select the destination host, cluster, or resource pool
    - Accept the end user license agreements (EULA)
    - Select the disk format and destination datastore
    - Select the network for the VM to connect to
    
    **NOTE**: If you select thick provisioning as the disk format, when Tanzu Community Edition creates cluster node VMs from the template, the full size of each node's disk will be reserved. This can rapidly consume storage if you deploy many clusters or clusters with many nodes. However, if you select thin provisioning, as you deploy clusters this can give a false impression of the amount of storage that is available. If you select thin provisioning, there might be enough storage available at the time that you deploy clusters, but storage might run out as the clusters run and accumulate data.
   d. Click **Finish** to deploy the VM.
   e. When the OVA deployment finishes, right-click the VM and select **Template** > **Convert to Template**.

   **NOTE**: Do not power on the VM before you convert it to a template.
<!--In the **VMs and Templates** view, right-click the new template, select **Add Permission**, and assign the `tkg-user` to the template with the `TKG` role.

   For information about how to create the user and role for Tanzu Community Edition, see [Required Permissions for the vSphere Account](#vsphere-permissions) above. -->
   
3. Complete the following steps to create an SSH Key Pair: 

   a. On the bootstrap machine on which you will run the Tanzu CLI, run the following `ssh-keygen` command:  
   ``ssh-keygen -t rsa -b 4096 -C "email@example.com"``
   b. At the prompt `Enter file in which to save the key (/root/.ssh/id_rsa):` press Enter to accept the default.
   c. Enter and repeat a password for the key pair.
   d. Add the private key to the SSH agent running on your machine, and enter the password you created in the previous step:  
   ``ssh-add ~/.ssh/id_rsa``
   e. Open the file `.ssh/id_rsa.pub` in a text editor so that you can easily copy and paste it when you deploy a management cluster.
 

#


## <a id="what-next"></a> What to Do Next

For production deployments, it is strongly recommended to enable identity management for your clusters. For information about the preparatory steps to perform before you deploy a management cluster, see [Enabling Identity Management in Tanzu Community Edition](enabling-id-mgmt.md).

If you are using Tanzu Community Edition in an environment with an external internet connection, once you have set up identity management, you are  ready to deploy management clusters to vSphere.

- [Deploy Management Clusters with the Installer Interface](deploy-ui.md). This is the preferred option for first deployments.
- [Deploy Management Clusters from a Configuration File](deploy-cli.md). This is the more complicated method,  that allows greater flexibility of configuration and automation.
- If you are using Tanzu Community Edition in an internet-restricted environment, see [Deploying Tanzu Community Edition in an Internet-Restricted Environment](airgapped-environments.md) for the additional steps to perform.
- If you want to deploy clusters to Amazon EC2 and Azure as well as to vSphere, see [Prepare to Deploy Management Clusters to Amazon EC2](aws.html) and [Prepare to Deploy Management Clusters to Microsoft Azure](azure.md) for the required setup for those platforms.