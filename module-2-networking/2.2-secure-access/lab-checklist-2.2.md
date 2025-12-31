# Lab 2.2 Checklist: Secure Access

## Resources Created

- [ ] **ASGs Created**:
  - [ ] `prod-skycraft-swc-asg-auth`
  - [ ] `prod-skycraft-swc-asg-world`
  - [ ] `prod-skycraft-swc-asg-db`
- [ ] **NSGs Created**:
  - [ ] `prod-skycraft-swc-nsg`

## NSG Rules Validation

- [ ] **Inbound Rule `AllowAuthServer`**:
  - Allow TCP 3724
  - Destination: `prod-skycraft-swc-asg-auth`
- [ ] **Inbound Rule `AllowWorldServer`**:
  - Allow TCP 8085
  - Destination: `prod-skycraft-swc-asg-world`
- [ ] **Inbound Rule `AllowAppToDB`**:
  - Allow TCP 3306
  - Destination: `prod-skycraft-swc-asg-db`

## Association

- [ ] `prod-skycraft-swc-nsg` is associated with:
  - [ ] `snet-auth`
  - [ ] `snet-world`
  - [ ] `snet-db`

## Bastion (If Deployed)

- [ ] `AzureBastionSubnet` exists in Hub VNet.
- [ ] Bastion Host is in **Running** state.
