# Lab 2.3 Checklist: Name Resolution

## Resources Created

- [ ] **Private DNS Zone**: `skycraft.internal` exists in `platform-skycraft-swc-rg` (or chosen RG).

## Configuration Validation

- [ ] **Hub Link**:
  - [ ] Linked to `platform-skycraft-swc-vnet`
  - [ ] Auto-registration is **Enabled**
- [ ] **Spoke Link**:
  - [ ] Linked to `prod-skycraft-swc-vnet`
  - [ ] Auto-registration is **Enabled**

## Functional Testing

- [ ] DNS Zone Overview shows 'A' records for any existing VMs.
- [ ] `nslookup` from one VM to another using the `.skycraft.internal` suffix resolves to a private IP.
