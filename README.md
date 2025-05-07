# HyperV-Replica-CertSetup
PowerShell script to create/install Self-signed certificates to be used for HTTPS based HyperV Replica feature for 2 Windows Server hosts. It will also disable CRL checks for the HyperV replica communication, as they will not work with self-signed certs.

## Prerequisites

You need FQDNs for both HyperV hosts. If you are planning to use a dedicated network connection for the replication traffic, you may add the FQDN hostnames into the `hosts` file of the servers.
Both FQDNs need to be resolveable on each server before you run the script.

## Usage

Start on the primary host with:
```
.\HyperV-Replica-CertSetup.ps1 -PrimaryFQDN "yourfirst.hv.local" -SecondaryFQDN "yoursecond.hv.local"
```

When the script has finished, copy both the PoSh script file and the `yoursecond.hv.local.pfx` to the Secondary HyperV host and run:
```
.\HyperV-Replica-CertSetup.ps1 -PrimaryFQDN "yourfirst.hv.local" -SecondaryFQDN "yoursecond.hv.local" -SecondaryImport
```

That's it, you can now configure HTTPS based HyperV replica between the 2 hosts. I'd recommend to remove the PFX files from both hosts.

## Disclaimer
The script is provided as-is without any support or guarantee that it will work as expected. I have tested it with 2 Windows Server 2025 HyperV hosts.


Have fun,

Juergen