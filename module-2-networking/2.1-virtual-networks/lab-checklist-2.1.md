# Lab 2.1 Checklist: Virtual Networks

Use this checklist to ensure you have correctly completed the lab.

## Architecture Validation

- [ ] Resource Group `platform-skycraft-swc-rg` contains the Hub VNet.
- [ ] Resource Group `prod-skycraft-swc-rg` contains the Spoke VNet.
- [ ] Two Virtual Networks exist: `platform-skycraft-swc-vnet` and `prod-skycraft-swc-vnet`.

## Hub VNet Configuration (platform-skycraft-swc-vnet)

- [ ] **Address Space**: `10.0.0.0/16`
- [ ] **Subnets**:
  - [ ] `AzureBastionSubnet` exists with range `10.0.1.0/26`
  - [ ] `AzureFirewallSubnet` exists with range `10.0.2.0/26`
  - [ ] `GatewaySubnet` exists with range `10.0.3.0/27`
  - [ ] `SharedSubnet` exists with range `10.0.4.0/24`

## Spoke VNet Configuration (prod-skycraft-swc-vnet)

- [ ] **Address Space**: `10.1.0.0/16`
- [ ] **Subnets**:
  - [ ] `AuthSubnet` exists with range `10.1.1.0/24`
  - [ ] `WorldSubnet` exists with range `10.1.2.0/24`
  - [ ] `DatabaseSubnet` exists with range `10.1.3.0/24`

## Peering Configuration

- [ ] **Hub VNet** has a peering named `peer-hub-to-prod`.
- [ ] **Spoke VNet** has a peering named `peer-prod-to-hub`.
- [ ] **Peering Status** is `Connected` for both.

## Connectivity Test (Optional but Recommended)

- [ ] Create a VM in `SharedSubnet` (Hub)
- [ ] Create a VM in `WorldSubnet` (Spoke)
- [ ] Verify you can ping from Hub VM to Spoke VM (using private IP)
  > **Note**: You may need to allow ICMP in OS firewall or NSG (covered in next lab) for ping to work.
